# *arr Family DRY ApplicationSet + Generated Kargo Pipelines

**Goal:** Demonstrate that a family of near-identical apps can be onboarded
to `argo-fleet` without copy-pasting one Argo CD Application set and one
Kargo `Project`/`Warehouse`/`Stage` set per app — using Argo CD
`ApplicationSet` generators to fan out both the workload deployments *and*
the Kargo promotion pipelines from shared templates plus a small per-app
parameter list. This answers "is it possible?" as a proof of concept; it is
not itself the `htpc` migration off Flux (see Out of scope).

## Background

`fleet-infra`'s `apps/base/htpc/` namespace runs six apps — Sonarr, Radarr,
Lidarr, Bazarr, Prowlarr, Overseerr — as six hand-copied Flux `HelmRelease`
files (~80 lines each) against the same upstream chart (bjw-s
`app-template`). The only real variance across them: app name, image repo,
container port, whether a `downloads` volume mount exists, and (currently,
inconsistently) whether `PUID`/`PGID` use substitution variables or
hardcoded literals. `htpc`'s other apps (Plex, qBittorrent, rflood, SABnzbd)
were investigated and excluded — each has genuine per-app customization
(GPU passthrough, VPN sidecars, custom `rtorrent.rc`) that a shared
generator would fight, not help.

