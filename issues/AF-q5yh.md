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
updated_at: 2026-08-18T19:10:30Z
content_hash: "sha256:9b9049f16423d799f1dce4b97ef80b2e6c632bfa5336c66f3bfed929078db0d2"
blocks: [AF-8r8l, AF-vm0q]
---

## Description
PLACEHOLDER - being replaced

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
    schema: apps/arr-stack/argocd/kargo-chart/templates/project.yaml (Project), apps/arr-stack/argocd/kargo-chart/templates/warehouse.yaml (Warehouse, imageSelectionStrategy: Digest, constraint: release), apps/arr-stack/argocd/kargo-chart/templates/stages.yaml (3x Stage: dev/staging/prod), apps/arr-stack/argocd/kargo-chart/templates/tasks.yaml (PromotionTask `promote`, writes apps/arr-stack/env/{{appName}}/<stage>/release.yaml's imageTag key)
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
devops-toolkit:akp-platform (mandatory -- its GitOps app-patterns reference material for ApplicationSet conventions, and its Kargo promotion-patterns reference material for the Warehouse/Stage/Task field shapes referenced above), devops-toolkit:helm-chart-developer (mandatory -- vendored chart authoring), devops-toolkit:yaml-kubernetes-validator (mandatory)

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
    schema: apps/arr-stack/argocd/kargo-chart/templates/project.yaml (Project), apps/arr-stack/argocd/kargo-chart/templates/warehouse.yaml (Warehouse, imageSelectionStrategy: Digest, constraint: release), apps/arr-stack/argocd/kargo-chart/templates/stages.yaml (3x Stage: dev/staging/prod), apps/arr-stack/argocd/kargo-chart/templates/tasks.yaml (PromotionTask `promote`, writes apps/arr-stack/env/{{appName}}/<stage>/release.yaml's imageTag key)
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
devops-toolkit:akp-platform (mandatory -- its GitOps app-patterns reference material for ApplicationSet conventions, and its Kargo promotion-patterns reference material for the Warehouse/Stage/Task field shapes referenced above), devops-toolkit:helm-chart-developer (mandatory -- vendored chart authoring), devops-toolkit:yaml-kubernetes-validator (mandatory)

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
- 2026-08-18T18:54:17Z dep_added: blocks AF-8r8l
- 2026-08-18T18:57:52Z dep_added: blocks AF-vm0q

## Links
- Parent: [[AF-j5rz]]
- Blocks: [[AF-8r8l]], [[AF-vm0q]]

## Comments
