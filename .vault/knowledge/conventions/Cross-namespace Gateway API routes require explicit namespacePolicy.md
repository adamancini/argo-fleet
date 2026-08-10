---
type: convention
project: argo-fleet
status: active
actionable: pending
epic: AF-d66a
created: 2026-08-10
---

# Traefik's Gateway `allowedRoutes.namespaces.from` defaults to `Same` -- any cross-namespace HTTPRoute needs an explicit override

## Context
`infrastructure/traefik-gateway/` deploys Traefik as a Gateway API controller, creating a `Gateway` named `traefik-gateway` in the `traefik` namespace. AF-j4fp needed to attach the first-ever `HTTPRoute` to it (Grafana, in the `monitoring` namespace) and found the story's own premise -- "the Gateway already exists correctly, just add a consumer" -- was false.

## The trap
Gateway API defaults `allowedRoutes.namespaces.from` to `Same` when unset, and the Traefik chart leaves `gateway.listeners.web.namespacePolicy` unset. `kubectl apply` of the cross-namespace `HTTPRoute` succeeds with no error. `helm template` shows a listener with no `allowedRoutes` at all -- the default is applied server-side by the API server, invisible to client-side rendering. The only real-world symptom is a 404 at request time, plus (confirmed live) the route's own status:

```
reason=NotAllowedByListeners   status=False   type=Accepted
```

`ResolvedRefs` is `True` (the backend Service resolves fine) -- only the listener attachment is blocked, which can make the failure look like something else if you only check backend resolution.

## Fix
Set the listener's namespace policy explicitly to `All` (or a `Selector`, if multi-tenant isolation across namespaces is ever needed -- not the case here, one consuming namespace today):

```yaml
# infrastructure/traefik-gateway/argocd/appset.yaml, chart valuesObject
gateway:
  listeners:
    web:
      namespacePolicy:
        from: All
```

## Verification discipline
Prove the substitution is faithful before/without needing a live `kubectl apply` of the owning appset: extract the `valuesObject` verbatim from the server-rendered Application (`argocd appset generate`) and feed it through `helm template` -- confirm the rendered `Gateway.spec.listeners[].allowedRoutes.namespaces.from` matches the target value exactly, including the listener name (`sectionName` on the `HTTPRoute` must match). This lets you validate a fix on a shared, live Gateway you should not casually re-apply to, and reproduces cleanly in a scratch/dry-run context.

## Actionable guidance
- This was the FIRST cross-namespace route in the fleet; it will not be the last. Any future workload (a second UI, a webhook receiver, anything not deployed into the `traefik` namespace itself) that needs an `HTTPRoute` against `traefik-gateway` inherits this same requirement -- do not re-derive it, check `infrastructure/traefik-gateway/argocd/appset.yaml`'s current `namespacePolicy` first.
- Read the live `Gateway` object (`kubectl get gateway <name> -o jsonpath='{.spec.listeners}'`), not the Helm chart template, before assuming a shared Gateway's listener already admits the namespace you need -- server-side defaulting is invisible to client-side rendering (see the companion note on Gateway API defaulting breaking Argo CD sync-status, same epic, same root class of bug hit twice).
- A stated "out of scope" boundary in a story can rest on a false premise. When live evidence directly contradicts a story's stated scope, that is grounds to request an explicit, in-transcript, direct scope-expansion decision -- not grounds to silently comply with the stale scope, and not something a relayed coordinator message can authorize on the user's behalf (see the process-learnings note on authorization provenance).
