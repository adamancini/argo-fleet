---
id: AF-yse2
title: "Bug: ghcr.io/hotio/overseerr retired -- rename merged appset-kargo.yaml/appproject.yaml entries to seerr"
status: closed
priority: 0
type: bug
parent: AF-j5rz
created_at: 2026-08-19T15:40:11Z
created_by: ada
updated_at: 2026-08-19T16:04:19Z
content_hash: "sha256:62110ef869a4dc3f8e28498464225188d465f086ef37ccc119333bd5ab2a9dd3"
assignee: dev-AF-yse2
follows: [AF-hb2f, AF-iv8x]
labels: [accepted]
closed_at: 2026-08-19T16:03:25Z
close_reason: "Accepted: overseerr->seerr rename verified independently. appset-kargo.yaml element and appproject.yaml description match exactly. helm template renders clean app-scoped Project/Warehouse/3xStage/PromotionTask with Digest/release strategy intact and zero unresolved placeholders. Repo-wide grep for overseerr is clean. Diff vs epic/AF-j5rz base (c9d8095) is exactly 2 files modified, 0 added/deleted. bootstrap/ untouched. Other 5 list elements byte-identical."
led_to: [AF-6jta, AF-vm0q]
---

## Description
Description:
`apps/arr-stack/argocd/appset-kargo.yaml` and `apps/arr-stack/argocd/appproject.yaml` (both merged to `epic/AF-j5rz` via AF-hb2f, already accepted/closed) reference `overseerr`/`ghcr.io/hotio/overseerr`. hotio retired that image; the Warehouse subscription can never resolve, permanently deadlocking the overseerr Kargo trio. Rename the app to `seerr`/`ghcr.io/hotio/seerr` in both already-merged files. AF-hb2f itself is NOT reopened -- this is a follow-up patch, not a defect in AF-hb2f's own delivered scope (the image simply didn't exist at review time in the sense that mattered; it existed as a pullable tag but was already deprecated upstream in favor of `hotio/seerr`).

DISCOVERED DURING:
AF-8r8l's developer, while resolving each app's current digest to seed `release.yaml` files (see EVIDENCE below). Surfaced to Sr PM bug triage because AF-8r8l's developer released its claim rather than guess/fake a digest for a dead image.

SYMPTOMS:
- Any Kargo `Warehouse` subscribing to `ghcr.io/hotio/overseerr` with `imageSelectionStrategy: Digest` / `constraint: release` can never mint Freight -- the repository does not exist, so there is no tag list and no digest to discover.
- The `overseerr` Kargo trio (Project/Warehouse/3xStage) rendered by `appset-kargo.yaml`'s list-generator element is permanently dead the moment it reaches a live Argo CD/Kargo control plane (AF-o0rw/AF-c17x/AF-4wkn), independent of anything AF-8r8l or AF-6jta do.

EVIDENCE:
- ghcr.io anonymous-pull token endpoint for scope `repository:hotio/overseerr:pull` returned `{"errors":[{"code":"DENIED","message":"requested access to the resource is denied"}]}` on 3 consecutive attempts. `DENIED` means the repo is absent/private: no manifest, no tag list, therefore no digest exists to seed or to promote.
- Control probe (identical method) returned a valid anonymous pull token for `hotio/{sonarr,radarr,lidarr,bazarr,prowlarr,plex,qbittorrent,requestrr}` -- method is sound, `overseerr` specifically is gone. `hotio/jellyseerr` and `hotio/readarr` are likewise absent (not affected apps in this epic, noted for completeness).
- Root cause, hotio's own docs at https://hotio.dev/containers/overseerr/ (HTTP 200): "Warning -- Please migrate from hotio/overseerr to hotio/seerr. Seerr v3 has been released, so this should be safe to do."
- Successor verified live: `ghcr.io/hotio/seerr:release` resolves to `sha256:6ce42c9cdf64802f93639119009c1f24390bf17497775655698acd970e9920f7`.
- Currently committed (epic/AF-j5rz, `apps/arr-stack/argocd/appset-kargo.yaml`):
  ```yaml
        - name: overseerr
          image: ghcr.io/hotio/overseerr
  ```
