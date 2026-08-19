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
updated_at: 2026-08-19T15:43:26Z
content_hash: "sha256:aa02ca673a7923414e823645283362809f18aa34309c62802c62e3c0192b66c7"
blocked_by: [AF-6jta, AF-pfbv, AF-o0rw, AF-c17x, AF-4wkn]
was_blocked_by: [AF-q5yh, AF-iv8x, AF-hb2f, AF-8r8l, AF-yse2]
---

## Description
Description:
Static verification capstone for the whole `arr-stack` manifest set: prove the committed manifests describe a coherent, deployable system end to end -- including every cross-file contract that would otherwise only break at runtime -- without requiring a live cluster on the critical path. This is the epic's capstone: it introduces no new deploy-facing code, it proves everything the other developer-claimable and human-gated stories (AF-hb2f, AF-yse2, AF-8r8l, AF-iv8x, AF-6jta, AF-pfbv, AF-o0rw, AF-c17x, AF-4wkn) built actually fits together as one system end to end, catching anything that passed its own story's narrower verification but breaks when everything -- including the live evidence -- is combined.

BUG RESOLUTION (AF-hb2f discovered-bug follow-up, applied here before this story is claimed):
AF-8r8l and AF-6jta were both amended, ahead of this story, to fix a `tag:`-vs-`digest:` mismatch: `release.yaml`'s `imageTag` key holds a `sha256:<hex>` digest (per AF-hb2f's delivered `tasks.yaml`), and `appset-workloads.yaml` binds it to app-template's `digest:` field, not `tag:` (binding it to `tag:` would render an unparseable `repository:sha256:...` reference). This story's cross-file contract checks (item 3) and its self-validation regression list (item 7) below are written for the CORRECTED shape (`imageTag` is a digest, seeded per-app with a real resolvable value; the binding is `digest:`) -- do not write assertions against the original, buggy `imageTag: release` / `tag:` shape described in the design spec's own literal snippet (`docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md` lines ~203-205, tracked separately as a documentation-only fix, non-blocking).

ROSTER CORRECTION (separate discovered-bug follow-up, applied here before this story is claimed): the sixth app in this epic's family was originally `overseerr`/`ghcr.io/hotio/overseerr`. hotio retired that image; it is renamed `seerr`/`ghcr.io/hotio/seerr` throughout the epic (AF-j5rz's own per-app parameter table, AF-8r8l, AF-6jta, and a dedicated patch bug, AF-yse2, for AF-hb2f's already-merged `appset-kargo.yaml`/`appproject.yaml`). Every reference to the sixth app below has been updated from `overseerr` to `seerr` accordingly -- this story's cross-file contract checks (item 3), negative assertions (item 4), and collision check (item 5) are all written for the CORRECTED roster. Do not write any assertion that expects or tolerates `overseerr` anywhere under `apps/arr-stack/`; a lingering `overseerr` reference at capstone time is itself a regression this story must catch (see item 4's added check below).

**Sequencing note (mechanical, not narrative):** this story's `e2e/observability_test.rb` extension is written and run to completion BEFORE the live merge (AF-o0rw) is attempted -- writing and passing the static suite first is the whole point of a two-tier verification design, and AF-o0rw's own Step 0 requires confirming this suite is clean before merging. This story's nd ticket, however, is `blocked_by` every other sibling in the epic (including the human-gated live stories) and therefore CLOSES last: closing it is the final act of the epic, re-confirming that the static suite still passes and every negative assertion still holds after the live merge and promotion, not just before it. Author and run the suite early; close the ticket last.

Context:
This repo already has an established, reusable pattern for exactly this kind of test: `e2e/observability_test.rb` (`.vault/knowledge/patterns/Static-only Ruby e2e testing for a GitOps-manifest-only repo.md`), built for the prior `AF-d66a` epic's completion gate. Two hard constraints drove that choice, both apply identically here:
1. `pvg verify --check-e2e` only scans recognized source-file extensions -- a `.sh` file is invisible to that gate regardless of path or name.
2. This repo has zero test tooling installed and no lockfile/dependency-management convention for one. Ruby ships `YAML` and `JSON` in its standard library on both a stock macOS workstation and a stock CI runner -- zero external dependencies.

Reuse `e2e/observability_test.rb`'s harness (assert helpers, `dig_path`, `doc`/`raw` caching) as the base -- extend it with a new section for `arr-stack`, do not fork it into a second test file. There is no installed skill for this methodology yet (it's a pending vault proposal, not yet promoted) -- every specific check below is spelled out explicitly rather than referenced by skill name.

