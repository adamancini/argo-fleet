---
type: pattern
project: argo-fleet
status: active
actionable: pending
epic: AF-d66a
created: 2026-08-10
---

# `bootstrap/infra-apps.yaml` syncs `infrastructure/*/argocd` wholesale to `in-cluster` -- keep cluster-bound objects out of that glob

## Context
`bootstrap/infra-apps.yaml` auto-discovers every `infrastructure/*/argocd` directory (git-directories generator, `directory.recurse: true`) and syncs each matched directory **wholesale** to the `in-cluster` destination, namespace-scoped to `argocd` only. AF-d3ax needed to add a `SealedSecret` (Grafana admin creds) alongside the new `kube-prometheus-stack` appset and discovered this the hard way.

## The trap
`in-cluster`'s `apiVersions` list contains **zero** `bitnami.com` entries -- no `SealedSecret` CRD registered on the Akuity control plane. A `SealedSecret` placed inside `infrastructure/kube-prometheus-stack/argocd/` would have been pushed to that control plane, into a namespace it is not scoped for, for a CRD it does not have -- a guaranteed permanent sync failure on the auto-generated `infra-kube-prometheus-stack` Application. The same trap bit AF-j4fp one story later for an `HTTPRoute` (a workload-cluster-only CRD).

## Resolution (now the fleet convention)
Anything that must land on a **workload cluster** (`demo1`/`demo2`), not the control plane -- `SealedSecret`, `HTTPRoute`, or any other CRD not registered on `in-cluster` -- goes in a **sibling directory outside the `argocd/` glob**, referenced via a second multi-source `sources` entry with a `directory.include` glob. This repo already had the precedent (`apps/akkoma/argocd/` + `apps/akkoma/env/<stage>/`); `infrastructure/kube-prometheus-stack/secrets/` mirrors it.

```yaml
spec:
  template:
    spec:
      sources:
      - repoURL: https://prometheus-community.github.io/helm-charts
        chart: kube-prometheus-stack
        # ...
      - repoURL: https://github.com/adamancini/argo-fleet.git
        path: infrastructure/kube-prometheus-stack/secrets   # NOT .../argocd
        directory:
          include: "*.yaml"   # widened from *.sealed.yaml once an HTTPRoute
                                # also needed to live here -- see caveat below
```

## Caveat: glob width matters and is easy to get silently wrong
AF-j4fp initially widened `directory.include` from `'*.sealed.yaml'` to `'*.yaml'` to also pick up `grafana-httproute.yaml`. `'*.sealed.yaml'` genuinely does NOT match a file merely named `something.yaml` under Go `path.Match` semantics -- confirmed both by the developer and independently re-derived by the PM using a standalone `path.Match` program. A file that "looks like it should sync because it's in the folder" can be silently excluded by an over-narrow glob with **no apply-time error** -- it is simply absent from every cluster.

## Actionable guidance
- Before adding a new file under any `infrastructure/<name>/` tree, check: does this object need a CRD that exists on the workload clusters but not on `in-cluster`? If yes, it does NOT go under `<name>/argocd/`.
- Whenever a `directory.include` glob is widened or narrowed, verify with the literal glob semantics (`path.Match` in Go, not shell glob intuition) against every actual file in that directory -- do not eyeball it.
- The e2e test (`e2e/observability_test.rb`, section 9) now asserts no `SealedSecret`/`HTTPRoute` objects exist anywhere under any `infrastructure/*/argocd/*` glob, and (section 2) that every file actually present in a `secrets/` directory is matched by its own directory glob -- extend both checks if a new infra dependency introduces a third cluster-bound kind.
