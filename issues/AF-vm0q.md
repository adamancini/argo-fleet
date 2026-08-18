---
id: AF-vm0q
title: "Static verification suite for arr-stack manifests"
status: open
priority: 1
type: task
labels: [capstone]
parent: AF-j5rz
created_at: 2026-08-18T18:57:46Z
created_by: ada
updated_at: 2026-08-18T19:06:10Z
content_hash: "sha256:8707b8331266ae844dc76903605a343dc3902ce54824228531c8caca9dc3b1d6"
blocked_by: [AF-8r8l, AF-iv8x, AF-6jta, AF-pfbv, AF-o0rw, AF-c17x, AF-4wkn]
was_blocked_by: [AF-q5yh]
---

## Description
Description:
Static verification capstone for the whole `arr-stack` manifest set: prove the committed manifests describe a coherent, deployable system end to end -- including every cross-file contract that would otherwise only break at runtime -- without requiring a live cluster on the critical path. This is the epic's capstone: it introduces no new deploy-facing code, it proves everything the other developer-claimable and human-gated stories (AF-q5yh, AF-8r8l, AF-iv8x, AF-6jta, AF-pfbv, AF-o0rw, AF-c17x, AF-4wkn) built actually fits together as one system end to end, catching anything that passed its own story's narrower verification but breaks when everything -- including the live evidence -- is combined.

**Sequencing note (mechanical, not narrative):** this story's `e2e/observability_test.rb` extension is written and run to completion BEFORE the live merge (AF-o0rw) is attempted -- writing and passing the static suite first is the whole point of a two-tier verification design, and AF-o0rw's own Step 0 requires confirming this suite is clean before merging. This story's nd ticket, however, is `blocked_by` every other sibling in the epic (including the human-gated live stories) and therefore CLOSES last: closing it is the final act of the epic, re-confirming that the static suite still passes and every negative assertion still holds after the live merge and promotion, not just before it. Author and run the suite early; close the ticket last.

Context:
This repo already has an established, reusable pattern for exactly this kind of test: `e2e/observability_test.rb` (`.vault/knowledge/patterns/Static-only Ruby e2e testing for a GitOps-manifest-only repo.md`), built for the prior `AF-d66a` epic's completion gate. Two hard constraints drove that choice, both apply identically here:
1. `pvg verify --check-e2e` only scans recognized source-file extensions -- a `.sh` file is invisible to that gate regardless of path or name.
2. This repo has zero test tooling installed and no lockfile/dependency-management convention for one. Ruby ships `YAML` and `JSON` in its standard library on both a stock macOS workstation and a stock CI runner -- zero external dependencies.

Reuse `e2e/observability_test.rb`'s harness (assert helpers, `dig_path`, `doc`/`raw` caching) as the base -- extend it with a new section for `arr-stack`, do not fork it into a second test file. There is no installed skill for this methodology yet (it's a pending vault proposal, not yet promoted) -- every specific check below is spelled out explicitly rather than referenced by skill name.

USER INTENT:
Anyone reviewing this epic's delivery needs one command that either says "the whole arr-stack manifest set is internally coherent" or points at the exact cross-file contract that's broken -- not five separate spot-checks that each pass in isolation while the system as a whole is subtly wrong (a 7th app added to one list and not the other, a `hasDownloads` mismatch between the parameter table and the rendered template, a stray reference to an out-of-scope app).

IMPLEMENTATION:
Add a new section to `e2e/observability_test.rb` (or a clearly-delineated `arr_stack` method group within it) covering:

