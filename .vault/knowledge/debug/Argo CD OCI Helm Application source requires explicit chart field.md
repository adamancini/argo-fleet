---
type: debug
project: argo-fleet
status: active
actionable: pending
epic: AF-j5rz
created: 2026-08-20
---

# Argo CD OCI Helm Application sources require an explicit `chart:` field -- no static check catches its absence

## Symptoms
All 18 arr-stack workload Applications (`apps/arr-stack/argocd/appset-workloads.yaml`, merged and statically verified via AF-6jta and AF-vm0q's 589-assertion suite) failed live with:
```
InvalidSpecError -- spec.source.repoURL and either spec.source.path or spec.source.chart are required
```
The failure was clean and safe: Argo CD rejects an invalid spec before attempting any sync, so nothing was actually created (no pods, no PVCs, no partial state) -- discovered only during AF-o0rw's live merge verification, after `helm template`, the repo's full Ruby e2e suite (150/150, then 589/589), and `pvg gates`/`pvg verify` had all passed clean.

## Root cause
The committed source block was:
```yaml
source:
  repoURL: oci://ghcr.io/bjw-s-labs/helm/app-template
  targetRevision: "4.x"
  helm: {values: "..."}
```
Argo CD's single-source validation (`util/argo/argo.go`, `validateSourcePermissions`) unconditionally requires `path` or `chart` to be non-empty -- an `oci://`-prefixed `repoURL` does **not** satisfy this by itself, and there is no special case for it. Separately, `reposerver/repository/repository.go` trims any `oci://` prefix from `repoURL` before use ("oci:// prefix... is currently not supported by Argo CD (OCI repos just have no scheme)"), so the chart name must be supplied via a **separate, mandatory** `chart:` field, never appended to `repoURL`'s path.

The wrong shape traced back to a **schema conflation** in the design spec: `docs/onboarding.md`'s real, correctly-scoped rule that Kargo's `Warehouse.spec.subscriptions[].image` chart subscription must leave `chart.name` unset for an `oci://` repoURL (because each OCI repoURL there is dedicated to one chart) was misapplied to the unrelated Argo CD `Application.spec.source` schema, where the opposite is true: `chart:` is always mandatory for an OCI Helm source, `oci://`-prefixed or not.

## Why no static check caught it
`helm template`, the repo's Ruby YAML/structural assertions, and `pvg verify`/`pvg gates` all operate on the manifest's *content* or Helm's own rendering -- none of them replicate Argo CD's own `Application.spec.source` admission-time validation rule. This is a class of defect that is invisible to any check that doesn't literally transcribe the control plane's own validation predicate.

## Fix
```yaml
source:
  repoURL: ghcr.io/bjw-s-labs/helm    # no oci:// scheme
  chart: app-template                  # new, explicit, mandatory field
  targetRevision: "4.x"
  helm: {values: "..."}
```
This is the same shape this repo's own live-working `apps/akkoma/argocd/appset.yaml` already used for its own OCI source -- an in-repo precedent that would have prevented the defect if consulted at authoring time.

## Actionable guidance
- **Any Argo CD `Application`/`ApplicationSet` template source targeting an OCI registry must set both a bare (no-scheme) `repoURL` and an explicit `chart:` field, unconditionally.** Add this as a standing structural check to `e2e/observability_test.rb` (or any future static suite) for every OCI-sourced Application source in this repo -- not just arr-stack's.
- When a doc states a rule about "chart name and oci:// repoURLs," check which schema it's actually describing (Kargo Warehouse subscription vs. Argo CD Application source) before reusing the rule elsewhere -- the two have opposite requirements for the same-looking field.
- For any future ApplicationSet whose generated spec can be validated against a real control-plane rule, consider transcribing that rule directly into a throwaway harness (as AF-wb16's developer did, reproducing the exact `InvalidSpecError` string offline) rather than relying solely on `helm template`/YAML structural checks -- this closes the exact gap that let this bug reach the live instance.