`argo-fleet` itself has no existing precedent for fanning out *apps* (only
`akkoma`/`soju`'s `argocd/appset.yaml` fanning out *stages* within one app),
and two structural constraints from its bootstrap layer matter here:

1. `bootstrap/fleet-argocd-apps.yaml` / `fleet-kargo-apps.yaml` (git
   `directories` generator over `apps/*/argocd` and `apps/*/kargo`) derive
   the Argo CD `AppProject`/Kargo `Project` scope from the directory name
   (`{{path[1]}}`). One `apps/<name>/` directory is the unit bootstrap
   discovers — this cannot be routed around from inside an app without
   editing bootstrap, which onboarding.md documents as something that
   should never need to happen per app.
2. An `ApplicationSet` object must be reconciled by an Argo CD control
   plane, so it can only usefully live under a path whose wrapper
   Application targets `destination.name: in-cluster` (as
   `fleet-argocd-apps.yaml`'s wrapper does) — not under `apps/*/kargo`,
   whose wrapper targets `destination.name: kargo`. A second, nested
   `ApplicationSet` cannot be used to fan out Kargo CRDs.

Akuity's own `sedemo-platform` repo (`templated-teams/`) validates the
resulting shape: Kargo has no generator of its own, so it fans out
`Project`/`Warehouse`/`Stage` objects by having ordinary Argo CD
`Application`s (created per app instance) render a shared Helm chart with
`destination.name: kargo` — each app instance keeps its own independent
`Project`, so DRY comes from the shared chart, not from merging promotion
boundaries. `sedemo-platform` also confirms the deciding factor for when
this is a good fit: apps genuinely similar enough that one parameterized
chart captures the difference. That matches these six `*arr` apps exactly.

`argo-fleet`'s `apps/` currently targets the shared Akuity-hosted `demo1`/
`demo2`/`kargo` instance (also serving `akp-platform`'s live demo) as a
staging ground before the eventual move to the real `annarchy.net`
clusters — see `docs/superpowers/specs/2026-08-05-bootstrap-name-collision-design.md`.
This design targets that same staging instance.

## Design

### Directory layout

One new directory, discovered automatically by the existing
`fleet-argocd-apps.yaml` — no bootstrap changes:

```
apps/arr-stack/
├── argocd/
│   ├── appproject.yaml          # AppProject "arr-stack"
│   ├── appset-workloads.yaml    # matrix: 6 apps x stage -> 18 Applications
│   ├── appset-kargo.yaml        # list: 6 apps -> 6 Applications (destination: kargo)
│   └── kargo-chart/             # vendored Helm chart: Project+Warehouse+3xStage+Tasks
│       ├── Chart.yaml
│       └── templates/
│           ├── project.yaml
│           ├── warehouse.yaml
│           ├── stages.yaml
│           └── tasks.yaml
└── env/
    ├── sonarr/{dev,staging,prod}/release.yaml
    ├── radarr/{dev,staging,prod}/release.yaml
    ├── lidarr/{dev,staging,prod}/release.yaml
    ├── bazarr/{dev,staging,prod}/release.yaml
    ├── prowlarr/{dev,staging,prod}/release.yaml
    └── overseerr/{dev,staging,prod}/release.yaml
```

No `apps/arr-stack/kargo/` directory is needed. The Kargo CRDs are
*generated from* `argocd/appset-kargo.yaml` (targeting `destination.name:
kargo` directly from an Application created on the Argo CD control plane),
not synced statically from a `kargo/` folder — `fleet-kargo-apps.yaml`
simply won't match anything for `arr-stack`, which is fine; it only creates
a wrapper Application per matched directory.

### Namespace decision: one shared namespace per stage, not one per app

`onboarding.md`'s documented convention is `Namespaces: <name>-<stage>`,
one per app. This design deliberately deviates: all six apps share
`arr-stack-{dev,staging,prod}`, mirroring `fleet-infra`'s existing single
`htpc` namespace. Rationale: these apps conceptually share a media library
and, in the real migration, shared PVCs (`data-nfs`) — splitting them into
six namespaces would fight that reality and gain nothing for this family
specifically (unlike `akkoma`/`soju`, which are unrelated to each other).
The Kargo side is unaffected — each app still gets its own `Project`
namespace (`sonarr`, `radarr`, ...) on the `kargo` cluster, so promotion
pipelines stay fully independent per app regardless of workload namespace
sharing.

### Per-app parameter table

The single source of truth both generators read from (see below for where
it's expressed):

| app | image | port | has downloads mount |
|---|---|---|---|
| sonarr | `ghcr.io/hotio/sonarr` | 8989 | yes |
| radarr | `ghcr.io/hotio/radarr` | 7878 | yes |
| lidarr | `ghcr.io/hotio/lidarr` | 8686 | yes |
| bazarr | `ghcr.io/hotio/bazarr` | 6767 | yes |
| prowlarr | `ghcr.io/hotio/prowlarr` | 9696 | no |
| overseerr | `ghcr.io/hotio/overseerr` | 5055 | no |

`PUID`/`PGID` are fixed at generation time to always use a literal value
(no Flux-style `${app_puid}` substitution exists in Argo CD/Kargo) — this
also resolves the hardcoded-vs-substituted inconsistency found in
`fleet-infra`'s Prowlarr/nzbhydra/SABnzbd manifests, for free, since every
app is now rendered from the one template.

Persistence: no explicit `storageClass` is set on `config`/`downloads`
PVCs — `demo1`/`demo2` have no NFS-backed storage class equivalent to
`fleet-infra`'s `synology-csi-retain`, so this design relies on the
cluster's default `StorageClass` and uses small (1Gi) PVCs. Real NFS-backed
shared media volumes are out of scope here (see Out of scope).

### `appset-workloads.yaml` — matrix generator, 6 apps x stage

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: arr-stack-workloads
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - matrix:
        generators:
          - list:
              elements:
                - name: sonarr
                  image: ghcr.io/hotio/sonarr
                  port: "8989"
                  hasDownloads: "true"
                - name: radarr
                  image: ghcr.io/hotio/radarr
                  port: "7878"
                  hasDownloads: "true"
                - name: lidarr
                  image: ghcr.io/hotio/lidarr
                  port: "8686"
                  hasDownloads: "true"
                - name: bazarr
                  image: ghcr.io/hotio/bazarr
                  port: "6767"
                  hasDownloads: "true"
                - name: prowlarr
                  image: ghcr.io/hotio/prowlarr
                  port: "9696"
                  hasDownloads: "false"
                - name: overseerr
                  image: ghcr.io/hotio/overseerr
                  port: "5055"
                  hasDownloads: "false"
          - git:
              repoURL: https://github.com/adamancini/argo-fleet.git
              revision: HEAD
              files:
                - path: "apps/arr-stack/env/{{.name}}/*/release.yaml"
  template:
    metadata:
      name: "arr-{{.name}}-{{.path.basename}}"
      annotations:
        kargo.akuity.io/authorized-stage: "{{.name}}:{{.path.basename}}"
    spec:
      project: arr-stack
      source:
        # oci:// source: chart name is part of the path, so `chart:` stays
        # unset, per onboarding.md's documented rule for OCI sources.
        repoURL: oci://ghcr.io/bjw-s-labs/helm/app-template
        targetRevision: 4.x
        helm:
          values: |
            defaultPodOptions:
              automountServiceAccountToken: false
            controllers:
              main:
                pod:
                  securityContext:
                    fsGroup: 100
                    fsGroupChangePolicy: OnRootMismatch
                containers:
                  main:
                    image:
                      repository: {{.image}}
                      tag: "{{.values.imageTag}}"
                    env:
                      - name: PUID
                        value: "1000"
                      - name: PGID
                        value: "1000"
                      - name: TZ
                        value: "America/New_York"
                      - name: UMASK
                        value: "002"
            service:
              main:
                enabled: true
                ports:
                  http:
                    port: 80
                    targetPort: {{.port}}
            ingress:
              main:
                enabled: false
            persistence:
              config:
                accessMode: ReadWriteOnce
                size: 1Gi
{{- if eq .hasDownloads "true"}}
              downloads:
                accessMode: ReadWriteOnce
                size: 1Gi
                advancedMounts:
                  main:
                    main:
                      - path: /data
{{- end}}
      destination:
        name: "{{- if eq .path.basename \"prod\" -}}demo2{{- else -}}demo1{{- end -}}"
        namespace: "arr-stack-{{.path.basename}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

This uses `helm.values` (a raw multi-line string), not `helm.valuesObject`
— `akkoma`'s `appset.yaml` already documents why: `valuesObject` is a
structured/object field, so Argo CD's Go-template substitution can only
land on string leaves, not build conditional structure. `values` is a
plain string, so real `{{- if}}` blocks work once rendered and re-parsed as
YAML by Helm — this is what makes the `hasDownloads` conditional possible
at all, and is a deliberate departure from `akkoma`'s pattern for that
reason.

**Open validation item:** the inner `git files` generator's `path`
interpolates `{{.name}}` from the outer `list` generator's element — Argo
CD's `matrix` generator supports one generator referencing another's
params, but the exact syntax/version support needs to be confirmed against
whatever Argo CD version the shared `demo1`/`demo2`/`kargo` instance runs,
during implementation. If unsupported, the fallback is to drop the `git
files` generator entirely and add `dev`/`staging`/`prod` as a second static
`list` generator (matching `sedemo-platform`'s `demo-microservices`
precedent) — at the cost of losing the "Kargo commits back to `release.yaml`
and the ApplicationSet just picks it up" mechanism `akkoma`/`soju` rely on
for `chartVersion`/tag bumps. This must be settled before implementation,
not deferred silently.

### `appset-kargo.yaml` — list generator, 6 apps (no stage axis)

A `Project`/`Warehouse`/3x`Stage` set is per-app, not per-stage — one
Application per app, each rendering `kargo-chart/`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: arr-stack-kargo
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - name: sonarr
            image: ghcr.io/hotio/sonarr
          - name: radarr
            image: ghcr.io/hotio/radarr
          - name: lidarr
            image: ghcr.io/hotio/lidarr
          - name: bazarr
            image: ghcr.io/hotio/bazarr
          - name: prowlarr
            image: ghcr.io/hotio/prowlarr
          - name: overseerr
            image: ghcr.io/hotio/overseerr
  template:
    metadata:
      name: "kargo-arr-{{name}}"
    spec:
      project: arr-stack
      source:
        repoURL: https://github.com/adamancini/argo-fleet.git
        targetRevision: HEAD
        path: apps/arr-stack/argocd/kargo-chart
        helm:
          valuesObject:
            appName: "{{name}}"
            image: "{{image}}"
      destination:
        name: kargo
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

`kargo-chart/templates/*` render (per app, scalar substitution only — no
loop needed inside the chart itself, since one Application already equals
one app):

- `project.yaml`: `kind: Project`, `metadata.name: {{.Values.appName}}`,
  `argocd.argoproj.io/sync-wave: "-1"` (matching `akkoma`'s existing
  convention).
- `warehouse.yaml`: `kind: Warehouse`, image subscription against
  `{{.Values.image}}`.
- `stages.yaml`: `dev`/`staging`/`prod` `Stage` objects — promotion updates
  `apps/arr-stack/env/{{.Values.appName}}/<stage>/release.yaml`'s
  `imageTag` field via the same `git-clone` -> `yaml-update` ->
  `git-commit` -> `git-push` -> `argocd-update` task chain `akkoma`/`soju`
  already use, so this reuses an existing, already-working task shape
  rather than inventing a new one.
- `tasks.yaml`: the shared promotion task definition, parameterized by
  `{{.Values.appName}}`.

### `env/<app>/<stage>/release.yaml` contract

The one thing that's genuinely per-instance state, not template-able —
Kargo's promotion writes the currently-promoted tag here:

```yaml
imageTag: release
values: {}
```

### Promotion lifecycle (end to end)

1. `kargo-chart`'s `Warehouse` for e.g. `sonarr` discovers a new tag on
   `ghcr.io/hotio/sonarr`.
2. Kargo's `dev` `Stage` for `sonarr` auto-promotes: runs the shared task,
   bumping `apps/arr-stack/env/sonarr/dev/release.yaml`'s `imageTag` and
   pushing to `main`.
3. `appset-workloads.yaml`'s inner `git files` generator picks up the
   changed `release.yaml`, regenerates the `arr-sonarr-dev` Application's
   params, and Argo CD syncs the new tag to `arr-stack-dev` namespace on
   `demo1`.
4. Manual/gated promotion moves the same Freight through `staging` ->
   `prod`, independently of every other `*arr` app's own `Warehouse`/Stage
   chain — promoting Sonarr never touches Radarr's `release.yaml` or vice
   versa.

## Verification

**Static (safe to run without touching the shared instance):**

- `yamllint`/`kubeconform` (or `argocd app get --dry-run` if available
  locally) against `appproject.yaml`, `appset-workloads.yaml`,
  `appset-kargo.yaml`, and every `kargo-chart/templates/*.yaml`.
- `helm template apps/arr-stack/argocd/kargo-chart --set appName=sonarr
  --set image=ghcr.io/hotio/sonarr` for at least two apps (one with
  `hasDownloads: true`, one `false`) — confirm the rendered `Project`/
  `Warehouse`/`Stage` set is well-formed and app-name-scoped correctly.
- Manually render the `appset-workloads.yaml` template's `helm.values`
  block for both a `hasDownloads: true` and `hasDownloads: false` app (by
  hand-substituting the Go-template fields) and run it through `helm
  template <app-template chart>` to confirm the conditional persistence
  block parses.
- Repo-wide grep confirming `apps/arr-stack/` doesn't collide with any
  existing Application/AppProject/Project name in this repo (`akkoma`,
  `soju`, and their generated children).

**Live (human-run only — this is the shared `demo1`/`demo2`/`kargo`
instance also serving `akp-platform`'s live demo; no agent may execute
these steps unsupervised, per the precedent in
`2026-08-05-bootstrap-name-collision-design.md`):**

1. Baseline: `argocd app list` / `argocd appset list` — confirm no
   `arr-*`/`kargo-arr-*`-named resource exists yet.
2. Merge to `main`; confirm `fleet-argocd-apps.yaml` picks up
   `apps/arr-stack/argocd` and creates wrapper Application
   `argocd-arr-stack`, `Synced`/`Healthy`.
3. Confirm `arr-stack-workloads` and `arr-stack-kargo` ApplicationSets
   appear and each generates the expected child count (18 and 6
   respectively).
4. Confirm at least one full app (e.g. Sonarr) reaches `Synced`/`Healthy`
   in `arr-stack-dev` on `demo1`, and its Kargo `Project`/`Warehouse`/
   `Stage` trio is visible and healthy on the `kargo` cluster.
5. Trigger one real promotion (bump `env/sonarr/dev/release.yaml` by hand
   or let the `Warehouse` discover a real tag) and confirm the workload
   Application picks up the new tag without any manual `appset-workloads.yaml`
   edit — this is the actual proof of the DRY claim.

## Out of scope

- Migrating `fleet-infra`'s real `htpc` namespace off Flux — this is a
  proof of concept on the `demo1`/`demo2`/`kargo` staging instance, not a
  cutover. No real NFS-backed shared media volumes, no real hotio image
  history, no Gateway API `HTTPRoute`/ingress wiring (the existing
  `infrastructure/traefik-gateway` + `kube-prometheus-stack`'s
  `grafana-httproute.yaml` precedent would be the template for that, when
  it's needed).
- Plex, qBittorrent, rflood, SABnzbd — excluded by design; each has real
  per-app customization the shared chart would fight, not simplify.
- Adopting `sedemo-platform`'s `kargo-shared` `CustomPromotionStep`
  library — none of these six apps need custom promotion logic beyond a
  tag bump; revisit only if a future app in this family does.
- Any edit to `bootstrap/*.yaml` — this design requires none.