1. **Structural / lint checks** (accumulate-and-report, not fail-fast -- every assertion runs regardless of earlier failures):
   - Every YAML file under `apps/arr-stack/` parses cleanly (`YAML.load_stream`), including multi-document `stages.yaml`.
   - `yamllint`/`kubeconform` (or the repo's existing static-check convention) against `appproject.yaml`, `appset-workloads.yaml`, `appset-kargo.yaml`, and every `kargo-chart/templates/*.yaml` -- note that the `kargo-chart/templates/*.yaml` files are Helm templates, not raw manifests, so lint them post-`helm template` render, not as raw YAML with unrendered `{{ }}` syntax.

2. **`helm template` render checks:**
   - `helm template apps/arr-stack/argocd/kargo-chart --set appName=sonarr --set image=ghcr.io/hotio/sonarr` and again with `--set appName=prowlarr --set image=ghcr.io/hotio/prowlarr` (one `hasDownloads: true` app, one `false`, matching AF-q5yh's own verification) -- confirm both render a well-formed, app-name-scoped Project/Warehouse/3xStage/PromotionTask set.
   - Manually render `appset-workloads.yaml`'s `helm.values` block for both a `hasDownloads: true` and `hasDownloads: false` app (hand-substituting the Go-template fields, matching AF-6jta's own verification) and run through `helm template` against the `app-template` chart -- confirm the conditional persistence block parses in both branches.

3. **Cross-file contract checks (highest-value section -- discover expected sets by glob, not hard-coded lists, per this repo's established methodology):**
   - The app-name set in `appset-workloads.yaml`'s `list` generator == the app-name set in `appset-kargo.yaml`'s `list` generator == the app-name set discovered by globbing `apps/arr-stack/env/*/` (AF-8r8l) == the epic's own per-app parameter table (`sonarr`, `radarr`, `lidarr`, `bazarr`, `prowlarr`, `overseerr`) -- all four sources must agree exactly; a 7th app or a missing one in any ONE source is a failure.
   - For every app, the `image` value in `appset-workloads.yaml`'s list == the `image` value in `appset-kargo.yaml`'s list (byte-identical `repoURL`, e.g. `ghcr.io/hotio/sonarr` in both).
   - For every app, the `port`/`hasDownloads` values in `appset-workloads.yaml`'s list exactly match the epic's per-app parameter table (not just "some value present").
   - Glob-discover all 18 `apps/arr-stack/env/*/*/release.yaml` files; confirm exactly 18, confirm the (app, stage) pairs are the full cross-product of the 6-app set x `{dev,staging,prod}`, confirm every file's content is exactly `imageTag: release` / `values: {}`.
   - Every file under `apps/arr-stack/argocd/kargo-chart/` contains the literal string `+argocd:skip-file-rendering` (re-verifies AF-q5yh's own AC independently -- do not just trust the developer's claim, re-derive it).
   - `kargo-chart/templates/project.yaml` carries `argocd.argoproj.io/sync-wave: "-1"` (re-verified, matching this repo's checklist convention).
   - Every workload Application name template (`arr-{{.name}}-{{.path.basename}}`) and its `kargo.akuity.io/authorized-stage` annotation value are structurally consistent with each other (same app name, same stage token) -- a mismatched annotation would silently break Kargo's Application-authorization check without erroring anywhere visible.

4. **Negative assertions, one per explicit Out of scope item (paired with a positive assertion confirming pre-existing/unrelated state is untouched -- single-direction assertions miss the "someone added something they shouldn't have" class of regression):**
   - No file under `apps/arr-stack/` references `plex`, `qbittorrent`, `rflood`, or `sabnzbd` (case-insensitive grep).
   - No file under `apps/arr-stack/` references `kargo-shared` or any `CustomPromotionStep`.
   - `bootstrap/fleet-argocd-apps.yaml`, `bootstrap/fleet-kargo-apps.yaml`, `bootstrap/fleet-platform-aoa.yaml`, and `bootstrap/infra-apps.yaml` are byte-identical to their state before this epic started (git diff against the epic's base commit is empty for every file under `bootstrap/`) -- the positive-assertion half confirming "bootstrap really is untouched," not just "arr-stack doesn't mention bootstrap."
   - No `Stage.spec.verification`/`AnalysisTemplate` block exists anywhere under `apps/arr-stack/argocd/kargo-chart/`.
   - No `storageClassName` is hard-coded in `appset-workloads.yaml`'s persistence block (confirms Story 5's verification gate wasn't silently pre-empted).

5. **Repo-wide collision check:** none of `arr-stack`, `kargo-arr-sonarr`, `kargo-arr-radarr`, `kargo-arr-lidarr`, `kargo-arr-bazarr`, `kargo-arr-prowlarr`, `kargo-arr-overseerr`, or any `arr-{app}-{stage}` Application name collides with any existing Application/AppProject/Kargo-Project name already in this repo (`akkoma`, `soju`, and their generated children) -- repo-wide grep, not just a check within `apps/arr-stack/`.

6. **Project hard-rule / quality-gate check:** confirm this epic's stories collectively satisfy the project's registered `lint.quality_gates` patterns (`CreateNamespace=true` present on both ApplicationSets' `syncOptions`, `storageClassName` explicitly discussed/deferred rather than silently absent, no secrets committed anywhere under `apps/arr-stack/` since this design has none, `never add app-specific config` -- confirmed via the bootstrap byte-identity check above).

7. **Self-validation (required delivery evidence, not optional):** before trusting the new test section, deliberately introduce at least 5 single-field regressions against a scratch copy of the manifests (e.g., rename one app in `appset-workloads.yaml`'s list only, remove the skip-rendering marker from one `kargo-chart` file, delete one `release.yaml`, add a `storageClassName` to the persistence block, change one app's `image` in `appset-kargo.yaml` only) and confirm each is caught by the SPECIFIC assertion meant to catch it (not just "some assertion failed") -- discard the scratch copy afterward. Record which regression was introduced and which assertion caught it as delivery evidence.

KEY FILES:
Modify: `e2e/observability_test.rb` (extend with the `arr_stack` section; do not fork a second test file). Reference-only (read, not modified): every file under `apps/arr-stack/`, `bootstrap/*.yaml` (for the byte-identity check), the epic body's per-app parameter table.

OUT OF SCOPE:
- Live cluster checks of any kind -- this story is static-only by design; live verification is Stories 7-9 (human-gated), which depend on THIS story closing first, not the reverse.
- Rewriting or forking `e2e/observability_test.rb`'s existing `AF-d66a` sections -- this story only adds a new section/method group for `arr-stack`.

DIFF BUDGET:
1 file modified (`e2e/observability_test.rb`), 0 new files. Expect roughly 150-250 added LOC (a new section comparable in size to the existing 150-assertion file's largest section).

CONSUMES:
- AF-q5yh: apps/arr-stack/argocd/{appproject.yaml,kargo-chart/,appset-kargo.yaml} -> AppProject + vendored chart + list-generator ApplicationSet
    source: AF-q5yh's own PRODUCES block
- AF-8r8l: apps/arr-stack/env/<app>/<stage>/release.yaml (18 files) -> promotion-target contract files
    source: AF-8r8l's own PRODUCES block
- AF-6jta: apps/arr-stack/argocd/appset-workloads.yaml -> matrix-generator ApplicationSet
    source: AF-6jta's own PRODUCES block

PRODUCES:
- `e2e/observability_test.rb` (extended) -> static, mutation-tested assertion suite covering all of `apps/arr-stack/`
    source: this story's own design, extending the existing harness per `.vault/knowledge/patterns/Static-only Ruby e2e testing for a GitOps-manifest-only repo.md`

TESTING:
This story IS the testing infrastructure -- its own bar for "done" is: `ruby e2e/observability_test.rb` runs clean (0 failures) against the real committed state, AND the mutation-testing self-check (item 7 above) is recorded as delivery evidence, not asserted without evidence.

Acceptance Criteria:
1. [Ubiquitous] `ruby e2e/observability_test.rb` passes with 0 failures against the real committed `apps/arr-stack/` tree, both before the live merge (AF-o0rw) and again after the live promotion (AF-4wkn) closes -- the suite's output is what this story's own closure evidence shows the user, not an agent's paraphrase of it.
2. [Ubiquitous] The app-name/image/port/hasDownloads sets in `appset-workloads.yaml`, `appset-kargo.yaml`, and the glob-discovered `env/` directory tree are cross-checked and found to agree exactly.
3. [Event] `helm template` renders succeed for both `kargo-chart` and the `app-template` chart, for one `hasDownloads: true` and one `hasDownloads: false` app each.
4. [Unwanted] Every negative assertion in IMPLEMENTATION item 4 passes (no Plex/qBittorrent/rflood/SABnzbd reference, no `kargo-shared`/`CustomPromotionStep` reference, zero bootstrap diff, no verification block, no hard-coded storageClassName).
5. [Ubiquitous] Every file under `kargo-chart/` carries the `+argocd:skip-file-rendering` marker (independently re-verified, not trusted from AF-q5yh's own claim).
6. Mutation-testing self-check completed: at least 5 deliberate single-field regressions introduced against a scratch copy, each caught by its specific intended assertion, recorded as delivery evidence.
7. `bootstrap/*.yaml` byte-identity check passes (0 diff against the epic's base commit).

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory), devops-toolkit:yaml-kubernetes-validator (mandatory), devops-toolkit:helm-chart-developer (mandatory)

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-18T18:57:52Z dep_added: blocked_by AF-q5yh
- 2026-08-18T18:57:53Z dep_added: blocked_by AF-8r8l
- 2026-08-18T18:57:53Z dep_added: blocked_by AF-iv8x
- 2026-08-18T18:57:54Z dep_added: blocked_by AF-6jta
- 2026-08-18T18:58:41Z dep_added: blocks AF-o0rw
- 2026-08-18T19:00:17Z dep_added: blocks AF-4wkn
- 2026-08-18T19:06:18Z dep_removed: no_longer_blocks AF-o0rw
- 2026-08-18T19:06:19Z dep_removed: no_longer_blocks AF-4wkn
- 2026-08-18T19:06:19Z dep_added: blocked_by AF-pfbv
- 2026-08-18T19:06:20Z dep_added: blocked_by AF-o0rw
- 2026-08-18T19:06:20Z dep_added: blocked_by AF-c17x
- 2026-08-18T19:06:21Z dep_added: blocked_by AF-4wkn
- 2026-08-18T19:11:20Z dep_removed: was_blocked_by AF-q5yh

## Links
- Parent: [[AF-j5rz]]
- Blocked by: [[AF-8r8l]], [[AF-iv8x]], [[AF-6jta]], [[AF-pfbv]], [[AF-o0rw]], [[AF-c17x]], [[AF-4wkn]]
- Was blocked by: [[AF-q5yh]]

## Comments
