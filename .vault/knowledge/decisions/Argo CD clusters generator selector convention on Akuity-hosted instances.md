---
type: decision
project: argo-fleet
status: active
actionable: pending
epic: AF-d66a
created: 2026-08-10
---

# Argo CD's `clusters: {}` generator requires a mandatory `NotIn` selector on this Akuity-hosted instance

## Context
AF-ogxu (spike) needed to confirm whether Argo CD's ApplicationSet `clusters: {}` generator works against an Akuity-hosted (not plain OSS) Argo CD instance before migrating 5 existing appsets + adding a 6th. The documented risk was that Akuity's Terraform-based cluster registration (no hand-authored cluster Secrets) might mean the generator finds nothing.

## Decision / Finding
The generator works, but the real risk was the *opposite* of the one predicted: a bare `clusters: {}` returns **four** clusters, not two -- `demo1`, `demo2`, plus the Akuity control plane (`in-cluster`) and the `kargo` cluster. A naive swap from the old 2-element `list` generator to a bare `clusters: {}` would silently broaden every infra app's targeting onto the control plane and the Kargo cluster (e.g. `sealed-secrets` would try to install into `kargo`; `in-cluster` is namespace-restricted to `argocd` and would reject the destination namespace outright).

The confirmed, now-fleet-wide convention:
```yaml
spec:
  generators:
  - clusters:
      selector:
        matchExpressions:
        - key: akuity.io/argo-cd-cluster-name
          operator: NotIn
          values: [in-cluster, kargo]
  template:
    metadata:
      name: "<app>-{{name}}"
    spec:
      destination:
        name: "{{name}}"   # NEVER destination.server -- {{server}} resolves to an
                            # Akuity-internal proxy URL (e.g. http://cluster-demo1:8001),
                            # not a reachable API server URL.
```

Denylist (`NotIn`) was deliberately chosen over allowlist (`In [demo1, demo2]`, which is just a `list` generator wearing a different hat) so a third workload cluster is picked up with zero file edits -- the actual goal of the migration.

A `goTemplate: false` (default) gotcha compounds this: an unresolved `{{metadata.labels.X}}` renders as the literal placeholder string, not empty/falsy -- do not write conditional logic assuming a missing label evaluates falsy without `goTemplate: true`.

## Evidence
- `argocd appset generate` (server-side dry-run RPC) was the verification tool of choice: it renders against real cluster state and creates nothing, so "no leftovers" is true by construction rather than by cleanup discipline.
- Byte-identical diff of old (`list`) vs new (`clusters`+selector) rendered Application specs proved the migration a true no-op across all 5 pre-existing infra apps (AF-c8p4).
- `NotIn` only excludes `in-cluster`/`kargo` because Akuity actually stamps `akuity.io/argo-cd-cluster-name` on every cluster -- verified empirically (Kubernetes `NotIn` semantics also match on missing keys, so this depended on the label always being present, not assumed).

## Actionable guidance
- Any 6th+ infrastructure appset (or any future ApplicationSet targeting workload clusters on this instance) MUST copy this exact selector -- do not reintroduce a bare `clusters: {}` or an allowlist.
- `docs/infra-dependencies.md` already documents this (AF-qmy9) -- point new contributors/agents there before they hand-roll a generator block.
- Longer-term hardening option identified but not implemented: stamp `labels = { fleet = "true" }` per cluster in `terraform/clusters/terraform.tfvars` (only after first successful apply -- two-phase registration) and switch to `matchLabels: {fleet: "true"}`, which does not depend on Akuity-internal label semantics.
