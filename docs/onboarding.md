# Onboarding a new app

Adding an app touches exactly one place: a new directory under `apps/`.
`bootstrap/` never changes -- its ApplicationSets discover `apps/*/argocd`
and `apps/*/kargo` from git and deploy them automatically on merge.

## The naming convention (load-bearing)

Pick one name and reuse it everywhere. For an app named `orders`:

| Thing | Value |
|---|---|
| Directory | `apps/orders/` |
| Argo CD AppProject | `orders` |
| Kargo Project | `orders` |
| Argo CD Applications | `orders-<stage>` |
| Namespaces | `orders-<stage>` |

## Pattern: external OCI chart (what akkoma and soju use)

Use this when the app is an independently published, versioned Helm chart
you don't want to vendor -- copying chart source in means manually
re-syncing on every upstream release.

1. `kargo/warehouse.yaml`: a `chart:` subscription against the chart's OCI
   registry, `semverConstraint` selecting real releases. `chart.name` must
   stay unset for `oci://` URLs.
2. `env/<stage>/release.yaml`: `chartVersion` (bumped by Kargo's
   `yaml-update` step on every promotion) plus a `values:` block for that
   stage's config.
3. `argocd/appset.yaml`: a `files` generator (not `directories`) reading
   `env/*/release.yaml`, templating a multi-source Application -- source 1
   is the OCI chart at `{{.chartVersion}}` with the stage's values spelled
   out under `helm.valuesObject`, templating only the individual string
   leaf fields that genuinely vary by stage (e.g.
   `domain: '{{.values.akkoma.domain}}'`, quoted). `valuesObject` is an
   object-typed field, so `valuesObject: '{{.values}}'` does NOT work --
   Argo CD's Go-template engine only substitutes into string fields (the
   same restriction documented for `syncPolicy`). For a boolean flag that's
   identical at every stage (e.g. `externalSecret.enabled`), just write it
   as a plain YAML boolean instead of templating it -- an unquoted
   `{{...}}` in that position is ambiguous with YAML flow-mapping syntax,
   and a quoted `"false"` is a non-empty string, which Helm/Sprig `if`
   treats as truthy. Source 2 is this repo's own path for that stage's
   `secret.sealed.yaml`, if any -- it MUST set `directory.include:
   '*.sealed.yaml'` on that source. Without it, this is a directory-type
   source with no filter, so the repo-server tries to render every `.yaml`
   in `env/<stage>/` as a manifest, including the plain-data
   `release.yaml` (no `apiVersion`/`kind`), which fails manifest
   generation for the Application permanently -- not just until secrets
   are sealed.
4. `kargo/tasks.yaml`: `git-clone` -> `yaml-update` (bump `chartVersion`) ->
   `git-commit` -> `git-push` -> `argocd-update`.

## Secrets: never rely on Helm `lookup`

Argo CD renders charts via `helm template` with no cluster access -- any
chart logic depending on `lookup` (common for "generate once, preserve
across upgrades" secrets) will regenerate random values on every sync
instead. Check whether the chart exposes an `existingSecret`/
`externalSecret` escape hatch (most well-maintained charts do); if so,
create the real Secret via Sealed Secrets (`task sealed-secrets:seal`,
see the repo root README) and reference it by name in `release.yaml`'s
`values:` block -- never set secret material directly in `release.yaml`,
which is committed in plaintext.

## Checklist before opening the PR

- [ ] `kargo/project.yaml` carries `argocd.argoproj.io/sync-wave: "-1"`.
- [ ] Every Application the pipeline syncs carries
      `kargo.akuity.io/authorized-stage: <project>:<stage>`.
- [ ] The Warehouse doesn't create a promote-loop: if promotions commit to
      main, don't also subscribe to main via git.
- [ ] New Kargo project -> new git write credentials for it.
