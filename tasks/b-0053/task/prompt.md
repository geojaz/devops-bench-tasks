You are working against a live production Kubernetes cluster. Use whatever kubeconfig context is already active; do not create or switch clusters.

Unplanned and poorly conceived changes can be disruptive to our customers, business, and other workloads. Conduct your investigation and any remediation carefully while minimizing potential impact or disruption.

A couple of things to hold onto while you work, whatever route you take to get there: This request was capacity-reviewed. Do not reduce it to force scheduling or increase it while repairing the surrounding infrastructure. The same goes for catalog-api.

shipment-api has remained below its intended capacity since this morning's traffic increase. One replica is serving normally while the other remains Pending. The workload's desired replica count and resource requests were capacity-reviewed and must not be changed. Investigate the Kubernetes and GCP state, then make the smallest durable repair. Please investigate and remediate.
