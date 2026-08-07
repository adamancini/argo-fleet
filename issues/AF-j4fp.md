---
id: AF-j4fp
title: "Expose Grafana externally via a Traefik Gateway API HTTPRoute"
status: open
priority: 2
type: task
parent: AF-d66a
created_at: 2026-08-07T15:06:17Z
created_by: ada
updated_at: 2026-08-07T16:42:47Z
content_hash: "sha256:dc26f99c4812803cab832e64c076e3dbf0e0c35b5b2cdc9915abde06b8e555af"
blocks: [AF-7u8n]
was_blocked_by: [AF-d3ax]
follows: [AF-d3ax]
---

## Description
Description:
Add an `HTTPRoute` (Gateway API) that exposes the Grafana service created by the kube-prometheus-stack story through the existing `traefik-gateway` Gateway, on every cluster running the stack, using this fleet's placeholder-domain convention (no real DNS/TLS exists yet anywhere in this repo).

Context:
`infrastructure/traefik-gateway/` already deploys Traefik configured as a Gateway API controller, creating a `Gateway` object named `traefik-gateway` in the `traefik` namespace (chart values `gateway.enabled: true`, `gateway.name: traefik-gateway` -- see `infrastructure/traefik-gateway/argocd/appset.yaml`). Its own README states explicitly: "Any actual `HTTPRoute`... Wiring them to this Gateway is a follow-up once real domains exist, not part of this layer" -- meaning nothing is wired to this Gateway yet anywhere in this repo. This story's `HTTPRoute` is the first real workload connected to it.

