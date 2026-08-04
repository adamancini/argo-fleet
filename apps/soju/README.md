# soju — external OCI chart, promotions commit to main

Deploys [soju-helm](https://github.com/adamancini/soju-helm)'s published
chart (`oci://ghcr.io/adamancini/charts/soju`) directly. Same pattern as
`apps/akkoma/` -- see that README for the full rationale on the multi-source
Application and why the chart isn't vendored.

**Pipeline:** `Warehouse → dev → staging → prod`. `dev`/`staging` run on
`demo1`, `prod` on `demo2`.

## Secrets

`admin.existingSecret` replaces the chart's own post-install-hook-based
admin user creation (which would otherwise rely on Helm `lookup` and
regenerate credentials on every Argo CD sync). Create it per stage via:

```bash
task sealed-secrets:seal -- soju-dev soju-admin apps/soju/env/dev/secret.sealed.yaml \
  admin-username=admin \
  admin-password=$(openssl rand -hex 12)
```

Repeat per stage (`soju-staging`, `soju-prod` namespaces).

## Things to know

- The Warehouse is chart-only -- soju's actual application image comes
  from upstream (`codeberg.org/emersion/soju`), and `soju-helm`'s own
  `check-upstream.yml` bot already keeps the chart's pinned image tag and
  chart version bumped together, so tracking chart SemVer alone is
  sufficient.
- gamja (the bundled web client subchart) stays at its chart defaults --
  no override needed for this phase.
