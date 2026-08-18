---
id: AF-q5yh
title: "Scaffold arr-stack AppProject + vendored Kargo chart + per-app Kargo pipeline ApplicationSet"
status: open
priority: 1
type: task
labels: [walking-skeleton]
parent: AF-j5rz
created_at: 2026-08-18T18:53:28Z
created_by: ada
updated_at: 2026-08-18T18:53:28Z
content_hash: "sha256:7d3d177ceddd1babc28a5f4a93e422c6ec282f998d166351e797e465c1940fb2"
---

## Description
Description:
Stand up the Kargo-pipeline-generation half of the arr-stack PoC end to end: a new `arr-stack` AppProject, a vendored Helm chart that renders a Project/Warehouse/3xStage/Tasks set per app, and the list-generator ApplicationSet that renders that chart once per app -> 6 independent Kargo pipelines from one shared template. This is the epic's walking skeleton: it is the first slice that proves the whole generation mechanism end to end (bootstrap directory discovery -> AppProject -> ApplicationSet(list) -> per-app Application -> Helm chart render -> Project/Warehouse/Stage), for all 6 apps, statically verifiable without a live cluster.

Context:
`apps/arr-stack/` is a brand-new directory under `apps/`, discovered automatically by the existing `bootstrap/fleet-argocd-apps.yaml` (git `directories` generator over `apps/*/argocd`, wrapper Application `argocd-arr-stack`, `destination.name: in-cluster`, source type `directory` with `recurse: true`). No `bootstrap/*.yaml` file is ever edited by this story or any other story in this epic -- `AGENTS.md` is explicit that adding app-specific config there should never be needed, and this design's entire premise depends on it.

