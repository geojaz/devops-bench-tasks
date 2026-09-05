# layer0-smoke

Layer 0 of the streaming/CDC environment stack (see
`factory-303/docs/terraform-scene-layout.md`): the provider-only foundation
a scene layer (Kafka, Flink, CNPG) is built on top of. This stack exists to
hand-validate `tf/modules/gke_cluster_data`, `tf/modules/gcs_bucket`, and
`tf/modules/workload_identity` end to end, the same way the layout doc's
migration step 1 describes ("unit-tested by hand against a scratch
bucket/project, not referenced by any prebuilt stack yet"). It is not wired
to any scene module and not referenced by any task stack.

## What it adopts

- **The GKE cluster** named by `var.cluster_name`, via
  `tf/modules/gke_cluster_data`, a data-source-only module. There is no
  resource anywhere in this module or this stack that can create, modify, or
  delete a `google_container_cluster`. Confirm this yourself with
  `tofu plan` and grep the output for `google_container_cluster`: the only
  match is the data source's own read.
- **The shared SQL runner jar bucket** (`var.jar_bucket_name`), by default,
  via a `google_storage_bucket` data source. See "Jar bucket: shared, not
  per-attempt" below for why, and `var.manage_jar_bucket` for the one
  bootstrap-time exception.

## What it creates

- **A per-attempt checkpoint/savepoint bucket**, named
  `<project_id>-f303-<12-char hash of attempt_id>`, preserving the shape of
  `factory303/stream_runtime.py`'s `_ensure_bucket` (`<project>-f303-<12-char
  hash>`). The original hashes `namespace:owner_id`; this stack is only given
  `attempt_id`, so `attempt_id` stands in for that combined salt.
- **A Google service account** (`tf/modules/workload_identity`) the Flink
  workload assumes, named from a truncated+hashed `f303-flink-<attempt_id>`
  (GCP's 30-char account_id limit doesn't leave room for a raw attempt id).
- **Per-bucket IAM bindings**, not a project-wide role:
  `roles/storage.objectAdmin` on the checkpoint bucket,
  `roles/storage.objectViewer` on the jar bucket.
- **A Workload Identity Federation binding**
  (`roles/iam.workloadIdentityUser` on the GSA, member
  `serviceAccount:<project>.svc.id.goog[<namespace>/<ksa>]`) letting the
  `flink` Kubernetes service account in the attempt's namespace impersonate
  the GSA. This replaces `_bind_bucket`'s imperative
  `gcloud storage buckets add-iam-policy-binding` call and its direct
  `principal://...workloadIdentityPools/...` binding; the GSA-in-the-middle
  shape here is the one the task asked for and is simpler (no project number
  needed in the member string).
- **Optionally**, the shared jar bucket itself, only when
  `manage_jar_bucket = true` (see below).

## Jar bucket: shared, not per-attempt

The jar is a generic SQL runner wrapper (see
`factory-303/docs/flink-sessionjob-spike.md`): its content does not vary
with the attempt id, only the SQL script argument does. Making it per-attempt
would mean rebuilding/re-uploading an identical artifact on every attempt,
carrying N buckets' worth of IAM surface over time for zero behavioral
difference, and it would create a lifecycle hazard: a per-attempt bucket gets
destroyed at that attempt's teardown, but a still-running `FlinkSessionJob` CR
elsewhere could still hold a `jarURI` pointing at it. A single shared bucket,
built once and referenced by every attempt, avoids all of that. This stack
therefore adopts it via data source by default and only creates it when
`manage_jar_bucket = true`, which is meant for the one-time bootstrap of that
shared bucket (or, as used below, for hand-validating the `gcs_bucket` module
against a real project).

### Known constraint, confirmed live: public read is blocked by org policy

The spike found that `FlinkSessionJob.spec.job.jarURI` is fetched by the
*operator pod* over plain, anonymous https, not by an authenticated GCS
client. That means the jar object needs to be publicly readable over
`storage.googleapis.com`, independent of any per-bucket IAM grant to the
Flink workload's own GSA (that grant is a defense-in-depth/fallback path, not
what the operator actually uses).

