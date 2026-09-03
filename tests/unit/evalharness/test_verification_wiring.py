# Copyright 2026 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Unit tests for post-agent verification wiring in the default harness."""

import time
from unittest.mock import patch

import pytest

from devops_bench.evalharness.default import DefaultEvalHarness
from devops_bench.evalharness.hold import HoldObservation
from devops_bench.verification.base import MIN_LEAF_BUDGET_SECONDS, VerificationResult
from devops_bench.verification.spec import parse_entries

_HOLD_SPEC = [
    {
        "name": "no-scale-down",
        "role": "safeguard",
        "severity": "catastrophic",
        "mode": "hold",
        "check": {
            "type": "resource_property",
            "kind": "deployment",
            "resource_name": "storefront",
            "op": "exists",
        },
    }
]

_SPEC = [
    {
        "name": "web-ready",
        "role": "objective",
        "weight": 3,
        "check": {"type": "pod_healthy", "selector": "app=web", "namespace": "shop"},
    },
    {
        "name": "nothing-in-default",
        "role": "safeguard",
        "severity": "catastrophic",
        "check": {
            "type": "resource_property",
            "kind": "deployment",
            "selector": "app=web",
            "namespace": "default",
            "op": "absent",
        },
    },
]


def _harness() -> DefaultEvalHarness:
    harness = DefaultEvalHarness.__new__(DefaultEvalHarness)
    # Minimal attributes replace_placeholders() reads unconditionally
    # (project_id, app_location) or falls back to when the caller's
    # target_deployment / namespace argument is falsy.
    harness.project_id = "proj"
    harness.app_location = "us-central1"
    harness.target_deployment = "web"
    harness.namespace = "shop"
    return harness


def test_report_carries_the_scoring_vocabulary_for_every_entry() -> None:
    entries, errors = parse_entries(_SPEC)
    assert errors == []
    ok = VerificationResult(success=True, elapsed_time=0.1, reason="fine")
    with patch("devops_bench.evalharness.default.VerifierAgent.run_entry", return_value=ok):
        report = _harness()._run_verification(entries)

    assert [r["name"] for r in report] == ["web-ready", "nothing-in-default"]
    assert report[0]["role"] == "objective"
    assert report[0]["weight"] == 3
    assert report[0]["mode"] == "converge"
    assert report[0]["severity"] is None
    assert report[1]["severity"] == "catastrophic"
    assert report[1]["mode"] == "assert"
    assert all(r["success"] is True for r in report)


def test_one_raising_entry_does_not_abort_the_rest() -> None:
    """Entries evaluate concurrently, so which one raises is a race; either can.

    The contract under test is only that one entry raising never aborts the
    other, not which of the two concurrently-started entries hits the
    ``RuntimeError`` first.
    """
    entries, _ = parse_entries(_SPEC)
    ok = VerificationResult(success=True, elapsed_time=0.1, reason="fine")
    with patch(
        "devops_bench.evalharness.default.VerifierAgent.run_entry",
        side_effect=[RuntimeError("cluster gone"), ok],
    ):
        report = _harness()._run_verification(entries)

    assert len(report) == 2
    failures = [r for r in report if r["success"] is False]
    successes = [r for r in report if r["success"] is True]
    assert len(failures) == 1
    assert len(successes) == 1
    assert "cluster gone" in failures[0]["reason"]


def test_no_entries_yields_an_empty_report() -> None:
    assert _harness()._run_verification([]) == []


def test_child_results_are_serialised_onto_the_report() -> None:
    entries, _ = parse_entries(_SPEC[:1])
    child = VerificationResult(success=False, elapsed_time=0.0, reason="no pods", name="c")
    parent = VerificationResult(
        success=False, elapsed_time=0.2, reason="child failed", children=[child]
    )
    with patch("devops_bench.evalharness.default.VerifierAgent.run_entry", return_value=parent):
        report = _harness()._run_verification(entries)

    assert report[0]["children"][0]["reason"] == "no pods"


