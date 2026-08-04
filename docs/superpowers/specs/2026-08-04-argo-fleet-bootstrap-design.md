# argo-fleet bootstrap: Sealed Secrets + akkoma/soju on demo1/demo2

## Context

`akkoma-helm` and `soju-helm` are two personal services currently deployed via
Flux `HelmRelease`s in `fleet-infra`, running live on `annarchy.net` (prod)
and `staging.annarchy.net` (staging). The goal is to migrate their GitOps
management to Argo CD/Kargo, eventually on those same real clusters.

Both charts publish versioned OCI Helm charts
(`oci://ghcr.io/adamancini/charts/{akkoma,soju}`) and are designed to be
installed via `helm install`/`helm upgrade` — including relying on Helm's
`lookup` function to preserve auto-generated secrets across upgrades. Argo CD
renders charts via `helm template` with no cluster access, so `lookup` always
resolves empty; deploying either chart through Argo CD as-is would regenerate
random secrets (and invalidate all sessions/admin credentials) on every sync.
Both charts anticipated this and expose an escape hatch
(`externalSecret.enabled`/`externalSecret.name` for akkoma,
`admin.existingSecret` for soju) to read a pre-existing Secret instead.

`fleet-infra` already runs Sealed Secrets and cert-manager as cluster-wide
infrastructure on `annarchy.net`/`staging.annarchy.net`, managed by Flux. The
new `argo-fleet` repo targets `demo1`/`demo2` instead (the same Akuity-hosted
Argo CD/Kargo instance already used by `akp-platform`) — neither cluster has
Sealed Secrets installed yet, so it has to be added as a prerequisite before
akkoma/soju can be onboarded safely.

## Scope

**In scope:**

- New `argo-fleet` repo, bootstrapped independently of `akp-platform`.
- Sealed Secrets controller on `demo1` and `demo2`, sharing one keypair
  (rather than each controller generating its own) so today's sealed secrets
  remain valid after the eventual real-cluster migration.
- A `Taskfile.yml` capturing the repeatable Sealed Secrets operations:
  generating the shared keypair, rotating it, and sealing a new secret.
- Kargo/Argo CD pipelines for `akkoma` and `soju`, dev→staging on `demo1`,
  prod on `demo2` — mirroring `rollouts-app`'s cluster-destination pattern in
  `akp-platform`.

**Explicitly deferred (not built as part of this spec):**

- cert-manager — no real domains are wired up yet, so there's nothing to
  issue TLS certificates for. Placeholder domains are used per stage instead.
- Migrating `annarchy.net`/`staging.annarchy.net` off Flux, and any
  Flux/Argo coexistence handling for the real clusters — moot until that
  migration actually starts. `demo1`/`demo2` are not currently Flux-managed,
  so there is no dual-controller conflict today.
- Real Postgres/S3/CNPG backends for akkoma, or Postgres for soju — both
  apps use each chart's own bundled default (Postgres StatefulSet for akkoma,
  SQLite for soju).

## Repo structure

```text
argo-fleet/
├── Taskfile.yml
├── bootstrap/
│   ├── platform-aoa.yaml       # the one manifest applied by hand
│   ├── infra-apps.yaml         # ApplicationSet discovering infrastructure/*/argocd
│   ├── argocd-apps.yaml        # ApplicationSet discovering apps/*/argocd
│   └── kargo-apps.yaml         # ApplicationSet discovering apps/*/kargo
├── infrastructure/
│   └── sealed-secrets/
│       ├── README.md
│       └── argocd/
│           └── appset.yaml     # list generator: one Application per cluster (demo1, demo2)
├── apps/
│   ├── akkoma/
│   │   ├── README.md
│   │   ├── argocd/
│   │   │   ├── appproject.yaml
│   │   │   └── appset.yaml     # files generator over env/*/release.yaml
│   │   ├── kargo/
│   │   │   ├── project.yaml
│   │   │   ├── warehouse.yaml  # chart subscription, oci://ghcr.io/adamancini/charts/akkoma
│   │   │   ├── stages.yaml     # dev -> staging -> prod
│   │   │   └── tasks.yaml      # yaml-update bumps chartVersion in release.yaml
│   │   └── env/
│   │       ├── dev/{release.yaml, secret.sealed.yaml}
│   │       ├── staging/{release.yaml, secret.sealed.yaml}
│   │       └── prod/{release.yaml, secret.sealed.yaml}
│   └── soju/
│       └── (same shape as akkoma)
└── docs/
    ├── onboarding.md            # the "external OCI chart" pattern, adapted from akp-platform's
    └── infra-dependencies.md    # how to add a new cluster-wide controller (template for cert-manager later)
```