USER INTENT:
Anyone reviewing this epic's delivery needs one command that either says "the whole arr-stack manifest set is internally coherent" or points at the exact cross-file contract that's broken -- not five separate spot-checks that each pass in isolation while the system as a whole is subtly wrong (a 7th app added to one list and not the other, a `hasDownloads` mismatch between the parameter table and the rendered template, a stray reference to an out-of-scope app, a stray reference to the retired `overseerr` image, or a digest silently bound into the wrong app-template field). Running the suite displays a clear pass/fail per section; the user can trust a clean run as the epic's actual coherence proof, not an agent's paraphrase of one.

IMPLEMENTATION:
Add a new section to `e2e/observability_test.rb` (or a clearly-delineated `arr_stack` method group within it) covering:

1. **Structural / lint checks** (accumulate-and-report, not fail-fast -- every assertion runs regardless of earlier failures):
   - Every YAML file under `apps/arr-stack/` parses cleanly (`YAML.load_stream`), including multi-document `stages.yaml`.
   - `yamllint`/`kubeconform` (or the repo's existing static-check convention) against `appproject.yaml`, `appset-workloads.yaml`, `appset-kargo.yaml`, and every `kargo-chart/templates/*.yaml` -- note that the `kargo-chart/templates/*.yaml` files are Helm templates, not raw manifests, so lint them post-`helm template` render, not as raw YAML with unrendered `{{ }}` syntax.

2. **`helm template` render checks:**
   - `helm template apps/arr-stack/argocd/kargo-chart --set appName=sonarr --set image=ghcr.io/hotio/sonarr` and again with `--set appName=prowlarr --set image=ghcr.io/hotio/prowlarr` (one `hasDownloads: true` app, one `false`, matching AF-hb2f's own verification) -- confirm both render a well-formed, app-name-scoped Project/Warehouse/3xStage/PromotionTask set.
   - Manually render `appset-workloads.yaml`'s `helm.values` block for both a `hasDownloads: true` and `hasDownloads: false` app (hand-substituting the Go-template fields, matching AF-6jta's own verification, using a real `sha256:<hex>` value for `{{.values.imageTag}}`) and run through `helm template` against the `app-template` chart -- confirm the conditional persistence block parses in both branches AND confirm the rendered container image reference is `<repository>@sha256:<hex>` (never `<repository>:sha256:<hex>`).

3. **Cross-file contract checks (highest-value section -- discover expected sets by glob, not hard-coded lists, per this repo's established methodology):**
   - The app-name set in `appset-workloads.yaml`'s `list` generator == the app-name set in `appset-kargo.yaml`'s `list` generator == the app-name set discovered by globbing `apps/arr-stack/env/*/` (AF-8r8l) == the epic's own per-app parameter table (`sonarr`, `radarr`, `lidarr`, `bazarr`, `prowlarr`, `seerr`) -- all four sources must agree exactly; a 7th app, a missing one, or a stale `overseerr` in any ONE source is a failure.
   - For every app, the `image` value in `appset-workloads.yaml`'s list == the `image` value in `appset-kargo.yaml`'s list (byte-identical `repoURL`, e.g. `ghcr.io/hotio/sonarr` in both; for the sixth app, `ghcr.io/hotio/seerr` in both, never `ghcr.io/hotio/overseerr`).
   - For every app, the `port`/`hasDownloads` values in `appset-workloads.yaml`'s list exactly match the epic's per-app parameter table (not just "some value present").
   - Glob-discover all 18 `apps/arr-stack/env/*/*/release.yaml` files; confirm exactly 18, confirm the (app, stage) pairs are the full cross-product of the 6-app set (including `seerr`, never `overseerr`) x `{dev,staging,prod}`, confirm every file's `values` key is exactly `{}` and every file's `imageTag` value matches `sha256:<64 lowercase hex chars>` (a well-formed digest -- NOT the literal string `release` or any other tag-shaped value, per this story's BUG RESOLUTION note above), and confirm that for each app, all three stage files share one byte-identical `imageTag` value (the shared pre-promotion seed) while different apps are NOT required to match each other.
   - `apps/arr-stack/argocd/appset-workloads.yaml` binds `digest: "{{.values.imageTag}}"` in its container image block, and does NOT contain the substring `tag: "{{.values.imageTag}}"` anywhere -- the exact regression this epic's bug-triage pass exists to prevent, re-verified independently here rather than trusted from AF-6jta's own claim.
   - Every file under `apps/arr-stack/argocd/kargo-chart/` contains the literal string `+argocd:skip-file-rendering` (re-verifies AF-hb2f's own AC independently -- do not just trust the developer's claim, re-derive it).
   - `kargo-chart/templates/project.yaml` carries `argocd.argoproj.io/sync-wave: "-1"` (re-verified, matching this repo's checklist convention).
   - Every workload Application name template (`arr-{{.name}}-{{.path.basename}}`) and its `kargo.akuity.io/authorized-stage` annotation value are structurally consistent with each other (same app name, same stage token) -- a mismatched annotation would silently break Kargo's Application-authorization check without erroring anywhere visible.

4. **Negative assertions, one per explicit Out of scope item (paired with a positive assertion confirming pre-existing/unrelated state is untouched -- single-direction assertions miss the "someone added something they shouldn't have" class of regression):**
   - No file under `apps/arr-stack/` references `plex`, `qbittorrent`, `rflood`, or `sabnzbd` (case-insensitive grep).
   - No file under `apps/arr-stack/` references `kargo-shared` or any `CustomPromotionStep`.
   - No file under `apps/arr-stack/` references `overseerr` (case-insensitive grep) -- confirms this epic's rename bug-triage fix (AF-yse2 + amendments to AF-8r8l/AF-6jta) wasn't silently reverted or left half-applied anywhere in the tree.
   - `bootstrap/fleet-argocd-apps.yaml`, `bootstrap/fleet-kargo-apps.yaml`, `bootstrap/fleet-platform-aoa.yaml`, and `bootstrap/infra-apps.yaml` are byte-identical to their state before this epic started (git diff against the epic's base commit is empty for every file under `bootstrap/`) -- the positive-assertion half confirming "bootstrap really is untouched," not just "arr-stack doesn't mention bootstrap."
   - No `Stage.spec.verification`/`AnalysisTemplate` block exists anywhere under `apps/arr-stack/argocd/kargo-chart/`.
   - No `storageClassName` is hard-coded in `appset-workloads.yaml`'s persistence block (confirms AF-pfbv's verification gate wasn't silently pre-empted).
   - No `release.yaml` file's `imageTag` value is the literal string `release`, empty, or otherwise non-digest-shaped (confirms this epic's bug-triage fix wasn't silently reverted).

5. **Repo-wide collision check:** none of `arr-stack`, `kargo-arr-sonarr`, `kargo-arr-radarr`, `kargo-arr-lidarr`, `kargo-arr-bazarr`, `kargo-arr-prowlarr`, `kargo-arr-seerr`, or any `arr-{app}-{stage}` Application name collides with any existing Application/AppProject/Kargo-Project name already in this repo (`akkoma`, `soju`, and their generated children) -- repo-wide grep, not just a check within `apps/arr-stack/`.

6. **Project hard-rule / quality-gate check:** confirm this epic's stories collectively satisfy the project's registered `lint.quality_gates` patterns (`CreateNamespace=true` present on both ApplicationSets' `syncOptions`, `storageClassName` explicitly discussed/deferred rather than silently absent, no secrets committed anywhere under `apps/arr-stack/` since this design has none, `never add app-specific config` -- confirmed via the bootstrap byte-identity check above).

7. **Self-validation (required delivery evidence, not optional):** before trusting the new test section, deliberately introduce at least 6 single-field regressions against a scratch copy of the manifests (e.g., rename one app in `appset-workloads.yaml`'s list only, remove the skip-rendering marker from one `kargo-chart` file, delete one `release.yaml`, add a `storageClassName` to the persistence block, change one app's `image` in `appset-kargo.yaml` only, and change `appset-workloads.yaml`'s image block from `digest: "{{.values.imageTag}}"` back to `tag: "{{.values.imageTag}}"` -- this last one specifically re-introduces the bug this epic's triage pass fixed) and confirm each is caught by the SPECIFIC assertion meant to catch it (not just "some assertion failed") -- discard the scratch copy afterward. Record which regression was introduced and which assertion caught it as delivery evidence. Include a 7th regression reintroducing a stray `overseerr` reference (e.g. revert one `appset-kargo.yaml` list element back to `overseerr`/`ghcr.io/hotio/overseerr`) and confirm the item-4 negative assertion added above catches it.

KEY FILES:
Modify: `e2e/observability_test.rb` (extend with the `arr_stack` section; do not fork a second test file). Reference-only (read, not modified): every file under `apps/arr-stack/`, `bootstrap/*.yaml` (for the byte-identity check), the epic body's per-app parameter table.

OUT OF SCOPE:
- Live cluster checks of any kind -- this story is static-only by design; live verification is AF-o0rw/AF-c17x/AF-4wkn (human-gated), which depend on THIS story closing first, not the reverse.
- Rewriting or forking `e2e/observability_test.rb`'s existing `AF-d66a` sections -- this story only adds a new section/method group for `arr-stack`.
- Correcting the design spec doc's own snippet (`docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md` lines ~120, ~170-171, ~203-205, ~296-297) -- tracked as a documentation-only follow-up outside the execution path.

DIFF BUDGET:
1 file modified (`e2e/observability_test.rb`), 0 new files. Expect roughly 150-260 added LOC (a new section comparable in size to the existing 150-assertion file's largest section; slightly larger than the original estimate to cover the digest/tag and overseerr/seerr regression checks added by this bug-triage pass).

CONSUMES:
- AF-hb2f: apps/arr-stack/argocd/{appproject.yaml,kargo-chart/,appset-kargo.yaml} -> AppProject + vendored chart + list-generator ApplicationSet
    source: AF-hb2f's own PRODUCES block
- AF-yse2: apps/arr-stack/argocd/{appset-kargo.yaml,appproject.yaml} -> corrected `seerr`/`ghcr.io/hotio/seerr` roster entry and AppProject description
    source: AF-yse2's own AC
- AF-8r8l: apps/arr-stack/env/<app>/<stage>/release.yaml (18 files, roster: sonarr/radarr/lidarr/bazarr/prowlarr/seerr) -> promotion-target contract files
    schema: imageTag (string, "sha256:<64 lowercase hex chars>"), values (object)
    source: AF-8r8l's own PRODUCES block (as amended by this bug-triage pass)
- AF-6jta: apps/arr-stack/argocd/appset-workloads.yaml -> matrix-generator ApplicationSet
    spec: container image block binds digest: "{{.values.imageTag}}" (not tag:); sixth app is seerr/ghcr.io/hotio/seerr (not overseerr)
    source: AF-6jta's own PRODUCES block (as amended by this bug-triage pass)

PRODUCES:
- `e2e/observability_test.rb` (extended) -> static, mutation-tested assertion suite covering all of `apps/arr-stack/`
    source: this story's own design, extending the existing harness per `.vault/knowledge/patterns/Static-only Ruby e2e testing for a GitOps-manifest-only repo.md`

Acceptance Criteria:
1. [Ubiquitous] `e2e/observability_test.rb` gains a new `arr_stack` section covering all seven implementation items above.
2. [Ubiquitous] All structural/lint checks (item 1) and all `helm template` render checks (item 2) pass, including the corrected digest-reference assertion.
3. [Ubiquitous] All cross-file contract checks (item 3) pass, including the `imageTag` digest-shape check, the `digest:` (not `tag:`) binding check, and the `seerr` (not `overseerr`) roster check.
4. [Unwanted] All negative assertions (item 4) pass, including the new digest-regression check and the new overseerr-regression check.
5. [Ubiquitous] The repo-wide collision check (item 5) and quality-gate check (item 6) pass.
6. [Ubiquitous] Self-validation (item 7) is performed with at least 7 deliberate regressions, one of which is the `digest:`-to-`tag:` reversion and one of which is an `overseerr` reintroduction, and each is caught by its specific assertion; this is recorded as delivery evidence, not asserted without detail.
7. Running the full extended `e2e/observability_test.rb` produces zero failures against the real, committed `apps/arr-stack/` manifests.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory), devops-toolkit:yaml-kubernetes-validator (mandatory), devops-toolkit:helm-chart-developer (mandatory -- app-template's `image.digest` vs `image.tag` fields)

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
- 2026-08-18T19:11:43Z dep_added: blocked_by AF-hb2f
- 2026-08-19T14:44:32Z dep_removed: was_blocked_by AF-iv8x
- 2026-08-19T15:09:39Z dep_removed: was_blocked_by AF-hb2f
- 2026-08-19T15:45:38Z dep_added: blocked_by AF-yse2
- 2026-08-19T15:59:15Z dep_removed: was_blocked_by AF-8r8l
- 2026-08-19T16:03:25Z dep_removed: was_blocked_by AF-yse2

## Links
- Parent: [[AF-j5rz]]
- Blocked by: [[AF-6jta]], [[AF-pfbv]], [[AF-o0rw]], [[AF-c17x]], [[AF-4wkn]]
- Was blocked by: [[AF-q5yh]], [[AF-iv8x]], [[AF-hb2f]], [[AF-8r8l]], [[AF-yse2]]

## Comments

### 2026-08-19T15:02:56Z ada
BUG TRIAGE (Sr PM): amended this capstone's static verification IMPLEMENTATION/ACs in lockstep with AF-8r8l and AF-6jta to match the corrected release.yaml/appset-workloads.yaml contract (imageTag holds a sha256 digest, seeded per-app with a real resolvable value; appset-workloads.yaml binds digest: not tag:). Also added a dedicated regression check (item 4 negative assertion + item 7 self-validation regression #6) so a future revert of the digest: binding back to tag: is caught by the static suite before it ever reaches a live cluster. See AF-8r8l/AF-6jta comments for the full discovered-bug context (originally surfaced by AF-hb2f's deliver-only follow-up developer).