Only the plain-HTTP `web` listener is enabled on this Gateway (`websecure`/TLS stays off -- no cert-manager exists yet in this fleet, deferred fleet-wide per `docs/infra-dependencies.md`'s "Candidates already identified but deferred" section until `akkoma`/`soju` have real domains). `akkoma`/`soju` themselves still use placeholder domains (`*.example.com`, e.g. `akkoma.example.com`, `akkoma-dev.example.com` -- see `apps/akkoma/env/prod/release.yaml`) with `ingress.enabled: false`, precisely because there is no real DNS pointed at either cluster. Grafana's `HTTPRoute` follows the same placeholder-domain convention: it will not resolve via real DNS, but is genuinely reachable by setting the `Host` header explicitly against the Traefik Service's routable address (k3d's built-in `servicelb` gives `LoadBalancer`-type Services -- which is what Traefik's Service is (`service.type: LoadBalancer`, no fixed `loadBalancerIP`) -- a routable IP on the Docker network; if that IP isn't reachable directly from the host machine's network namespace, `kubectl port-forward -n traefik svc/traefik 8080:80` is the universal fallback and must be documented as the verification method actually used).

The exact `HTTPRoute` shape (`parentRefs` referencing a Gateway by name+namespace, `hostnames`, `rules[].backendRefs`) is confirmed working syntax from `fleet-infra` (the Flux repo this project is migrating off of), whose existing routes already reference a Gateway named `traefik-gateway` this way -- e.g. (sanitized shape, not copied verbatim since that repo uses Flux `${cluster_domain}` substitution this repo doesn't have):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <name>
  namespace: <namespace>
spec:
  parentRefs:
    - name: traefik-gateway
      namespace: traefik
  hostnames:
    - "<subdomain>.<domain>"
  rules:
    - backendRefs:
        - name: <service-name>
          port: <port>
```

USER INTENT:
The user explicitly does not want Grafana to be port-forward-only or internal-only -- they want it exposed "consistent with how other UIs in this fleet are exposed," which in this repo means: wired through the Gateway API layer, the same mechanism every future UI in this fleet will use once real domains exist. Given no real DNS exists yet anywhere in this repo, "externally reachable" for THIS story means reachable from outside the pod/cluster network via the Gateway's routable address with an explicit Host header -- not a claim that `https://grafana.something/` works from a browser with no setup. The developer must document the exact command that proves reachability, not just "AC says HTTPRoute exists."

IMPLEMENTATION:
1. Determine the Grafana Service's actual name and port on a deployed cluster: `kubectl get svc -n monitoring` (do not assume the name -- the kube-prometheus-stack story sets `helm.releaseName: kube-prometheus-stack`, so the chart's naming convention should produce `kube-prometheus-stack-grafana` on port `80`, but confirm this against the real cluster rather than hand-guessing the chart's fullname template).
2. Add `infrastructure/kube-prometheus-stack/argocd/grafana-httproute.yaml`:
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
     hostnames:
       - "grafana.<cluster>.example.com"
     rules:
       - backendRefs:
           - name: kube-prometheus-stack-grafana
             port: 80
   ```
   Since the hostname must differ per cluster (`grafana.demo1.example.com` vs `grafana.demo2.example.com`, matching `akkoma`/`soju`'s existing per-stage placeholder-domain convention), and this file syncs identically to both clusters via the same multi-source `ApplicationSet` from the kube-prometheus-stack story (`directory.include` pattern, now needs to include this file too, not just `*.sealed.yaml` -- update that `directory.include` glob in `infrastructure/kube-prometheus-stack/argocd/appset.yaml` to also pick up this file, or add a second `directory.include` pattern), template the hostname using the same generator field the spike story confirmed (e.g. `hostnames: ["grafana.{{name}}.example.com"]`) via a `goTemplate: true` ApplicationSet (see `apps/akkoma/argocd/appset.yaml` for the `goTemplate: true` + `goTemplateOptions: ["missingkey=error"]` pattern this requires) if the file itself needs per-cluster templating, OR keep the file generic (omit `hostnames` entirely, which makes the HTTPRoute match any `Host` header -- the simpler option, since nothing in this fleet resolves these placeholder domains via real DNS anyway, and an unrestricted match still lets verification proceed with an explicit `Host` header of the developer's choosing). Pick whichever is simpler to get working reliably; document the choice and why in this story's delivery notes.
3. Verify reachability: `kubectl port-forward -n traefik svc/traefik 8080:80 &` then `curl -H "Host: grafana.demo1.example.com" http://localhost:8080/` (or the actual hostname chosen in step 2, or no Host header at all if `hostnames` was omitted) and confirm Grafana's login page HTML is returned (not a 404/`no matching route`). Repeat against `demo2`.

KEY FILES:
`infrastructure/kube-prometheus-stack/argocd/grafana-httproute.yaml` (new). `infrastructure/kube-prometheus-stack/argocd/appset.yaml` (modified -- the `directory.include` glob, to also sync this new file; created by the kube-prometheus-stack story).

OUT OF SCOPE:
- Real DNS, TLS, or cert-manager wiring -- explicitly deferred fleet-wide (`docs/infra-dependencies.md`) until `akkoma`/`soju` have real domains; Grafana follows the same placeholder-domain convention, not an exception to it.
- Authentication/SSO in front of Grafana (e.g. a forward-auth `Middleware` like `fleet-infra`'s `forgejo-route.yaml` uses for Authelia) -- this fleet has no Authelia/SSO deployed yet; Grafana relies on its own login (the sealed-secret admin credentials from the kube-prometheus-stack story) for this round.
- Any change to Traefik's own configuration (`infrastructure/traefik-gateway/`) -- the Gateway already exists with the right listener/name; this story only adds a consumer of it.

DIFF BUDGET:
1 new file (`grafana-httproute.yaml`), 1 file modified (`appset.yaml`'s `directory.include` glob). Under 30 changed LOC.

CONSUMES:
- AF-d3ax: infrastructure/kube-prometheus-stack/argocd/appset.yaml -> Grafana Service
    spec: service name: kube-prometheus-stack-grafana (from helm.releaseName: kube-prometheus-stack, fixed across all clusters); port: 80; namespace: monitoring
    source: that story's PRODUCES (verify against the real deployed Service before trusting this name, per that story's own note that chart fullname conventions must be confirmed, not assumed)
- infrastructure/traefik-gateway/argocd/appset.yaml -> traefik-gateway Gateway
    spec: Gateway name: traefik-gateway; namespace: traefik; listener: web (plain HTTP only, websecure disabled)
    source: infrastructure/traefik-gateway/argocd/appset.yaml (existing file, gateway.name: traefik-gateway, gateway.enabled: true), infrastructure/traefik-gateway/README.md

PRODUCES:
- `infrastructure/kube-prometheus-stack/argocd/grafana-httproute.yaml` -> HTTPRoute
    spec: apiVersion: gateway.networking.k8s.io/v1; parentRefs: [{name: traefik-gateway, namespace: traefik}]; rules[].backendRefs: [{name: kube-prometheus-stack-grafana, port: 80}]
    source: this story's own design, modeled on fleet-infra's existing HTTPRoute shape (infrastructure/core-config/*-route.yaml in that repo)

TESTING:
Operational verification only (no test suite exists for this repo's manifests): `curl` against the Traefik Service's routable address (or via `kubectl port-forward` as the guaranteed-reachable fallback) with the chosen `Host` header returns Grafana's login page on both `demo1` and `demo2`. Document the exact command used as delivery evidence -- "HTTPRoute created" without a passing curl is not sufficient proof.

Acceptance Criteria:
1. [Event] When a request reaches the Traefik Gateway with the matching `Host` header (or with any Host header, if `hostnames` was intentionally omitted), it is routed to the Grafana Service and returns Grafana's login page.
2. [Ubiquitous] The `HTTPRoute`'s `parentRefs` references the existing `traefik-gateway` Gateway in the `traefik` namespace -- no new Gateway object is created.
3. [State] While no real DNS exists for the chosen hostname (the expected, documented state for this fleet), Grafana is still verifiably reachable via an explicit `Host` header against the Gateway's routable address or via `kubectl port-forward` -- this is the passing condition, not a blocker to resolve.
4. This story's delivery notes include the exact verification command run and its output (or a description of the returned HTML confirming Grafana's login page), for both `demo1` and `demo2`.
5. [Unwanted] No TLS/cert-manager/real-domain dependency is introduced -- plain HTTP only, consistent with every other route in this fleet today.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory), devops-toolkit:yaml-kubernetes-validator (mandatory -- Gateway API resource validation)

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-07T15:07:23Z dep_added: blocked_by AF-d3ax
- 2026-08-07T15:07:25Z dep_added: blocks AF-7u8n
- 2026-08-07T16:40:18Z dep_removed: was_blocked_by AF-d3ax
- 2026-08-07T16:40:18Z status: open -> in_progress
- 2026-08-07T16:40:18Z auto-follows: linked to predecessor AF-d3ax
- 2026-08-07T16:42:47Z status: in_progress -> open

## Links
- Parent: [[AF-d66a]]
- Blocks: [[AF-7u8n]]
- Was blocked by: [[AF-d3ax]]
- Follows: [[AF-d3ax]]

## Comments
