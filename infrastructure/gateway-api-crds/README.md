# gateway-api-crds — cluster-wide dependency, no promotion pipeline

Installs the [Gateway API](https://gateway-api.sigs.k8s.io/) CRDs
(`Gateway`, `HTTPRoute`, `GatewayClass`, etc.) at the experimental channel,
version `v1.5.1` -- the same version
[fleet-infra](https://github.com/adamancini/fleet-infra) uses. Traefik's own
Helm chart doesn't install these CRDs itself; `traefik-gateway`
(`infrastructure/traefik-gateway/`) needs them present before it can create
its `Gateway` object.

## Ordering

`argocd.argoproj.io/sync-wave: "-1"` makes Argo CD sync this Application's
resources before wave-0 (default) Applications on the same cluster,
including `traefik-gateway` -- so the CRDs land first. This only controls
sync order within a single Argo CD sync operation; it doesn't block
`traefik-gateway` from being *created* first, only from *syncing
successfully* first. If `traefik-gateway` errors on its first sync attempt
because the CRDs aren't registered yet, Argo CD's `selfHeal` will retry it
automatically once this Application succeeds -- no manual intervention
needed, just a one-time delay on the very first sync after the epic's
release-gate story recreates the clusters.
