# traefik-gateway — cluster-wide dependency, no promotion pipeline

Installs [Traefik](https://traefik.io/) on every cluster in
`argocd/appset.yaml`'s `list` generator (`demo1`, `demo2`), configured as a
**Gateway API** controller -- not classic Ingress-only -- mirroring
[fleet-infra](https://github.com/adamancini/fleet-infra)'s real-cluster
setup. Classic Ingress support (`providers.kubernetesIngress`) and
Traefik's own CRD provider (`providers.kubernetesCRD`, for `Middleware`
etc.) both stay enabled too -- Gateway API and Ingress aren't mutually
exclusive.

The chart creates the `Gateway` object itself from the `gateway.*` values --
no hand-authored `Gateway` YAML in this repo. Its name is pinned to
`traefik-gateway` explicitly, matching the exact name `fleet-infra`'s
`HTTPRoute` resources already reference via `parentRefs`, so a future
app's `HTTPRoute` here can use the identical reference shape.

## What's NOT enabled yet

- The `websecure` (TLS) listener -- stays off. No cert-manager, no real
  domains yet (see the design spec in `docs/superpowers/`).
- Any actual `HTTPRoute` for `akkoma`/`soju` -- they still use placeholder
  domains and `ingress.enabled: false`. Wiring them to this Gateway is a
  follow-up once real domains exist, not part of this layer.

## Prerequisite

Same as `openebs-localpv`: k3s's own bundled Traefik must be gone first
(`task cluster:recreate` disables it via
`--k3s-arg "--disable=traefik@server:0"`), or this Application's
`IngressClass`/`Gateway` objects collide with k3s's own.