- Currently committed (epic/AF-j5rz, `apps/arr-stack/argocd/appproject.yaml`):
  ```yaml
    description: DRY *arr family workloads + generated Kargo pipelines (PoC) -- Sonarr, Radarr, Lidarr, Bazarr, Prowlarr, Overseerr
  ```

POSSIBLE CAUSES:
1. hotio deprecated/deleted the `hotio/overseerr` image in favour of `hotio/seerr` (Seerr v3) -- confirmed root cause, not a hypothesis; see EVIDENCE.

CONFIG (if relevant):
Not applicable -- no live cluster config involved; this is a static manifest edit against already-merged files.

KEY FILES:
Modify: `apps/arr-stack/argocd/appset-kargo.yaml` (list-generator element), `apps/arr-stack/argocd/appproject.yaml` (`spec.description`). No other file is touched -- the vendored `kargo-chart/` is already fully parameterized and needs no change of its own.

PRODUCES:
- `apps/arr-stack/argocd/appset-kargo.yaml` -> corrected list-generator element
    spec: `{name: seerr, image: ghcr.io/hotio/seerr}` replaces `{name: overseerr, image: ghcr.io/hotio/overseerr}`; the other 5 elements (sonarr/radarr/lidarr/bazarr/prowlarr) are unchanged
    source: this bug's own AC #1
- `apps/arr-stack/argocd/appproject.yaml` -> corrected `spec.description`
    spec: description string ends `...Prowlarr, Seerr` instead of `...Prowlarr, Overseerr`
    source: this bug's own AC #2

Acceptance Criteria:
1. `apps/arr-stack/argocd/appset-kargo.yaml`'s list-generator element renamed from `{name: overseerr, image: ghcr.io/hotio/overseerr}` to `{name: seerr, image: ghcr.io/hotio/seerr}` -- no other element in the list is touched.
2. `apps/arr-stack/argocd/appproject.yaml`'s `spec.description` string updated to read `...Prowlarr, Seerr` instead of `...Prowlarr, Overseerr`.
3. `helm template apps/arr-stack/argocd/kargo-chart --set appName=seerr --set image=ghcr.io/hotio/seerr` renders a well-formed, app-name-scoped Project/Warehouse/3xStage/PromotionTask set with zero unresolved placeholders (same render-diff check AF-hb2f itself used) -- the vendored chart is already parameterized and requires no changes of its own.
4. Repo-wide `grep -rniw overseerr` under `apps/arr-stack/` returns no matches after the fix (case-insensitive, whole-word).
5. [Unwanted] `bootstrap/*.yaml` is not modified by this fix.
6. [Unwanted] No other list element (`sonarr`, `radarr`, `lidarr`, `bazarr`, `prowlarr`) is altered.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory -- ApplicationSet list-generator conventions, Kargo Warehouse/Digest-strategy semantics), devops-toolkit:yaml-kubernetes-validator

## Acceptance Criteria


## Design


## Notes


## nd_contract
status: accepted

### evidence
- PM closeout applied via pvg story accept on 2026-08-19.

### proof
- [x] Story closed after accepted label was applied.


## nd_contract
status: delivered

### evidence
- Transitioned via pvg story deliver on 2026-08-19.

### proof
- [ ] Developer evidence block must remain authoritative above this contract.


## History
- 2026-08-19T15:40:15Z dep_added: blocks AF-6jta
- 2026-08-19T15:45:38Z dep_added: blocks AF-vm0q
- 2026-08-19T15:47:37Z status: open -> in_progress
- 2026-08-19T15:47:37Z auto-follows: linked to predecessor AF-hb2f
- 2026-08-19T15:47:37Z claimed by dev-AF-yse2
- 2026-08-19T15:57:14Z status: in_progress -> in_progress
- 2026-08-19T15:57:15Z auto-follows: linked to predecessor AF-iv8x
- 2026-08-19T16:03:25Z status: in_progress -> closed
- 2026-08-19T16:03:25Z dep_removed: no_longer_blocks AF-6jta
- 2026-08-19T16:03:25Z dep_removed: no_longer_blocks AF-vm0q

