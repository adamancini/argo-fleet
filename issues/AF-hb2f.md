---
id: AF-hb2f
title: "Scaffold arr-stack AppProject + vendored Kargo chart + per-app Kargo pipeline ApplicationSet"
status: closed
priority: 1
type: task
labels: [walking-skeleton, accepted]
parent: AF-j5rz
created_at: 2026-08-18T19:11:30Z
created_by: ada
updated_at: 2026-08-19T15:09:40Z
content_hash: "sha256:2ab147e1ce3d828075e823b2fa906079e8748bea2f78300258ae0a595f511789"
assignee: dev-AF-hb2f
follows: [AF-iv8x]
closed_at: 2026-08-19T15:09:39Z
close_reason: "Accepted: all 9 ACs independently re-verified against delivered files (helm template renders for sonarr+prowlarr well-formed with zero unresolved placeholders, normalized diff identical proving pure scalar substitution; skip-file-rendering marker present on all 5 chart files; sync-wave -1 present; Warehouse Digest/release strategy and the .Digest-over-.Tag determination spot-checked against akuity/kargo source (digest_selector.go mutableTag, repository_client.go img.Tag=tag, git_commiter.go hasDiffs guard) -- all match; appset-kargo renders 6 elements, destination.name kargo, project arr-stack; no Plex/qBittorrent/rflood/SABnzbd refs; bootstrap/*.yaml untouched (git diff stat empty); no repo-wide name collisions against akkoma/soju and their generated children incl. fleet-kargo-apps' apps/*/kargo glob which arr-stack does not match). pvg gates PASS, pvg verify PASSED. Diff budget 7 files added/0 modified exactly as budgeted; 260 total/181 substantive LOC vs 120-180 estimate is explained entirely by rationale comments the story's own Context section requested -- accepted as judgment call, not scope creep. stages.yaml 3-Stage-per-file shape confirmed as explicitly specified by the story's own IMPLEMENTATION section (not a helm-chart-developer skill violation). git-commit message arr-stack/ prefix fix confirmed present in tasks.yaml and in rendered output. DISCOVERED_BUG on tag-vs-digest downstream wiring confirmed already triaged and resolved in AF-8r8l's own story body -- not re-filed."
---

## Description
Description:
Stand up the Kargo-pipeline-generation half of the arr-stack PoC end to end: a new `arr-stack` AppProject, a vendored Helm chart that renders a Project/Warehouse/3xStage/Tasks set per app, and the list-generator ApplicationSet that renders that chart once per app -> 6 independent Kargo pipelines from one shared template. This is the epic's walking skeleton: it is the first slice that proves the whole generation mechanism end to end (bootstrap directory discovery -> AppProject -> ApplicationSet(list) -> per-app Application -> Helm chart render -> Project/Warehouse/Stage), for all 6 apps, statically verifiable without a live cluster.

Context:
`apps/arr-stack/` is a brand-new directory under `apps/`, discovered automatically by the existing `bootstrap/fleet-argocd-apps.yaml` (git `directories` generator over `apps/*/argocd`, wrapper Application `argocd-arr-stack`, `destination.name: in-cluster`, source type `directory` with `recurse: true`). No `bootstrap/*.yaml` file is ever edited by this story or any other story in this epic -- `AGENTS.md` is explicit that adding app-specific config there should never be needed, and this design's entire premise depends on it.

