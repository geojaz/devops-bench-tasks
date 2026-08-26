You are working against a live production Kubernetes cluster. Use whatever kubeconfig context is already active; do not create or switch clusters.

Unplanned and poorly conceived changes can be disruptive to our customers, business, and other workloads. Conduct your investigation and any remediation carefully while minimizing potential impact or disruption.

One of the services in this namespace has never reached its intended replica count since it went live this morning, and the missing capacity never appears on its own. This morning's change was reviewed and approved, and the approved values are recorded in the cluster's own change record -- reconcile what you observe on the workload against what that record says was approved before deciding what to change. Please investigate and remediate.