## Links
- Parent: [[AF-j5rz]]
- Follows: [[AF-hb2f]], [[AF-iv8x]]
- Led to: [[AF-6jta]], [[AF-vm0q]]

## Comments

### 2026-08-19T15:57:06Z ada
DELIVERED: AF-yse2 -- overseerr -> seerr rename in the two already-merged arr-stack files.

Commit: a497fbaaf7cbc2b6a965f567e2737287b8db52ba (branch `story/AF-yse2`, pushed to origin, fast-forward over `origin/epic/AF-j5rz` @ c9d8095)
Base: epic/AF-j5rz @ c9d809590521a0166e58561944ad2fd6eaf45923 (local == origin, no rebase needed)

## PROOF

All results below produced from commit a497fba with a clean worktree (`git status -uno` empty).

### Commands run

| # | Command | Result |
|---|---------|--------|
| 1 | `helm template apps/arr-stack/argocd/kargo-chart --set appName=seerr --set image=ghcr.io/hotio/seerr` | exit 0, empty stderr, 6693 bytes, 6 documents |
| 2 | `ruby verify_ac3.rb render-seerr.yaml` (structural assertions over that render) | **45 passed / 0 failed**, exit 0 |
| 3 | `ruby` YAML assertions over both edited files | **14 passed / 0 failed**, exit 0 |
| 4 | `helm template` loop over all 6 appset elements | **6/6 PASS** (each: exit 0, 6 kinds, 5 namespaced resources scoped to its own app name) |
| 5 | `ruby e2e/observability_test.rb` (existing repo suite, regression) | **150 passed / 0 failed**, exit 0 |
| 6 | `pvg verify <2 changed files> --format text` | PASSED (0 files scanned -- see note) |
| 7 | `pvg verify . --check-e2e` | PASSED (1 e2e file found) |
| 8 | `grep -rniw overseerr apps/arr-stack/` | exit 1, **0 matches** |
| 9 | `git diff epic/AF-j5rz --name-status` | exactly `M` x2, 0 added, 0 deleted |

Totals: **215 assertions passed, 0 failed, 0 skipped.** Zero errors and zero warnings in all output.

Note on #6: `pvg verify` reports "0 files scanned" because `.yaml` is not one of its recognized
source extensions -- it is structurally incapable of scanning a manifest-only change. It is
recorded for completeness, not as the substantive check. The real verification of this change is
#1-#4 (helm render + parsed-YAML assertions). No stub/thin-file/TODO markers were introduced;
the diff adds only YAML data plus explanatory comments.

