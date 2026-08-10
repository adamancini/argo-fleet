---
type: debug
project: argo-fleet
status: active
actionable: pending
epic: AF-d66a
created: 2026-08-10
---

# Live-verification cleanup gotchas: cascade delete leaves cluster-scoped CRDs behind

## Symptom
After `argocd app delete --cascade` (the default) on a temporary `kube-prometheus-stack` Application used for live verification, the developer's own "baseline restored" claim was incomplete: 10 cluster-scoped `monitoring.coreos.com` CustomResourceDefinitions per cluster remained, even though the `monitoring` namespace and all namespaced resources were correctly gone. This happened identically across AF-d3ax, AF-7u8n, and AF-mnpo -- three separate stories in the same epic hit the same residue.

## Root cause
Argo CD's cascade delete removes the resources it tracks as **managed** by the Application. Cluster-scoped CRDs installed by a chart (here, the six prometheus-operator CRDs) and a namespace created via `CreateNamespace=true` in `syncOptions` are not always swept the same way -- the namespace in particular is not itself a "tracked" resource in the same sense, so `CreateNamespace=true` creating it does not imply cascade-deleting it will remove it, and the CRDs can outlive the Application that installed them entirely.

## Fix / verification pattern
Every "baseline restored" claim for a live-verification story that installs CRDs must enumerate cluster-scoped leftovers explicitly, not just check that the namespace is gone:
```bash
kubectl get crd | grep monitoring.coreos.com   # should be empty post-cleanup
kubectl get ns monitoring                       # should be NotFound
```
Confirm zero custom resources of each CRD type existed before deleting the CRDs themselves (deleting a CRD while CRs still exist silently deletes those CRs too -- verify emptiness first, not just count-after).

## Actionable guidance
- Add "cluster-scoped CRDs left behind by cascade delete" to the standard cleanup checklist for any future story that live-verifies a chart bundling its own CRDs (cert-manager, any future CRD-heavy chart) on these shared k3d clusters.
- Do not trust `argocd app delete --cascade`'s default behavior to be a complete cleanup for CRD-bundling charts -- always follow with an explicit CRD/namespace enumeration, and prefer this repeatable pattern over ad hoc `kubectl get all -n <ns>` spot checks that would miss cluster-scoped objects entirely.
