---
id: AF-mnpo
title: "Bug: kube-prometheus-stack Application permanently OutOfSync due to Gateway API HTTPRoute server-side defaulting"
status: open
priority: 0
type: bug
parent: AF-d66a
created_at: 2026-08-07T19:13:30Z
created_by: ada
updated_at: 2026-08-07T19:13:30Z
content_hash: "sha256:59dc3fe773142e1bec12891c60b5883a0a76fd098cb9ae2fc0cd9dd553f9470a"
blocked_by: [AF-j4fp]
---

## Description
Priority: P0

Description:
`kube-prometheus-stack-<cluster>` Application will sit permanently `OutOfSync` in Argo CD (Health stays `Healthy`) once the Grafana `HTTPRoute` this epic introduced reaches a live cluster, because Gateway API's server-side defaulting mutates fields the committed git manifest never specifies.

DISCOVERED DURING:
AF-7u8n's live end-to-end verification (capstone story of epic AF-d66a). The developer deployed the real manifests -- `infrastructure/kube-prometheus-stack/argocd/appset.yaml` and `infrastructure/kube-prometheus-stack/secrets/grafana-httproute.yaml` (introduced by AF-j4fp, already accepted) -- live to both `demo1` and `demo2`, observed the `OutOfSync` state directly on both, and confirmed it is deterministic (reproduced identically on both clusters).

SYMPTOMS:
- `kube-prometheus-stack-<cluster>` Application reports `Sync: OutOfSync` permanently after a normal GitOps sync, while `Health: Healthy`.
- No selfHeal loop/fight was observed (sync history stable at 1, `finishedAt` unchanged over a 90s observation window) -- traffic and functionality are unaffected, but the app shows a permanent yellow "OutOfSync" state in the Argo CD UI on every subsequent sync.
- `argocd app diff` returns EMPTY output (exit 0) on both clusters while the same Application reports `OutOfSync` in `.status.sync.status`. Client-side diff normalization silently hides the exact fields causing the mismatch, so anyone troubleshooting the normal way (`argocd app diff`) will see no diff and wrongly conclude there is no drift. This survives `--hard-refresh`.

EVIDENCE:
Live field-by-field diff between the committed git manifest and the live object, confirmed directly against both `demo1` and `demo2` by AF-7u8n's developer:

```
git (grafana-httproute.yaml)         live object adds (Gateway API server-side defaulting)
  spec.parentRefs[]:                 + parentRefs[].group = gateway.networking.k8s.io
    name, namespace, sectionName     + parentRefs[].kind  = Gateway
  spec.rules[].backendRefs[]:        + rules[].backendRefs[].group  = ""
    name, port                       + rules[].backendRefs[].kind   = Service
                                      + rules[].backendRefs[].weight = 1
  spec.rules[]: no `matches`         + rules[].matches = [{path: {type: PathPrefix, value: "/"}}]
```

Current committed manifest, unchanged since AF-j4fp (`infrastructure/kube-prometheus-stack/secrets/grafana-httproute.yaml`):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
  namespace: monitoring
spec:
  parentRefs:
  - name: traefik-gateway
    namespace: traefik
    sectionName: web
  rules:
  - backendRefs:
    - name: kube-prometheus-stack-grafana
      port: 80
```

The owning ApplicationSet, `infrastructure/kube-prometheus-stack/argocd/appset.yaml`, currently has no `ignoreDifferences` block at all (verified by reading the file on `epic/AF-d66a`, HEAD at the time of writing this bug).

POSSIBLE CAUSES:
1. (confirmed root cause) The Gateway API resource's structural-schema/admission defaulting sets default values for `parentRefs[].group`/`kind`, `backendRefs[].group`/`kind`/`weight`, and `rules[].matches` on every `HTTPRoute` object at creation time, regardless of whether git specifies them. Argo CD's server-side sync-status computation compares the un-defaulted git manifest against the live, defaulted object and reports permanent drift on those fields.
2. Argo CD's `app diff` normalization (the path used for local, human-facing diff display) already accounts for exactly these well-known Gateway API defaults and therefore hides them -- explaining why `app diff` returns empty while `.status.sync.status` does not. This confirms the mismatch lives specifically in the sync-status computation path, not in a resource that is actually misconfigured.

CONFIG:
- `apiVersion: gateway.networking.k8s.io/v1`, `kind: HTTPRoute`, resource `grafana` in namespace `monitoring`.
- Managed via `infrastructure/kube-prometheus-stack/argocd/appset.yaml`'s second `sources` entry (git directory source over `infrastructure/kube-prometheus-stack/secrets`, `include: '*.yaml'`).
- Confirmed on both `demo1` and `demo2` (Akuity-hosted Argo CD instance).

Acceptance Criteria:
1. Root cause is confirmed and documented in the fix's commit message: Gateway API server-side defaulting on `spec.parentRefs[].group`, `spec.parentRefs[].kind`, `spec.rules[].backendRefs[].group`, `spec.rules[].backendRefs[].kind`, `spec.rules[].backendRefs[].weight`, and `spec.rules[].matches`.
2. `infrastructure/kube-prometheus-stack/argocd/appset.yaml`'s `template.spec` gains an `ignoreDifferences` entry scoped to `group: gateway.networking.k8s.io`, `kind: HTTPRoute`, `name: grafana`, `namespace: monitoring` (or the ApplicationSet-templated equivalent), covering exactly the fields confirmed drifting above -- not a blanket ignore of the entire `spec`.
3. Before merging, the fixing developer re-verifies the exact JSON pointer / jqPathExpression paths against a live cluster's actual `HTTPRoute` object (`kubectl get httproute grafana -n monitoring -o json`) rather than trusting this bug's field list as final -- per this fleet's discipline of confirming exact shapes instead of guessing (the shapes above are correct as of this bug's filing but a schema/version bump could change them).
4. After the fix, `kube-prometheus-stack-<cluster>` Application reports `Sync: Synced` (not `OutOfSync`) on both `demo1` and `demo2` following a normal GitOps sync, with `Health` remaining `Healthy`.
5. Verification checks `.status.sync.status` on the live Application object directly -- `argocd app diff` returning empty is explicitly NOT sufficient proof of a fix, since it already returned empty before the fix while the bug was present.
6. No functional/routing change to the HTTPRoute: Grafana remains reachable via the same curl/Host-header verification AF-j4fp documented (`infrastructure/kube-prometheus-stack/secrets/grafana-httproute.yaml`'s consumer path) -- this is a diff-visibility fix only.
7. The `ignoreDifferences` scope is narrow enough that a genuine future change (e.g. a developer intentionally changing the backend Service name or adding a real `hostnames` entry) still surfaces as a diff -- it must not mask real drift on `parentRefs`/`backendRefs` name/namespace/port values or hostnames.
8. Fix is verified live on both `demo1` and `demo2`, not rendered/dry-run only, consistent with how this epic's other stories (AF-j4fp, AF-7u8n) verified against real cluster state.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-07T19:13:34Z dep_added: blocked_by AF-j4fp

## Links
- Parent: [[AF-d66a]]
- Blocked by: [[AF-j4fp]]

## Comments