Coverage: not a meaningful metric for this change -- there is no executable code in this repo
(GitOps manifests only; see e2e/observability_test.rb's own "WHY STATIC-ONLY" rationale).
The equivalent measure is manifest coverage: **6/6 list elements render-verified**, and
**100% of the changed lines** are covered by assertions in #2/#3.

### Acceptance criteria

| AC | Status | Evidence |
|----|--------|----------|
| 1. appset-kargo.yaml element renamed `overseerr`->`seerr`, image `ghcr.io/hotio/seerr`, no other element touched | PASS | Committed lines 30-31: `- name: seerr` / `image: ghcr.io/hotio/seerr`. Parsed elements are exactly `[sonarr, radarr, lidarr, bazarr, prowlarr, seerr]`, each with exactly keys `{name,image}` and `image == ghcr.io/hotio/<name>`. Diff hunk touches only the removed element's 2 lines (+4 comment lines); the other 5 elements do not appear in the diff at all, and their `grep`-extracted lines are byte-identical to `epic/AF-j5rz` (line numbers included). |
| 2. appproject.yaml `spec.description` ends `...Prowlarr, Seerr` | PASS | Committed line 7: `description: DRY *arr family workloads + generated Kargo pipelines (PoC) -- Sonarr, Radarr, Lidarr, Bazarr, Prowlarr, Seerr`. Asserted via `end_with?("Prowlarr, Seerr")` plus "names all 6 apps". |
| 3. `helm template ... --set appName=seerr --set image=ghcr.io/hotio/seerr` renders a well-formed, app-name-scoped Project/Warehouse/3xStage/PromotionTask with zero unresolved placeholders | PASS | 45/45 assertions. Resource set is exactly `{Project:1, Warehouse:1, Stage:3, PromotionTask:1}` (6 docs, all `kargo.akuity.io/v1alpha1`). Scoping: Project name `seerr`; all 5 namespaced resources in namespace `seerr`; Warehouse name `seerr` subscribing `repoURL: ghcr.io/hotio/seerr` with `imageSelectionStrategy: Digest` / `constraint: release`; all 3 Stages request Freight from `Warehouse/seerr`; dev<-direct, staging<-dev, prod<-staging; PromotionTask `vars.image == ghcr.io/hotio/seerr`, chain `git-clone -> yaml-update -> git-commit -> git-push -> argocd-update`, yaml-update path `./src/apps/arr-stack/env/seerr/${{ ctx.stage }}/release.yaml`, argocd-update target `arr-seerr-${{ ctx.stage }}`. Placeholders: no `{{ }}` remaining once legitimate Kargo `${{ }}` expressions are stripped; no `.Values`, `<no value>`, `RELEASE-NAME`, or `appName` leaked; and positively, all 3 Kargo expressions survived Helm rendering verbatim at their expected occurrence counts (3x `ctx.stage`, 1x `vars.repoURL`, 2x `imageFrom(vars.image).Digest`) -- guarding against an over-eager fix that escapes them and silently breaks promotion. Chart itself unchanged, as the story predicted. |
| 4. `grep -rniw overseerr` under `apps/arr-stack/` returns no matches | PASS | Working tree: exit 1, 0 matches. Committed tree (`git grep -niw overseerr HEAD -- apps/arr-stack/`): 0 matches across all 7 tracked files. Also 0 matches repo-wide (excluding .git/.vault/.claude). The rendered helm output likewise contains no whole-word occurrence. |
| 5. [Unwanted] `bootstrap/*.yaml` not modified | PASS | `git diff --quiet epic/AF-j5rz -- bootstrap/` exits 0; `--name-only -- bootstrap/` returns 0 lines. |
| 6. [Unwanted] No other list element altered | PASS | Diffstat vs epic: exactly 2 files, both `M`, 0 added, 0 deleted, 7 insertions / 3 deletions. All 6 apps still render cleanly and app-scoped (#4 above), so the unchanged 5 are proven working, not merely untouched. |

### Wiring

No new component -- this re-points an existing, already-wired one. The wiring site is the
`list` generator in `apps/arr-stack/argocd/appset-kargo.yaml`, which `bootstrap/fleet-argocd-apps.yaml`
discovers by syncing `apps/*/argocd` as a recursive `directory` source. The renamed element is
what mounts the pipeline: it drives the `kargo-arr-seerr` Application, whose Helm `valuesObject`
binds `appName`/`image` into the vendored chart. Exercised through that wiring by rendering the
chart with exactly the values the appset supplies (`appName=seerr`, `image=ghcr.io/hotio/seerr`),
and by confirming `appset-kargo.yaml` still parses as a valid standalone manifest -- required
because the bootstrap directory sync parses each file literally, with no Helm-chart awareness.

### Root cause independently re-confirmed (not taken on faith from the story)

- `GET https://ghcr.io/token?scope=repository:hotio/overseerr:pull` ->
  `{"errors":[{"code":"DENIED","message":"requested access to the resource is denied"}]}`
  (no tag list, no manifest, so a Digest-strategy Warehouse can never mint Freight).
- `GET https://ghcr.io/token?scope=repository:hotio/seerr:pull` -> token issued;
  `HEAD /v2/hotio/seerr/manifests/release` ->
  `docker-content-digest: sha256:6ce42c9cdf64802f93639119009c1f24390bf17497775655698acd970e9920f7`
  -- byte-identical to the digest recorded in the story's EVIDENCE.

## LEARNINGS

- A "fix the stale name" story can be self-defeating: the explanatory comment I first added to
  `appset-kargo.yaml` named the retired image, which broke AC4's `grep -rniw` on my own change.
  Reworded to describe the retirement without spelling the dead name. Worth remembering whenever
  an AC is a repo-wide grep -- comments and commit messages are in scope for the file check even
  though the intent is only about live config.
- Verifying "zero unresolved placeholders" needs a two-sided test on this chart. `tasks.yaml`
  deliberately carries Kargo `${{ ... }}` expressions that MUST survive Helm rendering verbatim,
  so a naive "no braces in output" check fails on correct output. The assertion has to strip
  `${{ ... }}` first, then also positively count that those expressions are still present -- the
  negative check alone would pass an implementation that escaped them and silently broke promotion.
- The `pvg verify` gate is blind to this repo's entire content type: `.yaml` is not a scanned
  extension, so it returns "PASSED (0 files scanned)" for any manifest-only story. Treat it as a
  formality here and carry real evidence from `helm template` plus parsed-YAML assertions.
- Renaming the app renames its promotion target directory too: the PromotionTask now writes
  `apps/arr-stack/env/seerr/<stage>/release.yaml` and nudges `arr-seerr-<stage>`. Downstream
  AF-8r8l (release.yaml seeding) and AF-6jta/AF-vm0q must use `seerr`, not the old name -- the
  digest to seed is `sha256:6ce42c9cdf64802f93639119009c1f24390bf17497775655698acd970e9920f7`.
- Environment friction worth flagging for future stories in this loop: the pvg guard blocks `cd`
  into the worktree even for the developer subagent, so every command must use absolute paths
  (`git -C <worktree>`); Python has no PyYAML on this box, so Ruby stdlib YAML is the only
  dependency-free parser (which is exactly why the existing e2e suite is Ruby); and zsh eats the
  colon in `git show "$SHA:path"` -- use `HEAD:path` or `"${SHA}":path`.

### 2026-08-19T16:04:19Z ada
PM-ACCEPTOR REVIEW: Independently re-verified all 6 required checks. (1) appset-kargo.yaml list element is exactly {name: seerr, image: ghcr.io/hotio/seerr}; diffed against parent commit c9d8095 (epic/AF-j5rz base) and confirmed the other 5 elements (sonarr/radarr/lidarr/bazarr/prowlarr) are byte-identical. (2) appproject.yaml spec.description ends '...Prowlarr, Seerr'. (3) Re-ran helm template apps/arr-stack/argocd/kargo-chart --set appName=seerr --set image=ghcr.io/hotio/seerr myself: exit 0, 6 well-formed documents (Project/Warehouse/3xStage/PromotionTask), all seerr-scoped, Warehouse imageSelectionStrategy=Digest/constraint=release, zero unresolved {{ }} placeholders, Kargo ${{ }} expressions intact. (4) grep -rniw overseerr apps/arr-stack/ (and repo-wide) returns 0 matches -- confirmed clean, including the developer's flagged near-miss on their own explanatory comment (reworded, does not contain the word). (5) git diff --stat c9d8095 a497fba shows exactly 2 files modified, 0 added, 0 deleted. (6) bootstrap/ diff against c9d8095 is empty. pvg gates --changed c9d8095: PASS (0 warn, 0 skip). pvg verify: vacuous PASS (0 files scanned, .yaml not a scanned extension) as the developer correctly flagged -- not relied upon. No hard-tdd label, no DISCOVERED_BUG, no stale docs (0 overseerr references anywhere in repo). ACCEPTED.