**Load-bearing architecture finding, confirmed against Argo CD source, not guessed -- read before writing any file in `kargo-chart/`:** `fleet-argocd-apps.yaml`'s wrapper Application uses a `directory`-type source with `recurse: true`. Per `~/src/github.com/argoproj/argo-cd/reposerver/repository/repository.go` (`getPotentiallyValidManifests`, `filepath.Walk` with `recurse=true`, ~line 2221), this walks EVERY subdirectory under `apps/arr-stack/argocd/` with no Helm-chart-boundary awareness, and attempts to parse every `*.yaml`/`*.yml`/`*.json` file it finds as a literal Kubernetes manifest. A raw (unrendered) Helm chart template value like `name: {{ .Values.appName }}` is NOT valid standalone YAML -- a plain scalar cannot start with `{` (the flow-mapping-start indicator) -- so if `kargo-chart/` is left unprotected, `argocd-arr-stack`'s manifest generation breaks for the WHOLE wrapper Application (both the workloads and Kargo halves of this design), not just the chart. Argo CD ships a documented per-file escape hatch for exactly this: any file whose raw bytes contain the literal string `+argocd:skip-file-rendering` is skipped entirely by directory-type manifest generation, regardless of extension or glob (confirmed constant `skipFileRenderingMarker = "+argocd:skip-file-rendering"`, `repository.go:84`). Every file under `apps/arr-stack/argocd/kargo-chart/` (including `Chart.yaml`) MUST include `# +argocd:skip-file-rendering` as a YAML comment -- harmless to real Helm rendering (Helm ignores `#` comments), and it is the only in-scope fix (adding a `directory.exclude` to `bootstrap/fleet-argocd-apps.yaml` itself would violate the epic's no-bootstrap-edit rule). This mirrors the same underlying class of problem this repo's own vault knowledge already documents for `bootstrap/infra-apps.yaml` and non-raw-manifest content living under a wholesale-synced `*/argocd` tree (`.vault/knowledge/patterns/Infra appset directory boundary for bootstrap wholesale sync.md`) -- same root cause (a directory-type source with no awareness of "this subtree means something different"), different concrete fix (a skip marker here, since the offending content is a legitimately-rendered-elsewhere Helm chart, not a plain-data file that needs a sibling directory).

The task chain (`git-clone -> yaml-update -> git-commit -> git-push -> argocd-update`) and the `sync-wave: "-1"` annotation on `project.yaml` are this repo's existing, already-working convention -- `apps/akkoma/kargo/{project,stages,tasks}.yaml` is the reference implementation to copy the SHAPE of (not the values); do not invent a new task chain shape.

**Warehouse image subscription -- confirmed strategy, one detail to verify against the skill/CRD reference before finalizing:** hotio images (all six apps' image source) publish under a mutable channel tag (`release`) rather than semver-versioned tags -- this is why the `env/<app>/<stage>/release.yaml` contract's seed value is literally `imageTag: release`, not a version string. Kargo's `ImageSubscription.ImageSelectionStrategy: Digest` with `Constraint: <mutable tag name>` is built exactly for this case -- confirmed by reading `~/src/github.com/akuity/kargo/pkg/image/digest_selector.go`: the `Digest` strategy's selector stores `Constraint` as `mutableTag` and matches on that exact tag, tracking digest changes underneath it rather than tag changes. Use `imageSelectionStrategy: Digest` / `constraint: release` on each app's `Warehouse`. One thing this story must still confirm via the mandatory skill (`devops-toolkit:akp-platform`, `references/kargo-promotion-patterns.md`) and the Kargo CRD reference (https://doc.crds.dev/github.com/akuity/kargo) before finalizing `kargo-chart/templates/tasks.yaml`: whether the promotion task's `imageFrom(vars.image)` expression should write `.Tag` or `.Digest` into `release.yaml`'s `imageTag` field for a `Digest`-strategy subscription -- do not guess between the two without checking the actual `DiscoveredImageReference`/Freight image field names Kargo exposes to promotion-step expressions.

USER INTENT:
Anyone reading `apps/arr-stack/argocd/` needs to see, in one glance, that six independent Kargo promotion pipelines exist as six generated instances of ONE reviewable template -- not six near-identical hand-copied files that will drift the moment someone edits one and forgets the other five. The chart's per-app scalar substitution (`appName`, `image`) is the whole DRY claim for the Kargo half of this design; this story is what makes that claim real and inspectable, not just asserted.

IMPLEMENTATION:
1. Create `apps/arr-stack/argocd/appproject.yaml`:
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: AppProject
   metadata:
     name: arr-stack
     namespace: argocd
   spec:
     description: DRY *arr family workloads + generated Kargo pipelines (PoC) -- Sonarr, Radarr, Lidarr, Bazarr, Prowlarr, Overseerr
     sourceRepos:
       - '*'
     destinations:
       - server: '*'
         name: '*'
         namespace: '*'
     clusterResourceWhitelist:
       - group: '*'
         kind: '*'
   ```
   (Mirrors `apps/akkoma/argocd/appproject.yaml`'s existing shape exactly -- do not invent a narrower one.)

2. Create `apps/arr-stack/argocd/kargo-chart/Chart.yaml`:
   ```yaml
   # +argocd:skip-file-rendering
   apiVersion: v2
   name: arr-stack-kargo
   description: Shared Kargo Project/Warehouse/Stage/Tasks chart, rendered once per *arr app by appset-kargo.yaml
   version: 0.1.0
   ```

3. Create `apps/arr-stack/argocd/kargo-chart/templates/project.yaml`:
   ```yaml
   # +argocd:skip-file-rendering
   apiVersion: kargo.akuity.io/v1alpha1
   kind: Project
   metadata:
     name: {{ .Values.appName }}
     annotations:
       argocd.argoproj.io/sync-wave: "-1"
   ```

4. Create `apps/arr-stack/argocd/kargo-chart/templates/warehouse.yaml`:
   ```yaml
   # +argocd:skip-file-rendering
   apiVersion: kargo.akuity.io/v1alpha1
   kind: Warehouse
   metadata:
     name: {{ .Values.appName }}
     namespace: {{ .Values.appName }}
   spec:
     subscriptions:
     - image:
         repoURL: {{ .Values.image }}
         imageSelectionStrategy: Digest
         constraint: release
   ```

5. Create `apps/arr-stack/argocd/kargo-chart/templates/stages.yaml` -- three `Stage` objects (`dev`/`staging`/`prod`), same shape as `apps/akkoma/kargo/stages.yaml` (requestedFreight chain dev<-staging<-prod, `promotionTemplate.spec.steps: [{task: {name: promote}}]`), parameterized by `{{ .Values.appName }}`, EVERY generated workload Application annotated `kargo.akuity.io/authorized-stage: '{{ .Values.appName }}:<stage>'` on the workloads side (Story 4) -- this file only defines the Stages themselves. No `verification.analysisTemplates` block (none specified for this PoC; do not add one un-asked -- see `AGENTS.md`'s caution that an `AnalysisTemplate` reference is a silent no-op without Argo Rollouts CRDs installed).
   ```yaml
   # +argocd:skip-file-rendering
   # yaml-language-server: $schema=https://raw.githubusercontent.com/akuity/kargo/refs/heads/main/ui/src/gen/schema/stages.kargo.akuity.io_v1alpha1.json
   apiVersion: kargo.akuity.io/v1alpha1
   kind: Stage
   metadata:
     name: dev
     namespace: {{ .Values.appName }}
     annotations:
       kargo.akuity.io/color: green
   spec:
     requestedFreight:
     - origin:
         kind: Warehouse
         name: {{ .Values.appName }}
       sources:
         direct: true
     promotionTemplate:
       spec:
         steps:
         - task:
             name: promote
   ---
   # +argocd:skip-file-rendering
   # yaml-language-server: $schema=https://raw.githubusercontent.com/akuity/kargo/refs/heads/main/ui/src/gen/schema/stages.kargo.akuity.io_v1alpha1.json
   apiVersion: kargo.akuity.io/v1alpha1
   kind: Stage
   metadata:
     name: staging
     namespace: {{ .Values.appName }}
     annotations:
       kargo.akuity.io/color: amber
   spec:
     requestedFreight:
     - origin:
         kind: Warehouse
         name: {{ .Values.appName }}
       sources:
         stages:
         - dev
     promotionTemplate:
       spec:
         steps:
         - task:
             name: promote
   ---
   # +argocd:skip-file-rendering
   # yaml-language-server: $schema=https://raw.githubusercontent.com/akuity/kargo/refs/heads/main/ui/src/gen/schema/stages.kargo.akuity.io_v1alpha1.json
   apiVersion: kargo.akuity.io/v1alpha1
   kind: Stage
   metadata:
     name: prod
     namespace: {{ .Values.appName }}
     annotations:
       kargo.akuity.io/color: red
   spec:
     requestedFreight:
     - origin:
         kind: Warehouse
         name: {{ .Values.appName }}
       sources:
         stages:
         - staging
     promotionTemplate:
       spec:
         steps:
         - task:
             name: promote
   ```

6. Create `apps/arr-stack/argocd/kargo-chart/templates/tasks.yaml`, same shape as `apps/akkoma/kargo/tasks.yaml`, writing to `apps/arr-stack/env/{{ .Values.appName }}/${{ ctx.stage }}/release.yaml`'s `imageTag` key (confirm `.Tag` vs `.Digest` per the note above before finalizing the `yaml-update` value expression):
   ```yaml
   # +argocd:skip-file-rendering
   apiVersion: kargo.akuity.io/v1alpha1
   kind: PromotionTask
   metadata:
     name: promote
     namespace: {{ .Values.appName }}
   spec:
     vars:
     - name: repoURL
       value: https://github.com/adamancini/argo-fleet.git
     - name: image
       value: {{ .Values.image }}
     steps:
     - uses: git-clone
       config:
         repoURL: ${{ vars.repoURL }}
         checkout:
         - branch: main
           path: ./src
     - uses: yaml-update
       as: update-image-tag
       config:
         path: ./src/apps/arr-stack/env/{{ .Values.appName }}/${{ ctx.stage }}/release.yaml
         updates:
         - key: imageTag
           value: ${{ imageFrom(vars.image).Tag }}
     - uses: git-commit
       as: commit
       config:
         path: ./src
         message: "arr-stack/{{ .Values.appName }}/${{ ctx.stage }}: promote image ${{ imageFrom(vars.image).Tag }}"
     - uses: git-push
       config:
         path: ./src
         targetBranch: main
     - uses: argocd-update
       config:
         apps:
         - name: arr-{{ .Values.appName }}-${{ ctx.stage }}
   ```

7. Create `apps/arr-stack/argocd/appset-kargo.yaml` -- verbatim per the design spec (list generator, 6 apps -> 6 Applications, `destination.name: kargo`, `project: arr-stack`, rendering `kargo-chart/`):
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

8. Before committing, run the render-diff verification primitive (`.vault/knowledge/patterns/Render-diff verification primitive for ApplicationSet changes.md`): `helm template apps/arr-stack/argocd/kargo-chart --set appName=sonarr --set image=ghcr.io/hotio/sonarr` and again with `--set appName=prowlarr --set image=ghcr.io/hotio/prowlarr` -- confirm both render a well-formed, app-name-scoped `Project`/`Warehouse`/3x`Stage`/`PromotionTask` set with no leftover `{{ }}` placeholders. Then confirm the `+argocd:skip-file-rendering` marker actually prevents the wrapper Application from choking: this can be tested locally without touching the live cluster by running `argocd-cm`-equivalent local YAML-walk logic is unnecessary -- instead, statically confirm every file under `kargo-chart/` contains the literal marker string via `grep -L '+argocd:skip-file-rendering' apps/arr-stack/argocd/kargo-chart/**/*.yaml` (expect empty output -- no file missing the marker). Full live confirmation that the wrapper Application actually syncs happens in Story 7 (human-gated).

KEY FILES:
Create: `apps/arr-stack/argocd/appproject.yaml`, `apps/arr-stack/argocd/kargo-chart/Chart.yaml`, `apps/arr-stack/argocd/kargo-chart/templates/project.yaml`, `apps/arr-stack/argocd/kargo-chart/templates/warehouse.yaml`, `apps/arr-stack/argocd/kargo-chart/templates/stages.yaml`, `apps/arr-stack/argocd/kargo-chart/templates/tasks.yaml`, `apps/arr-stack/argocd/appset-kargo.yaml`.
Reference-only (not modified): `apps/akkoma/argocd/appproject.yaml`, `apps/akkoma/kargo/{project,warehouse,stages,tasks}.yaml`, `AGENTS.md`, `docs/onboarding.md`.

OUT OF SCOPE:
- `apps/arr-stack/argocd/appset-workloads.yaml` (the matrix-generator workload fan-out) -- separate story (Story 4), gated by a separate spike (Story 3).
- `apps/arr-stack/env/<app>/<stage>/release.yaml` contract files -- separate story (Story 2); this story's `tasks.yaml` writes to paths that don't exist as real files until Story 2 lands, which is fine (this story only authors/statically verifies the chart, it does not run a live promotion).
- Any live cluster sync -- this story is authored and statically verified only (`helm template`, marker grep); the first live touch of any arr-stack file happens in Story 7 (human-gated).
- `Stage.spec.verification` / `AnalysisTemplate` -- not specified by the design for this PoC; adding one here would be scope creep and, per `AGENTS.md`, silently no-ops without Argo Rollouts CRDs installed.

DIFF BUDGET:
7 new files, 0 files modified. Expect roughly 120-180 LOC total (chart templates are short; the AppProject and appset-kargo.yaml mirror existing ~30-45 line files in this repo almost verbatim).

PRODUCES:
- `apps/arr-stack/argocd/appproject.yaml` -> AppProject `arr-stack`
    schema: apiVersion: argoproj.io/v1alpha1, kind: AppProject, metadata.name: arr-stack
    source: mirrors apps/akkoma/argocd/appproject.yaml verbatim shape
- `apps/arr-stack/argocd/kargo-chart/` -> vendored Helm chart, values: `appName` (string), `image` (string, no tag)
    schema: templates/project.yaml (Project), templates/warehouse.yaml (Warehouse, imageSelectionStrategy: Digest, constraint: release), templates/stages.yaml (3x Stage: dev/staging/prod), templates/tasks.yaml (PromotionTask `promote`, writes apps/arr-stack/env/{{appName}}/<stage>/release.yaml's imageTag key)
    source: this story's own design, task-chain shape copied from apps/akkoma/kargo/{stages,tasks}.yaml
- `apps/arr-stack/argocd/appset-kargo.yaml` -> ApplicationSet `arr-stack-kargo`
    spec: generators: [list, 6 elements (name/image per the epic's per-app parameter table)]; template.spec.destination.name: kargo; template.spec.source.helm.valuesObject: {appName, image}
    source: docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md, verbatim

TESTING:
No unit-test suite exists for this repo's GitOps manifests -- verification is static/render-level only for this story (no live cluster touch):
- `ruby -ryaml -e "YAML.load_stream(File.read('apps/arr-stack/argocd/appproject.yaml'))" && echo OK` (and the same for `appset-kargo.yaml`) -- confirms both parse as valid YAML.
- `helm template apps/arr-stack/argocd/kargo-chart --set appName=sonarr --set image=ghcr.io/hotio/sonarr` and again with `--set appName=prowlarr --set image=ghcr.io/hotio/prowlarr` -- both must render a complete, well-formed, app-name-scoped Project/Warehouse/3xStage/PromotionTask set with zero unresolved `{{ }}` placeholders in the output.
- `grep -L '+argocd:skip-file-rendering' apps/arr-stack/argocd/kargo-chart/**/*.yaml` -- expect EMPTY output (every file carries the marker).
- `devops-toolkit:yaml-kubernetes-validator` used on every new file before pushing.

Acceptance Criteria:
1. [Ubiquitous] `apps/arr-stack/argocd/appproject.yaml` creates AppProject `arr-stack` with the same permissive shape as `apps/akkoma/argocd/appproject.yaml`.
2. [Ubiquitous] Every file under `apps/arr-stack/argocd/kargo-chart/` (including `Chart.yaml`) contains the literal string `+argocd:skip-file-rendering`, confirmed by `grep -L` returning empty output.
3. [Event] `helm template apps/arr-stack/argocd/kargo-chart --set appName=<app> --set image=<image>` renders a well-formed Project/Warehouse/3xStage/PromotionTask set for both a representative app and a second app, with zero unresolved template placeholders.
4. [Ubiquitous] `kargo-chart/templates/project.yaml` carries `argocd.argoproj.io/sync-wave: "-1"`.
5. [Ubiquitous] `kargo-chart/templates/warehouse.yaml` uses `imageSelectionStrategy: Digest` / `constraint: release`, confirmed against the Kargo CRD reference and the mandatory skill (not left as an unverified guess).
6. [Ubiquitous] `apps/arr-stack/argocd/appset-kargo.yaml` renders exactly 6 Applications (one per app in the epic's per-app parameter table), each `destination.name: kargo`, `project: arr-stack`.
7. [Unwanted] No file under `apps/arr-stack/` shall reference Plex, qBittorrent, rflood, or SABnzbd.
8. [Unwanted] `bootstrap/*.yaml` shall not be modified by this story.
9. Repo-wide grep confirms no name collision between `arr-stack`/`kargo-arr-*`/`sonarr`/`radarr`/`lidarr`/`bazarr`/`prowlarr`/`overseerr` and any existing Application/AppProject/Kargo-Project name in this repo (`akkoma`, `soju`, their generated children).

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory -- `references/gitops-app-patterns.md` for ApplicationSet conventions, `references/kargo-promotion-patterns.md` for the Warehouse/Stage/Task field shapes referenced above), devops-toolkit:helm-chart-developer (mandatory -- vendored chart authoring), devops-toolkit:yaml-kubernetes-validator (mandatory)

## Acceptance Criteria


## Design


## Notes


## History


## Links
- Parent: [[AF-j5rz]]

## Comments