def test_the_report_feeds_rollup_directly() -> None:
    from devops_bench.verification.rollup import rollup

    entries, _ = parse_entries(_SPEC)
    ok = VerificationResult(success=True, elapsed_time=0.0, reason="fine")
    with patch("devops_bench.evalharness.default.VerifierAgent.run_entry", return_value=ok):
        report = _harness()._run_verification(entries)

    scores = rollup(report)
    assert scores.correctness == 1.0
    assert scores.catastrophic == 1.0
    assert scores.recoverable_safety is None


def test_converge_entries_get_the_min_of_per_entry_and_remaining_budget(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A tight total budget caps each converging entry below its per-entry timeout."""
    entries, errors = parse_entries(_SPEC[:1] + [{**_SPEC[0], "name": "web-ready-2"}])
    assert errors == []
    monkeypatch.setattr("devops_bench.evalharness.default.VERIFICATION_TOTAL_BUDGET_SEC", 5.0)

    seen_timeouts: list[float] = []

    def fake_run_entry(entry: object, timeout_sec: float = 120) -> VerificationResult:
        seen_timeouts.append(timeout_sec)
        return VerificationResult(success=True, elapsed_time=0.0, reason="ok")

    with patch(
        "devops_bench.evalharness.default.VerifierAgent.run_entry", side_effect=fake_run_entry
    ):
        _harness()._run_verification(entries, timeout_sec=120)

    assert len(seen_timeouts) == 2
    assert all(0 < t <= 5.0 for t in seen_timeouts)


def test_converge_entry_is_recorded_as_budget_exhausted_once_the_total_is_gone(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    entries, errors = parse_entries(_SPEC[:1] + [{**_SPEC[0], "name": "web-ready-2"}])
    assert errors == []
    # Entries evaluate concurrently, so pin the worker cap to 1 to force the
    # two entries through one worker in submission order -- the same
    # genuine-exhaustion shape a real spec hits when it has more entries
    # than the worker cap, without a flaky race on which entry the budget
    # ran out under.
    monkeypatch.setattr("devops_bench.evalharness.default._MAX_PARALLEL_WORKERS", 1)
    # Above MIN_LEAF_BUDGET_SECONDS so the first entry clears the guard; the
    # sleep below then drops the remainder under it for the second entry.
    total_budget = MIN_LEAF_BUDGET_SECONDS * 1.2
    monkeypatch.setattr(
        "devops_bench.evalharness.default.VERIFICATION_TOTAL_BUDGET_SEC", total_budget
    )

    def fake_run_entry(entry: object, timeout_sec: float = 120) -> VerificationResult:
        sleep_sec = MIN_LEAF_BUDGET_SECONDS * 0.3  # outruns the tiny total budget
        time.sleep(sleep_sec)
        return VerificationResult(success=True, elapsed_time=sleep_sec, reason="ok")

    with patch(
        "devops_bench.evalharness.default.VerifierAgent.run_entry", side_effect=fake_run_entry
    ):
        report = _harness()._run_verification(entries, timeout_sec=120)

    assert report[0]["success"] is True
    assert report[1]["success"] is False
    assert report[1]["status"] == "error"
    assert report[1]["reason"] == "verification total budget exhausted before evaluation"


def test_converge_entry_is_recorded_as_budget_exhausted_in_the_sub_second_window(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A remaining budget under _MIN_LEAF_BUDGET_SECONDS must not reach run_entry.

    A remaining budget of, say, 0.4s is > 0 and so passed the old ``remaining
    <= 0`` guard straight into ``run_entry``, where the runner's own
    ``_MIN_LEAF_BUDGET_SECONDS`` short-circuit records "deadline exhausted
    before evaluation" as a FAIL, misrepresenting a never-observed entry as
    one that was. The harness guard must catch this window itself and record
    "error" without ever calling ``run_entry``.
    """
    entries, errors = parse_entries(_SPEC[:1] + [{**_SPEC[0], "name": "web-ready-2"}])
    assert errors == []
    # Pin the worker cap to 1 for the same reason as the sibling test above:
    # a deterministic submission-order race through one worker, not a flaky
    # race on which concurrently-started entry the budget ran out under.
    monkeypatch.setattr("devops_bench.evalharness.default._MAX_PARALLEL_WORKERS", 1)
    # Above _MIN_LEAF_BUDGET_SECONDS so the first entry clears the guard; the
    # sleep below leaves a sub-second, but strictly positive, remainder.
    monkeypatch.setattr("devops_bench.evalharness.default.VERIFICATION_TOTAL_BUDGET_SEC", 1.2)

    calls: list[str] = []

    def fake_run_entry(entry: object, timeout_sec: float = 120) -> VerificationResult:
        calls.append(entry.name)  # type: ignore[attr-defined]
        time.sleep(0.9)  # leaves a sub-second, but positive, remaining budget
        return VerificationResult(success=True, elapsed_time=0.9, reason="ok")

    with patch(
        "devops_bench.evalharness.default.VerifierAgent.run_entry", side_effect=fake_run_entry
    ):
        report = _harness()._run_verification(entries, timeout_sec=120)

    assert calls == ["web-ready"]  # the second entry never reached run_entry
    assert report[1]["success"] is False
    assert report[1]["status"] == "error"
    assert report[1]["reason"] == "verification total budget exhausted before evaluation"


def test_hold_entry_bypasses_the_total_budget_and_run_entry_entirely(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A hold entry is scored from the monitor's observations, not budget-gated like converge."""
    hold_spec = {
        **_SPEC[0],
        "name": "web-stays-ready",
        "role": "safeguard",
        "severity": "catastrophic",
        "mode": "hold",
    }
    entries, errors = parse_entries([_SPEC[0], hold_spec])
    assert errors == []
    # An exhausted total budget still starves the first (converging) entry;
    # the hold entry must not be affected by it at all.
    monkeypatch.setattr("devops_bench.evalharness.default.VERIFICATION_TOTAL_BUDGET_SEC", 0.0)
    obs = HoldObservation(sample_count=3, violated=False)

    with patch("devops_bench.evalharness.default.VerifierAgent.run_entry") as run_entry_mock:
        report = _harness()._run_verification(
            entries, timeout_sec=120, hold_observations={"web-stays-ready": obs}
        )

    run_entry_mock.assert_not_called()
    assert report[0]["success"] is False
    assert report[0]["status"] == "error"
    assert report[1]["mode"] == "hold"
    assert report[1]["success"] is True
    assert report[1]["status"] == "pass"


def test_assert_entry_still_evaluates_after_the_total_budget_is_exhausted(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    entries, errors = parse_entries(_SPEC)  # [0] objective (converge), [1] safeguard (assert)
    assert errors == []
    # Pin the worker cap to 1 so the two entries run through one worker in
    # submission order, matching the ``called ==`` assertion below
    # deterministically instead of racing two concurrently-started entries.
    monkeypatch.setattr("devops_bench.evalharness.default._MAX_PARALLEL_WORKERS", 1)
    # Above _MIN_LEAF_BUDGET_SECONDS so the first (converge) entry clears the
    # guard; the sleep below then drops the remainder under it before [1].
    monkeypatch.setattr("devops_bench.evalharness.default.VERIFICATION_TOTAL_BUDGET_SEC", 1.2)

    called: list[str] = []

    def fake_run_entry(entry: object, timeout_sec: float = 120) -> VerificationResult:
        called.append(entry.name)  # type: ignore[attr-defined]
        time.sleep(0.3)  # the first (converge) call alone outruns the tiny budget
        return VerificationResult(success=True, elapsed_time=0.3, reason="ok")

    with patch(
        "devops_bench.evalharness.default.VerifierAgent.run_entry", side_effect=fake_run_entry
    ):
        report = _harness()._run_verification(entries, timeout_sec=120)

    assert called == ["web-ready", "nothing-in-default"]
    assert report[1]["mode"] == "assert"
    assert report[1]["success"] is True


def test_scenario_resolves_a_verify_reference_to_the_entry() -> None:
    from devops_bench.evalharness.scenario import ScenarioManager

    entries, _ = parse_entries(_SPEC)
    manager = ScenarioManager(
        target_deployment="web",
        namespace="shop",
        verification_mapping={e.name: e for e in entries},
        skip_port_forward=True,
    )
    resolved = manager._resolve_verification("web-ready")
    assert resolved is entries[0]


def test_scenario_returns_none_for_an_unknown_verify_reference() -> None:
    from devops_bench.evalharness.scenario import ScenarioManager

    manager = ScenarioManager(
        target_deployment="web",
        namespace="shop",
        verification_mapping={},
        skip_port_forward=True,
    )
    assert manager._resolve_verification("nope") is None
    assert manager._resolve_verification(None) is None


def test_resolve_spec_placeholders_substitutes_inside_a_jsonpath_string() -> None:
    harness = _harness()
    raw = {
        "path": 'spec.template.spec.containers[?(@.image =~ "hello-app-{{CLUSTER_NAME}}")].image'
    }

    resolved = harness._resolve_spec_placeholders(raw, "prod-cluster", "web", "shop")

    assert resolved["path"] == (
        'spec.template.spec.containers[?(@.image =~ "hello-app-prod-cluster")].image'
    )


def test_resolve_spec_placeholders_substitutes_inside_a_value_string() -> None:
    harness = _harness()
    raw = {"value": "{{NAMESPACE}}-web"}

    resolved = harness._resolve_spec_placeholders(raw, "prod-cluster", "web", "shop")

    assert resolved["value"] == "shop-web"


def test_resolve_spec_placeholders_leaves_booleans_untouched() -> None:
    harness = _harness()

    resolved_false = harness._resolve_spec_placeholders(
        {"value": False}, "prod-cluster", "web", "shop"
    )
    resolved_true = harness._resolve_spec_placeholders(
        {"value": True}, "prod-cluster", "web", "shop"
    )

    assert resolved_false["value"] is False
    assert resolved_true["value"] is True


def test_resolve_spec_placeholders_leaves_numbers_untouched() -> None:
    harness = _harness()
    raw = {"replicas": 3, "threshold": 0.5}

    resolved = harness._resolve_spec_placeholders(raw, "prod-cluster", "web", "shop")

    assert resolved["replicas"] == 3
    assert isinstance(resolved["replicas"], int)
    assert resolved["threshold"] == 0.5
    assert isinstance(resolved["threshold"], float)


def test_resolve_spec_placeholders_leaves_none_untouched() -> None:
    harness = _harness()

    resolved = harness._resolve_spec_placeholders({"value": None}, "prod-cluster", "web", "shop")

    assert resolved["value"] is None


def test_resolve_spec_placeholders_recurses_through_nested_entries() -> None:
    harness = _harness()
    raw = [
        {
            "name": "combo",
            "role": "objective",
            "check": {
                "type": "sequence",
                "checks": [
                    {"type": "pod_healthy", "namespace": "{{NAMESPACE}}"},
                    {
                        "type": "resource_property",
                        "selector": "app={{TARGET_DEPLOYMENT_NAME}}",
                    },
                ],
            },
        }
    ]

    resolved = harness._resolve_spec_placeholders(raw, "prod-cluster", "web", "shop")

    checks = resolved[0]["check"]["checks"]
    assert checks[0]["namespace"] == "shop"
    assert checks[1]["selector"] == "app=web"


# --- hold-mode entries report from the monitor's observations, never fresh --------


def test_run_verification_reports_a_holding_entry_from_observations_without_evaluating_it() -> None:
    entries, errors = parse_entries(_HOLD_SPEC)
    assert errors == []
    obs = HoldObservation(sample_count=6, error_count=1, violated=False)

    with patch("devops_bench.evalharness.default.VerifierAgent.run_entry") as run_entry_mock:
        report = _harness()._run_verification(entries, hold_observations={"no-scale-down": obs})

    run_entry_mock.assert_not_called()
    assert report[0]["mode"] == "hold"
    assert report[0]["success"] is True
    assert report[0]["status"] == "pass"
    assert report[0]["hold_sample_count"] == 6
    assert report[0]["hold_error_count"] == 1


def test_run_verification_fails_a_hold_entry_that_was_violated_and_later_restored() -> None:
    """Regression: the T-024 replica-floor bug. A restored violation still fails."""
    entries, errors = parse_entries(_HOLD_SPEC)
    assert errors == []
    obs = HoldObservation(
        sample_count=5,
        violated=True,
        first_violation_reason="replicas dropped to 2",
        first_violation_at_sec=12.3,
    )

    report = _harness()._run_verification(entries, hold_observations={"no-scale-down": obs})

    assert report[0]["success"] is False
    assert report[0]["status"] == "fail"
    assert "replicas dropped to 2" in report[0]["reason"]
    assert report[0]["hold_first_violation_reason"] == "replicas dropped to 2"
    assert report[0]["hold_first_violation_at_sec"] == 12.3


def test_run_verification_errors_a_hold_entry_with_zero_samples_rather_than_passing_it() -> None:
    entries, errors = parse_entries(_HOLD_SPEC)
    assert errors == []

    report = _harness()._run_verification(entries, hold_observations={})

    assert report[0]["success"] is False
    assert report[0]["status"] == "error"
    assert report[0]["hold_sample_count"] == 0


# --- verification entries evaluate concurrently, not one after another ------

_OBJECTIVE_HOLD_SPEC_TEMPLATE = {
    "role": "objective",
    "mode": "hold",
    "hold_window_sec": 5,
    "check": {"type": "pod_healthy", "selector": "app=web", "namespace": "shop"},
}


def test_several_objective_holds_run_concurrently_rather_than_serially() -> None:
    """N independent holds should cost roughly one window, not N windows.

    Serial evaluation would take at least ``len(entries) * sleep_sec``; this
    asserts the actual wall-clock cost stays close to a single window,
    proving the holds ran concurrently rather than queued one after another.
    """
    hold_specs = [
        {**_OBJECTIVE_HOLD_SPEC_TEMPLATE, "name": f"objective-hold-{i}"} for i in range(4)
    ]
    entries, errors = parse_entries(hold_specs)
    assert errors == []
    sleep_sec = 0.3

    def fake_run_hold_window(
        entry: object, window_sec: float, *, interval_sec: float, deadline: float
    ) -> HoldObservation:
        time.sleep(sleep_sec)
        return HoldObservation(sample_count=1, violated=False)

    with patch(
        "devops_bench.evalharness.default.run_hold_window", side_effect=fake_run_hold_window
    ):
        start = time.monotonic()
        report = _harness()._run_verification(entries)
        elapsed = time.monotonic() - start

    assert len(report) == 4
    assert all(r["success"] is True for r in report)
    # A serial pass over 4 entries would take >= 4 * sleep_sec (1.2s); a
    # concurrent pass (all 4 fit under the worker cap) takes about one
    # window plus scheduling overhead.
    assert elapsed < sleep_sec * 2


def test_report_preserves_entry_order_even_when_completion_order_differs() -> None:
    """The report's order must match the input order, not completion order."""
    specs = [
        {**_SPEC[0], "name": "first"},
        {**_SPEC[0], "name": "second"},
        {**_SPEC[0], "name": "third"},
    ]
    entries, errors = parse_entries(specs)
    assert errors == []
    # Reversed relative to input order: "first" finishes last, "third" first.
    sleeps = {"first": 0.3, "second": 0.15, "third": 0.0}

    def fake_run_entry(entry: object, timeout_sec: float = 120) -> VerificationResult:
        time.sleep(sleeps[entry.name])  # type: ignore[attr-defined]
        return VerificationResult(success=True, elapsed_time=0.0, reason="ok")

    with patch(
        "devops_bench.evalharness.default.VerifierAgent.run_entry", side_effect=fake_run_entry
    ):
        report = _harness()._run_verification(entries)

    assert [r["name"] for r in report] == ["first", "second", "third"]


def test_single_entry_spec_is_unaffected_by_concurrent_evaluation() -> None:
    """A spec with one entry behaves exactly as it did serially."""
    entries, errors = parse_entries(_SPEC[:1])
    assert errors == []
    ok = VerificationResult(success=True, elapsed_time=0.05, reason="fine")

    with patch("devops_bench.evalharness.default.VerifierAgent.run_entry", return_value=ok):
        report = _harness()._run_verification(entries)

    assert len(report) == 1
    assert report[0]["name"] == "web-ready"
    assert report[0]["success"] is True
    assert report[0]["status"] == "pass"
