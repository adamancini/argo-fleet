---
id: AF-8r8l
title: "Seed arr-stack release.yaml promotion-target files for all six apps"
status: open
priority: 1
type: task
parent: AF-j5rz
created_at: 2026-08-18T18:54:12Z
created_by: ada
updated_at: 2026-08-18T18:54:12Z
content_hash: "sha256:a21fbadb267714151b0891cf6d2887d8f388e6eacfc55eb4d229da0716a73857"
---

## Description
Description:
Seed the 18 `apps/arr-stack/env/<app>/<stage>/release.yaml` contract files (6 apps x dev/staging/prod) that both halves of this design need as a precondition: Kargo's per-app promotion task (AF-q5yh's `tasks.yaml`) writes to them, and `appset-workloads.yaml` (Story 4) reads them via its `git files` generator to know what tag to render.

Context:
Per the design spec's `env/<app>/<stage>/release.yaml` contract, this is the one genuinely per-instance piece of state in the whole design -- not template-able, because it's exactly what Kargo's promotion writes back to on every promote. The seed content is intentionally minimal and identical across all 18 files: `imageTag: release` (the mutable hotio channel tag every app's Warehouse subscribes to via `imageSelectionStrategy: Digest`/`constraint: release`, per AF-q5yh -- this is the correct pre-promotion seed value, not a placeholder that needs replacing) and `values: {}` (reserved for future stage-specific overrides; empty is correct for this PoC -- the design spec does not call for any stage-specific values beyond what `appset-workloads.yaml`'s template already hardcodes).

These files must exist as real files in git BEFORE `appset-workloads.yaml`'s `git files` generator (`path: "apps/arr-stack/env/{{.name}}/*/release.yaml"`) can discover anything -- an ApplicationSet git-files generator only picks up paths that exist at the revision it reads, so Story 4 is `blocked_by` this story regardless of the spike's (Story 3) outcome.

USER INTENT:
A developer or reviewer opening any one of these 18 files needs to see, at a glance, exactly what Kargo has most recently promoted for that app/stage -- no ambiguity about whether the file represents "not yet promoted" vs "promoted to X" (both cases render identically here: `imageTag: release`, since promotions to a Digest-strategy subscription track a fixed tag's underlying content, not a changing tag string -- see AF-q5yh's note on `.Tag` vs `.Digest` still needing confirmation for what the promotion task actually writes back).

IMPLEMENTATION:
Create all 18 files with identical content:
```yaml
imageTag: release
values: {}
```
at these paths:
```
apps/arr-stack/env/sonarr/dev/release.yaml
apps/arr-stack/env/sonarr/staging/release.yaml
apps/arr-stack/env/sonarr/prod/release.yaml
apps/arr-stack/env/radarr/dev/release.yaml
apps/arr-stack/env/radarr/staging/release.yaml
apps/arr-stack/env/radarr/prod/release.yaml
apps/arr-stack/env/lidarr/dev/release.yaml
apps/arr-stack/env/lidarr/staging/release.yaml
apps/arr-stack/env/lidarr/prod/release.yaml
apps/arr-stack/env/bazarr/dev/release.yaml
apps/arr-stack/env/bazarr/staging/release.yaml
apps/arr-stack/env/bazarr/prod/release.yaml
apps/arr-stack/env/prowlarr/dev/release.yaml
apps/arr-stack/env/prowlarr/staging/release.yaml
apps/arr-stack/env/prowlarr/prod/release.yaml
apps/arr-stack/env/overseerr/dev/release.yaml
apps/arr-stack/env/overseerr/staging/release.yaml
apps/arr-stack/env/overseerr/prod/release.yaml
```
The app names and count (6 apps x 3 stages = 18) must exactly match the per-app parameter table in both AF-q5yh's `appset-kargo.yaml` and Story 4's `appset-workloads.yaml` -- a mismatch here (a 7th app, a missing stage, a typo'd app name) is exactly the class of drift the static verification story (Story 6) is built to catch, so double-check the list against the epic's per-app parameter table before creating files, not against memory.

KEY FILES:
Create: the 18 `apps/arr-stack/env/<app>/<stage>/release.yaml` files listed above. No existing file is modified.

OUT OF SCOPE:
- Any stage-specific `values:` content -- the design specifies `values: {}` for every file; a future story that needs per-stage overrides is separate work, not guessed at here.
- The Kargo chart that writes to these files (AF-q5yh, already delivered/in-flight as a sibling story) and the workloads ApplicationSet that reads them (Story 4) -- this story only seeds the files themselves.

DIFF BUDGET:
18 new files, 0 modified. ~36 LOC total (2 lines per file).

CONSUMES:
- AF-q5yh: apps/arr-stack/argocd/kargo-chart/templates/tasks.yaml -> PromotionTask `promote`
    spec: yaml-update step targets path ./src/apps/arr-stack/env/{{ .Values.appName }}/${{ ctx.stage }}/release.yaml, key: imageTag
    source: AF-q5yh's own PRODUCES block -- confirms the exact per-app/per-stage path shape this story's 18 files must satisfy

PRODUCES:
- `apps/arr-stack/env/<app>/<stage>/release.yaml` (18 files) -> promotion-target contract file
    schema: imageTag (string, mutable-tag name), values (object, empty at seed)
    source: docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md, `env/<app>/<stage>/release.yaml` contract section, verbatim

TESTING:
No unit-test suite exists for this repo's GitOps manifests -- verification is static only:
- `ruby -ryaml -e "Dir.glob('apps/arr-stack/env/*/*/release.yaml').each { |f| d = YAML.load(File.read(f)); raise \"#{f}: bad shape\" unless d['imageTag'] == 'release' && d['values'] == {} }; puts 'OK'"` -- confirms all 18 files exist, parse, and share the identical seed shape.
- `Dir.glob('apps/arr-stack/env/*/*/release.yaml').length` must equal exactly 18, and the discovered app-name set (glob level 1) must exactly equal `{sonarr,radarr,lidarr,bazarr,prowlarr,overseerr}` and the stage set (glob level 2) must exactly equal `{dev,staging,prod}` for every app -- discover by glob, do not hard-code the count check only.

Acceptance Criteria:
1. [Ubiquitous] Exactly 18 `release.yaml` files exist under `apps/arr-stack/env/`, one per (app, stage) pair for all 6 apps x 3 stages.
2. [Ubiquitous] Every file's content is exactly `imageTag: release` / `values: {}`.
3. [Ubiquitous] The app-name set discovered by glob exactly matches the epic's per-app parameter table (`sonarr`, `radarr`, `lidarr`, `bazarr`, `prowlarr`, `overseerr`) -- no extra, no missing, no typo'd name.
4. [Unwanted] No file shall contain a real/placeholder secret value, a hand-picked non-`release` tag, or any stage-specific override -- every file is byte-identical to every other.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory -- confirms the release.yaml contract shape against `references/kargo-promotion-patterns.md` before seeding)

## Acceptance Criteria


## Design


## Notes


## History


## Links
- Parent: [[AF-j5rz]]

## Comments