`ehole-benchmark-temp-z8s8` enforces the `storage.publicAccessPrevention` org
policy project-wide:

```
$ gcloud org-policies describe constraints/storage.publicAccessPrevention \
    --project=ehole-benchmark-temp-z8s8 --effective
name: projects/909006432355/policies/storage.publicAccessPrevention
spec:
  rules:
  - enforce: true
```

Confirmed live during validation below: setting `allow_public_read = true` on
the jar bucket (`tf/modules/gcs_bucket`'s `allow_public_read` variable, which
sets a bucket-level `public_access_prevention = "inherited"` plus an
`allUsers` `roles/storage.objectViewer` grant) fails apply with:

```
Error 412: The member bindings allUsers and allAuthenticatedUsers are not
allowed since public access prevention is enforced., conditionNotMet
```

The org-level "enforced" setting overrides the bucket's own "inherited"
value. This is a real, environment-specific blocker, not a bug in the
module: `var.jar_bucket_allow_public_read` defaults to `true` because that is
what a real deployment needs, but plan/apply against this project must pass
`jar_bucket_allow_public_read = false` until one of the following is done,
none of which this stack should do unilaterally:

1. Get a project- or bucket-scoped exception to `storage.publicAccessPrevention`
   from whoever owns that org policy, and flip the variable back to `true`.
2. Distribute the jar a different way that doesn't require an anonymous
   public GCS URL (e.g. signed URLs regenerated outside Terraform's
   declarative model, in the same category as the other "must stay outside
   TF" items in `docs/terraform-scene-layout.md` section 4, or hosting it
   somewhere other than this GCS project).

## Cluster-safety property

`tofu plan`'s output for this stack contains exactly one line that mentions
the cluster: `module.cluster.data.google_container_cluster.this`, a read.
There is no `google_container_cluster` resource, no node pool resource, and
no provisioner anywhere in this stack or in `tf/modules/gke_cluster_data`.
Structurally, `tofu destroy` on this stack has nothing to delete that is the
cluster or any part of it: the resource type simply does not appear as a
managed resource anywhere in the dependency graph.

## Plan / apply / destroy

```
tofu init

tofu plan \
  -var="cluster_name=ehole-ap-use1-2" \
  -var="attempt_id=<short-id>" \
  -var="manage_jar_bucket=true" \
  -var="jar_bucket_allow_public_read=false"   # see the org-policy note above

tofu apply <saved plan>

tofu destroy \
  -var="cluster_name=ehole-ap-use1-2" \
  -var="attempt_id=<short-id>" \
  -var="manage_jar_bucket=true" \
  -var="jar_bucket_allow_public_read=false"
```

`cluster_name` has no default on purpose: a layer-0 stack that defaulted to
any one cluster would make it easy to apply against the wrong one by
omission. Always name the cluster explicitly. For a normal per-attempt run
(not hand-validating the module), omit `manage_jar_bucket` (defaults to
`false`, adopting the shared bucket) and `jar_bucket_allow_public_read`
(irrelevant when not managing the bucket).

## State backend

GCS, not local: `gs://ehole-benchmark-temp-z8s8-f303-bf7670a0`, prefix
`tf-state/layer0-smoke`. That bucket already exists independently of this
stack (it predates this task and is the dev-probe bucket referenced by
`factory303/stream_runtime.py`'s `DEFAULT_CAPACITY`); it is not created or
destroyed by anything here, so there is no bootstrapping cycle to solve.

The per-attempt checkpoint bucket this stack creates could *not* have been
used for its own backend: a `backend` block cannot interpolate a resource or
module output (bucket names must be known before `tofu init` runs, before
any resource in the configuration has been created), so a bucket created by
this same configuration can never be its own state backend without a
separate bootstrap phase (`terraform init -migrate-state` after a first,
backend-less apply). That extra phase isn't worth it for a stack whose
purpose is hand-validation; a real per-attempt task stack should point its
backend at a distinct, already-existing state bucket, not at the
attempt-scoped checkpoint bucket it manages.