Two discovery roots — `infrastructure/*/argocd` for cluster-wide singletons
with no promotion pipeline, `apps/*/{argocd,kargo}` for tenant apps with a
full Kargo pipeline — because Sealed Secrets isn't something that makes
sense to promote through dev→staging→prod; it just needs to exist,
identically, on every cluster.

## Sealed Secrets

- One controller per cluster (`demo1`, `demo2`) — Sealed Secrets encryption
  is tied to a specific controller's keypair, so each cluster needs its own
  running instance regardless of key strategy.
- **Shared keypair** across clusters, bootstrapped from a pre-generated key
  rather than letting each controller generate its own. A secret sealed once
  decrypts on any cluster running a controller configured with that key —
  including `annarchy.net`/`staging.annarchy.net` once the real-cluster
  migration happens, so today's sealed secrets don't need re-sealing later.
  Trade-off: a compromised key affects every cluster sharing it, not just
  one — acceptable here since these are environments for the same services,
  not isolation boundaries.
- The keypair itself is generated and distributed out-of-band (via
  `task sealed-secrets:generate-keypair`, run by the user) — not generated
  by Claude, and the private key material is never committed to git.
- `infrastructure/sealed-secrets/argocd/appset.yaml` uses a `list` generator
  (not `git.directories`, since there's no per-cluster directory — just a
  fixed list of two known destinations) to template one Application per
  cluster, installing the upstream `sealed-secrets` Helm chart configured to
  use the shared keypair Secret instead of generating its own.

### Taskfile

```bash
task sealed-secrets:generate-keypair   # generate the shared RSA keypair once
task sealed-secrets:rotate-keypair     # rotate to a new keypair, re-seal existing SealedSecrets
task sealed-secrets:seal -- <namespace> <name> <key>=<value>...
                                        # kubeseal a plaintext value against the shared cert,
                                        # writing the result to the right env/<stage>/secret.sealed.yaml
```

This is the standard way any new sealed secret in this repo gets created —
no hand-rolled `kubeseal` invocations.

## akkoma/soju app pipelines

Per app (akkoma, soju), reusing the pattern validated for `rollouts-app` in
`akp-platform` where it applies, adapted for an externally-published OCI
chart rather than a vendored one:

- **Warehouse**: `chart:` subscription against
  `oci://ghcr.io/adamancini/charts/{akkoma,soju}`. Unlike `rollouts-app`'s
  `<run#>-<color>` tags, these charts use real SemVer, so a standard semver
  selection strategy applies directly.
- **Stages**: `dev → staging → prod`. `dev`/`staging` destination `demo1`,
  `prod` destination `demo2` — same per-stage destination override technique
  already used in `rollouts-app`'s `argocd/appset.yaml` (Go templating,
  `{{- if eq .path.basename "prod" }}demo2{{- else }}demo1{{- end }}`).
- **`env/<stage>/release.yaml`**: holds `chartVersion` (bumped by Kargo via
  `yaml-update` on every promotion, same mechanism as `guestbook-helm`'s
  `image.tag` bump) and a `values:` block with that stage's placeholder
  domain and the secret-reference fields (`externalSecret.enabled: true` /
  `externalSecret.name: ...` for akkoma, `admin.existingSecret: ...` for
  soju).
- **`env/<stage>/secret.sealed.yaml`**: the SealedSecret CR for that stage,
  created once via `task sealed-secrets:seal` and committed as a static
  file. Kargo promotions never touch this file — it isn't a release
  artifact.
- **Argo CD Application**: multi-source, the same technique `guestbook-helm`
  already uses in `akp-platform` for its `$values` split. Source 1 is the
  OCI chart at `{{.chartVersion}}` with `helm.valuesObject` from the pin
  file's `values` block; source 2 is the git path to that stage's
  `secret.sealed.yaml`, applied into the same namespace.
- **ApplicationSet generator**: `files`, matching
  `apps/{akkoma,soju}/env/*/release.yaml` — not `directories`, since the
  generator needs the pin file's *contents* (chart version, values) as
  template variables, not just the matched path.
- **PromotionTask**: `git-clone` → `yaml-update` (bump `chartVersion` in
  `release.yaml`) → `git-commit` → `git-push` → `argocd-update`. Identical
  shape to `rollouts-app`'s `kargo/tasks.yaml`.

### Storage/database defaults

Each chart's own bundled default is used as-is, for both apps and all three
stages: Postgres StatefulSet for akkoma, SQLite for soju. No CNPG, external
Postgres, or S3 backend — those remain available later via the same
`values:` block in `release.yaml` if needed, with no pipeline changes.

### Domains

Placeholder per stage (e.g. `akkoma-dev.example.com`,
`akkoma-staging.example.com`, `akkoma.example.com` for prod; same scheme for
soju). Nothing will actually resolve or federate until real domains are
substituted in — that substitution is a values-only change, not a pipeline
change.
