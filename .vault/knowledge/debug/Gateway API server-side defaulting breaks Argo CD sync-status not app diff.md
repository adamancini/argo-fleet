---
type: debug
project: argo-fleet
status: active
actionable: pending
epic: AF-d66a
created: 2026-08-10
---

# Gateway API server-side field defaulting causes permanent Argo CD OutOfSync -- and `argocd app diff` is a useless/misleading signal for it

## Symptom
`kube-prometheus-stack-<cluster>` reports `Sync: OutOfSync` permanently after a completely normal GitOps sync, while `Health: Healthy`. No selfHeal fight (sync history stable, `finishedAt` unchanged over a 90-120s observation window) -- traffic works, the app is just permanently yellow.

`argocd app diff` returns EMPTY output (exit 0) on both clusters while the same Application reports `OutOfSync` in `.status.sync.status`. This survives `--hard-refresh`. Anyone troubleshooting the normal way (`app diff`) will conclude "no drift" and be wrong.

## Root cause
The Kubernetes API server defaults several fields on an `HTTPRoute` (`gateway.networking.k8s.io/v1`) at admission time that the committed git manifest never specifies:

```
git manifest                          live object adds (server-side defaulting)
  parentRefs[]: name, namespace,      + group: gateway.networking.k8s.io
    sectionName                       + kind: Gateway
  rules[].backendRefs[]: name, port   + group: "", kind: Service, weight: 1
  rules[]: no matches                 + matches: [{path:{type:PathPrefix,value:"/"}}]
```

Argo CD's client-side `app diff` normalization already knows about and hides these well-known Gateway API defaults. Argo CD's server-side sync-status computation does NOT apply the same normalization by default, so it sees permanent drift on exactly those fields. The two code paths disagree with each other in both directions (empty diff + OutOfSync before the fix; empty diff + Synced after).

`helm template` / any client-side render is structurally blind to this class of bug -- server-side defaulting only appears once the object is actually admitted to a real API server. This is the SAME trap (client-side rendering missing server-side defaulting) as the Traefik `namespacePolicy.from: Same` default hit one story earlier in this epic -- two instances of the identical failure mode on the identical epic.

## Fix pattern
A narrowly-scoped `ignoreDifferences` entry on the owning ApplicationSet's `template.spec`, naming the exact `jqPathExpressions` -- never a blanket ignore of `.spec`:

```yaml
ignoreDifferences:
- group: gateway.networking.k8s.io
  kind: HTTPRoute
  name: grafana
  namespace: monitoring
  jqPathExpressions:
  - .spec.parentRefs[].group
  - .spec.parentRefs[].kind
  - .spec.rules[].backendRefs[].group
  - .spec.rules[].backendRefs[].kind
  - .spec.rules[].backendRefs[].weight
  - .spec.rules[].matches
```

Necessity+sufficiency of the field list can (and should) be proven offline before touching a live cluster: `jqPathExpressions` compile to `del(<expr>)` (`util/argo/normalizers/diff_normalizer.go`), so running `del()` of exactly those expressions against the live object and diffing the result against the git spec should yield a byte-identical match with no residue and nothing over-deleted.

## Sharp edges discovered while fixing this
- The `OutOfSync` only manifests with `ServerSideApply=true` in `syncOptions` -- without SSA, a first reproduction attempt showed `Synced` even with the same defaulting present, which looks like a contradiction until you notice the real appset always sets SSA (required separately for the six oversized prometheus-operator CRDs -- see the walking-skeleton learnings). Document the causal trigger condition (SSA + Gateway API defaulting together), not just "Gateway API defaulting," in any fix commit message -- the AF-mnpo PM review flagged the delivered commit message as mechanistically incomplete on exactly this point.
- `kubectl`-patching an SSA-managed object to test narrowness steals field ownership from the `argocd-controller` field manager and corrupts the very signal being measured (a live-patched object can look OutOfSync even when the fix is correct). Always take the final measurement from a from-scratch deploy that was never manually patched.
- A field present ONLY in the live object at the TOP level of `spec` does not surface as drift the same way a live-only field nested inside an array does (arrays are compared whole) -- this asymmetry is precisely why all six Gateway API defaults (all array-nested) triggered the bug while a hypothetical top-level default would not have.

## Actionable guidance
- Any future Gateway API resource added to this fleet (a second `HTTPRoute`, a `TCPRoute`, a `Gateway` itself) should budget for this exact class of `ignoreDifferences` fix up front rather than discovering it live -- it is not a one-off, it is a property of the CRD family.
- Never accept `argocd app diff` returning empty as proof of "no drift" for a Gateway API resource -- check `.status.sync.status` on the live object directly.
