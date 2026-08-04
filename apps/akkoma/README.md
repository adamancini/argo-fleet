# akkoma — external OCI chart, promotions commit to main

Deploys [akkoma-helm](https://github.com/adamancini/akkoma-helm)'s published
chart (`oci://ghcr.io/adamancini/charts/akkoma`) directly -- unlike
`akp-platform`'s `guestbook-helm`, nothing is vendored into this repo. Each
environment's `env/<stage>/release.yaml` pins the chart version and stage
values; Argo CD's `files` generator reads it to build a multi-source
Application (chart + this repo's SealedSecret).

**Pipeline:** `Warehouse → dev → staging → prod`. `dev`/`staging` run on
`demo1`, `prod` on `demo2`.

## Why not vendor the chart

`akkoma-helm` is an independently maintained, versioned chart -- copying it
in means manually re-syncing on every upstream release, which defeats the
point of it being published. The Warehouse's `chart:` subscription tracks
real chart SemVer releases directly.

## Secrets

Argo CD renders charts via `helm template` with no cluster access, so
Helm's `lookup` (which this chart normally uses to preserve
auto-generated secrets across upgrades) always resolves empty --
deploying as-is would regenerate random secrets on every sync. Each stage's
`release.yaml` sets `externalSecret.enabled`/`externalSecret.name` and
`postgresql.existingSecret` instead, pointing at Secrets created by the
`sealed-secrets` controller (see `infrastructure/sealed-secrets/`) from
this app's `env/<stage>/secret.sealed.yaml` -- created via:

```bash
task sealed-secrets:seal -- akkoma-dev akkoma-secrets apps/akkoma/env/dev/secret.sealed.yaml \
  secret-key-base=$(openssl rand -hex 32) \
  signing-salt=$(openssl rand -hex 4) \
  release-cookie=$(openssl rand -hex 32)
task sealed-secrets:seal -- akkoma-dev akkoma-postgresql apps/akkoma/env/dev/secret.sealed.yaml \
  postgres-password=$(openssl rand -hex 16)
```

Repeat per stage (`akkoma-staging`, `akkoma-prod` namespaces). Kargo never
touches `secret.sealed.yaml` -- it isn't a release artifact.

## Things to know

- The Warehouse is chart-only, watching real chart SemVer -- no image
  subscription needed; the chart's own default `image.tag`/`appVersion`
  tracks the akkoma app version already.
- Storage defaults (bundled Postgres StatefulSet), and TLS/ingress
  (disabled, placeholder domains) are deferred -- see the design spec in
  `docs/superpowers/specs/`.