**Load-bearing architecture finding, confirmed against Argo CD source, not guessed -- read before writing any file in `kargo-chart/`:** `fleet-argocd-apps.yaml`'s wrapper Application uses a `directory`-type source with `recurse: true`. Per `~/src/github.com/argoproj/argo-cd/reposerver/repository/repository.go` (`getPotentiallyValidManifests`, `filepath.Walk` with `recurse=true`, ~line 2221), this walks EVERY subdirectory under `apps/arr-stack/argocd/` with no Helm-chart-boundary awareness, and attempts to parse every `*.yaml`/`*.yml`/`*.json` file it finds as a literal Kubernetes manifest. A raw (unrendered) Helm chart template value like `name: {{ .Values.appName }}` is NOT valid standalone YAML -- a plain scalar cannot start with `{` (the flow-mapping-start indicator) -- so if `kargo-chart/` is left unprotected, `argocd-arr-stack`'s manifest generation breaks for the WHOLE wrapper Application (both the workloads and Kargo halves of this design), not just the chart. Argo CD ships a documented per-file escape hatch for exactly this: any file whose raw bytes contain the literal string `+argocd:skip-file-rendering` is skipped entirely by directory-type manifest generation, regardless of extension or glob (confirmed constant `skipFileRenderingMarker = "+argocd:skip-file-rendering"`, `repository.go:84`). Every file under `apps/arr-stack/argocd/kargo-chart/` (including `Chart.yaml`) MUST include `# +argocd:skip-file-rendering` as a YAML comment -- harmless to real Helm rendering (Helm ignores `#` comments), and it is the only in-scope fix (adding a `directory.exclude` to `bootstrap/fleet-argocd-apps.yaml` itself would violate the epic's no-bootstrap-edit rule). This mirrors the same underlying class of problem this repo's own vault knowledge already documents for `bootstrap/infra-apps.yaml` and non-raw-manifest content living under a wholesale-synced `*/argocd` tree (`.vault/knowledge/patterns/Infra appset directory boundary for bootstrap wholesale sync.md`) -- same root cause (a directory-type source with no awareness of "this subtree means something different"), different concrete fix (a skip marker here, since the offending content is a legitimately-rendered-elsewhere Helm chart, not a plain-data file that needs a sibling directory).

The task chain (`git-clone -> yaml-update -> git-commit -> git-push -> argocd-update`) and the `sync-wave: "-1"` annotation on `project.yaml` are this repo's existing, already-working convention -- `apps/akkoma/kargo/{project,stages,tasks}.yaml` is the reference implementation to copy the SHAPE of (not the values); do not invent a new task chain shape.

**Warehouse image subscription -- confirmed strategy, one detail to verify against the skill/CRD reference before finalizing:** hotio images (all six apps' image source) publish under a mutable channel tag (`release`) rather than semver-versioned tags -- this is why the `env/<app>/<stage>/release.yaml` contract's seed value is literally `imageTag: release`, not a version string. Kargo's `ImageSubscription.ImageSelectionStrategy: Digest` with `Constraint: <mutable tag name>` is built exactly for this case -- confirmed by reading `~/src/github.com/akuity/kargo/pkg/image/digest_selector.go`: the `Digest` strategy's selector stores `Constraint` as `mutableTag` and matches on that exact tag, tracking digest changes underneath it rather than tag changes. Use `imageSelectionStrategy: Digest` / `constraint: release` on each app's `Warehouse`. One thing this story must still confirm via the mandatory skill (`devops-toolkit:akp-platform`, its Kargo promotion-patterns reference material) and the Kargo CRD reference (https://doc.crds.dev/github.com/akuity/kargo) before finalizing `kargo-chart/templates/tasks.yaml`: whether the promotion task's `imageFrom(vars.image)` expression should write `.Tag` or `.Digest` into `release.yaml`'s `imageTag` field for a `Digest`-strategy subscription -- do not guess between the two without checking the actual `DiscoveredImageReference`/Freight image field names Kargo exposes to promotion-step expressions.

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

## Acceptance Criteria


## Design


## Notes


## nd_contract
status: delivered

### evidence
- Transitioned via pvg story deliver on 2026-08-19.

### proof
- [ ] Developer evidence block must remain authoritative above this contract.


## History
- 2026-08-18T19:11:43Z dep_added: blocks AF-8r8l
- 2026-08-18T19:11:43Z dep_added: blocks AF-vm0q
- 2026-08-18T19:36:16Z status: open -> in_progress
- 2026-08-18T19:36:16Z claimed by dev-AF-hb2f
- 2026-08-19T14:52:36Z status: in_progress -> in_progress
- 2026-08-19T14:52:36Z auto-follows: linked to predecessor AF-iv8x
- 2026-08-19T15:09:39Z status: in_progress -> closed
- 2026-08-19T15:09:39Z dep_removed: no_longer_blocks AF-8r8l
- 2026-08-19T15:09:39Z dep_removed: no_longer_blocks AF-vm0q

## Links
- Parent: [[AF-j5rz]]
- Follows: [[AF-iv8x]]

## Comments

### 2026-08-19T14:52:30Z ada
DELIVERY -- AF-hb2f (deliver-only follow-up; prior session interrupted by an infra spend limit, not a defect in its work)

Branch: story/AF-hb2f
Producing SHA: caff89be83ff64e61add1d6f57c69143496bb3bd
Base: epic/AF-j5rz
Commits: fdc912e (prior session, 7 files) + caff89b (this session, 1 alignment fix)

Every AC below was re-verified independently against what is on disk. The prior
session's `helm template` note was NOT trusted -- both renders were re-run here.

## PROOF

### Commands run (all synchronous, all from the story worktree)

    helm template apps/arr-stack/argocd/kargo-chart --set appName=sonarr   --set image=ghcr.io/hotio/sonarr
    helm template apps/arr-stack/argocd/kargo-chart --set appName=prowlarr --set image=ghcr.io/hotio/prowlarr
    grep -rL '+argocd:skip-file-rendering' apps/arr-stack/argocd/kargo-chart/
    ruby -ryaml -e "YAML.load_stream(...)"   # appproject.yaml, appset-kargo.yaml, both renders
    diff apps/akkoma/argocd/appproject.yaml apps/arr-stack/argocd/appproject.yaml
    git diff epic/AF-j5rz --stat [-- bootstrap/]
    pvg verify --format text <7 changed files>
    helm version --short  ->  v4.2.4+g3900f43

No test suite exists for this manifest-only repo (story's TESTING section says so
explicitly). Verification is static/render-level. Counts below are check-level.

### Check results: 22 checks run, 22 passed, 0 failed, 0 skipped

| AC | Verdict | Evidence |
|----|---------|----------|
| 1. AppProject `arr-stack`, akkoma's permissive shape | PASS | `diff` vs `apps/akkoma/argocd/appproject.yaml` returns exactly 2 hunks: `name` and `description`. `sourceRepos: ['*']`, `destinations: [server/name/namespace '*']`, `clusterResourceWhitelist: [group/kind '*']` byte-identical. |
| 2. `+argocd:skip-file-rendering` on every kargo-chart file | PASS | `grep -rL` over all 5 files (Chart.yaml, project/stages/tasks/warehouse.yaml) returns EMPTY. Marker is line 1 of every file. |
| 3. Renders well-formed set for two apps, zero unresolved placeholders | PASS | Both renders emit exactly `Project, PromotionTask, Stage(dev), Stage(staging), Stage(prod), Warehouse` = 6 docs. `grep -E '\{\{[^$]'` excluding `${{` returns NONE. Render-diff: `diff <(sed s/sonarr/APP/g) <(sed s/prowlarr/APP/g)` -> IDENTICAL, proving pure scalar substitution with no per-app drift. All names/namespaces DNS-1123 valid. |
| 4. `sync-wave: "-1"` on project.yaml | PASS | project.yaml:10 `argocd.argoproj.io/sync-wave: "-1"` (quoted, so it stays a string). |
| 5. Warehouse `Digest`/`release` + Tag-vs-Digest determination | PASS | warehouse.yaml:23-24. Determination below -- source-verified, not guessed. |
| 6. appset renders exactly 6 Applications, `destination.name: kargo`, `project: arr-stack` | PASS | List generator has 6 elements -> `kargo-arr-{sonarr,radarr,lidarr,bazarr,prowlarr,overseerr}`. `template.spec.project=arr-stack`, `destination={"name"=>"kargo"}`, `source.path=apps/arr-stack/argocd/kargo-chart`, `valuesObject={appName,image}`. |
| 7. No Plex/qBittorrent/rflood/SABnzbd under apps/arr-stack/ | PASS | `grep -rniE 'plex\|qbittorrent\|rflood\|sabnzbd'` -> no matches. |
| 8. `bootstrap/*.yaml` unmodified | PASS | `git diff epic/AF-j5rz --stat -- bootstrap/` -> empty. `--name-status` shows all 7 paths as `A` (added), 0 `M`. |
| 9. No repo-wide name collision | PASS | Enumerated every Application/AppProject/ApplicationSet/Kargo-Project name outside arr-stack: AppProject{akkoma,soju}, Project{akkoma,soju}, Application{fleet-platform-aoa}, ApplicationSet{akkoma,soju,argo-rollouts-crds,fleet-argocd-apps,fleet-kargo-apps,gateway-api-crds,infra-apps,kube-prometheus-stack,openebs-localpv,sealed-secrets,traefik-gateway}. Zero overlap with `arr-stack`, `kargo-arr-*`, or the six app names. Generated children also clear: `fleet-argocd-apps` mints `argocd-{{path[1]}}` -> new `argocd-arr-stack` (unique); `fleet-kargo-apps` mints `kargo-{{path[1]}}` from `apps/*/kargo` and there is no `apps/arr-stack/kargo/` dir, so it generates nothing for arr-stack and cannot collide with our `kargo-arr-<app>`. |

### AC5 detail -- the `.Tag` vs `.Digest` determination (the story's explicit do-not-guess item)

Committed value is `${{ imageFrom(vars.image).Digest }}`. This DEVIATES from the
story's draft IMPLEMENTATION snippet (which wrote `.Tag`), and the deviation is
CORRECT. The story mandated verification over the draft; here is the chain.

Field names exist and are real -- `imageFrom(repoURL)` returns `kargoapi.Image`:
  pkg/expressions/function/functions.go  ImageFromFreight -> `new(func(repoURL string) kargoapi.Image)`
  api/v1alpha1/stage_types.go:681        type Image struct { RepoURL, Tag, Digest, Annotations, SubscriptionName }
Corroborated by the mandatory `devops-toolkit:akp-platform` skill
(references/kargo-promotion-patterns.md): "imageFrom(repoURL) -> Image{Tag, Digest, ...}".

Why `.Tag` is unusable under a Digest-strategy subscription:
  pkg/image/digest_selector.go     newDigestSelector: `mutableTag: sub.Constraint`
                                   MatchesTag: `return d.mutableTag == tag`
                                   Select: `getImageByTag(ctx, d.mutableTag, ...)`
  pkg/image/repository_client.go:205  `img.Tag = tag`
  => `.Tag` is invariantly the literal string "release" for every Freight this
     Warehouse can ever produce, because the only tag it ever looks at is the
     constraint.

Why that is not merely cosmetic:
  pkg/promotion/runner/builtin/git_commiter.go:85  `hasDiffs, err := workTree.HasDiffs(ctx)`
                                                  then `if hasDiffs { ... Commit ... }`
  => writing "release" over "release" produces no diff, so git-commit silently
     skips, git-push pushes nothing, and the Promotion reports SUCCESS having
     deployed nothing. A pipeline that always passes and never ships.

Why `.Digest` is the right field:
  pkg/image/repository_client.go:295,322  digest = `desc.Digest.String()` -> "sha256:<64 hex>"
  => the only field that moves when hotio republishes the mutable `release` tag,
     which is precisely the change this pipeline exists to promote.

AC5's mandated `imageSelectionStrategy: Digest` / `constraint: release` and the
`.Digest` choice are logically coupled: under that strategy `.Tag` cannot vary,
so `.Digest` is the only field carrying promotion signal.

### Fix committed this session (caff89b)

1. Restored the `arr-stack/` prefix on the git-commit message. The prior session
   had `"{{ .Values.appName }}/{{ $stage }}: ..."`; the story's IMPLEMENTATION
   specifies `"arr-stack/{{ .Values.appName }}/${{ ctx.stage }}: ..."`. Renders as
   `arr-stack/sonarr/${{ ctx.stage }}: promote image ${{ imageFrom(vars.image).Digest }}`.
2. Documented the downstream digest contract in tasks.yaml (see DISCOVERED_BUG).

### Also verified beyond the ACs

- The two-templating-layer escape in tasks.yaml is NECESSARY, not defensive.
  Reproduced the failure it prevents with a scratch chart containing an inlined
  `${{ ctx.stage }}`: `Error: parse error at (naive/templates/t.yaml:1): function
  "ctx" not defined`. Binding each Kargo expression to a Helm string variable
  (`{{- $stage := "${{ ctx.stage }}" }}`) is what lets Kargo syntax survive Helm
  rendering verbatim -- confirmed in the render output, where all five
  `${{ ... }}` expressions emerge intact.
- Rendered promotion step chain matches this repo's existing convention
  (git-clone -> yaml-update -> git-commit -> git-push -> argocd-update), same
  shape as apps/akkoma/kargo/tasks.yaml. No new task shape invented.
- YAML hygiene, all 7 files: 0 tabs, 0 trailing whitespace, final newline
  present, 0 odd-indent lines.
- `pvg verify --format text` on all 7 changed files: PASSED, 0 issues.
- Diff budget: 7 files added, 0 modified. 260 total lines / **181 substantive**
  (non-comment, non-blank) vs the story's 120-180 estimate -- substantive content
  lands at the top of budget; the remaining 79 lines are the rationale comments
  the story's own Context section asked for (skip-marker justification, digest
  strategy, two-layer templating trap).

### Deviations from the story's draft YAML, with reasons

- `tasks.yaml` writes `.Digest`, not the draft's `.Tag` -- story-sanctioned
  verification outcome, chain above.
- `stages.yaml` keeps 3 documents in one file. The `helm-chart-developer` skill
  prefers one resource per file, but the story explicitly specifies this shape to
  mirror `apps/akkoma/kargo/stages.yaml`. Story wins; flagging the tension.
- Files carry explanatory comment headers beyond the draft's bare YAML. Drives
  total LOC to 260; substantive LOC is 181.

## LEARNINGS

- A story that says "verify X, do not guess" can have a WRONG value in its own
  draft YAML. Here the draft said `.Tag` and the verified answer was `.Digest`.
  Treat draft snippets as intent, ACs as contract, and the cited source as truth.
- "Which field name exists" was the easy half; "which field carries signal" was
  the load-bearing half. Both `.Tag` and `.Digest` exist, so a field-name check
  alone would have ratified the broken option. The decisive evidence was
  git_commiter.go's `hasDiffs` guard -- proving the failure mode is a silent
  green promotion, the worst kind. Verify the consequence, not just the spelling.
- Reading the CONSUMER settles arguments the producer cannot. Pulling
  app-template and reading `_imageSpecificationToImage.tpl` turned "a digest in a
  tag field feels wrong" into a precise mechanism: `printf "%s:%s"` for tag vs
  `printf "%s@%s"` for digest. That single file both confirmed the hazard and
  named the exact fix for Story 4.
- Two templating engines sharing `{{` is a real trap, and the fix is
  counter-intuitive: bind the foreign expression to a Helm string variable,
  because Helm does not scan string-literal contents for actions. Worth
  reproducing the failure once (I did) so the workaround is not cargo-culted.
- Verifying an interrupted session's work cost far less than redoing it, but only
  because I re-ran the renders instead of trusting the handoff note. The one real
  gap I found (the dropped `arr-stack/` prefix) was in a spot the prior agent's
  own progress note did not claim to have checked.
- Deliver-only follow-ups should still re-check the diff budget. Substantive LOC
  was within estimate but total was 44% over, purely from comments -- worth
  stating explicitly so a reviewer is not surprised by the `--stat`.

## DISCOVERED_BUG

DISCOVERED_BUG:
  title: arr-stack release.yaml `imageTag` carries a digest, but the design spec wires it into app-template's `tag` field, producing an unparseable image reference
  context: |
    AF-hb2f's PromotionTask correctly writes ${{ imageFrom(vars.image).Digest }}
    (i.e. "sha256:<hex>") into apps/arr-stack/env/<app>/<stage>/release.yaml's
    `imageTag` key -- correct, because the Warehouse uses
    imageSelectionStrategy: Digest against the mutable `release` tag, so .Tag is
    invariantly "release" and .Digest is the only field that changes.

    The consuming side does not match. The design spec
    (docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md, lines 203-205,
    on main at cb8bf2e) has appset-workloads.yaml bind it as:
        image:
          repository: {{.image}}
          tag: "{{.values.imageTag}}"

    bjw-s app-template builds the reference in
    charts/common/templates/lib/common/_imageSpecificationToImage.tpl:
        {{- if $imageTag -}}    {{- $image = printf "%s:%s" $image $imageTag -}}
        {{- if $imageDigest -}} {{- $image = printf "%s@%s" $image $imageDigest -}}

    So `tag: sha256:abc...` renders `ghcr.io/hotio/sonarr:sha256:abc...`. An OCI
    tag cannot contain a colon, so that reference is unparseable and every arr
    workload pod would fail to pull. app-template already exposes a separate
    `digest` field that emits the correct `repository@sha256:...` form.

    Three coupled fixes, all outside AF-hb2f's scope:
      1. Story 4 (appset-workloads.yaml) must bind the value to app-template's
         `digest` field, not `tag`.
      2. Story 2's release.yaml seed `imageTag: release` is a TAG-shaped seed for
         a key that now holds digests. Either rename the key to `imageDigest`
         (clearer, and forces Story 4 to bind correctly) or seed it with a real
         digest. A `release` literal in a digest field renders
         `repository@release`, also unparseable.
      3. The design spec's own snippet should be corrected so Story 4 does not
         faithfully implement the broken wiring.

    Recommend renaming the contract key to `imageDigest` across Stories 2/4 and
    this task's yaml-update step, since `imageTag` now actively misdescribes its
    contents. AF-hb2f leaves the key as `imageTag` because that name is fixed by
    the story's ACs and the contract is Story 2's to define.

    Not blocking AF-hb2f: nothing here is live (no cluster touch until Story 7,
    human-gated), release.yaml files do not exist yet, and this story's own ACs
    all pass. Documented in tasks.yaml at the point the digest is produced.
  affected_files: |
    docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md (lines 203-205, on main at cb8bf2e)
    apps/arr-stack/env/<app>/<stage>/release.yaml (Story 2, not yet created)
    apps/arr-stack/argocd/appset-workloads.yaml (Story 4, not yet created)
    apps/arr-stack/argocd/kargo-chart/templates/tasks.yaml (produces the value; contract documented here)
  discovered_during: AF-hb2f
