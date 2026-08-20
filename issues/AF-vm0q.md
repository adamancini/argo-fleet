---
id: AF-vm0q
title: "Static verification suite for arr-stack manifests"
status: closed
priority: 1
type: task
labels: [capstone, accepted]
parent: AF-j5rz
created_at: 2026-08-18T18:57:46Z
created_by: ada
updated_at: 2026-08-20T16:39:21Z
content_hash: "sha256:671e22bb46e7f66cfc6ef8ed42ae80162055a045ff4d70d00bfe86a6787c3eb6"
was_blocked_by: [AF-q5yh, AF-iv8x, AF-hb2f, AF-8r8l, AF-yse2, AF-6jta, AF-pfbv, AF-wb16, AF-o0rw, AF-c17x, AF-4wkn]
assignee: dev-AF-vm0q
follows: [AF-iv8x, AF-hb2f, AF-8r8l, AF-yse2, AF-6jta, AF-pfbv, AF-wb16, AF-o0rw, AF-c17x, AF-4wkn]
closed_at: 2026-08-20T16:39:20Z
close_reason: "Accepted via pvg story accept"
---

## Description
Description:
Static verification capstone for the whole `arr-stack` manifest set: prove the committed manifests describe a coherent, deployable system end to end -- including every cross-file contract that would otherwise only break at runtime -- without requiring a live cluster on the critical path. This is the epic's capstone: it introduces no new deploy-facing code, it proves everything the other developer-claimable and human-gated stories (AF-hb2f, AF-yse2, AF-8r8l, AF-iv8x, AF-6jta, AF-pfbv, AF-o0rw, AF-c17x, AF-4wkn) built actually fits together as one system end to end, catching anything that passed its own story's narrower verification but breaks when everything -- including the live evidence -- is combined.

BUG RESOLUTION (AF-hb2f discovered-bug follow-up, applied here before this story is claimed):
AF-8r8l and AF-6jta were both amended, ahead of this story, to fix a `tag:`-vs-`digest:` mismatch: `release.yaml`'s `imageTag` key holds a `sha256:<hex>` digest (per AF-hb2f's delivered `tasks.yaml`), and `appset-workloads.yaml` binds it to app-template's `digest:` field, not `tag:` (binding it to `tag:` would render an unparseable `repository:sha256:...` reference). This story's cross-file contract checks (item 3) and its self-validation regression list (item 7) below are written for the CORRECTED shape (`imageTag` is a digest, seeded per-app with a real resolvable value; the binding is `digest:`) -- do not write assertions against the original, buggy `imageTag: release` / `tag:` shape described in the design spec's own literal snippet (`docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md` lines ~203-205, tracked separately as a documentation-only fix, non-blocking).

PARAM PATH CORRECTION (second bug-triage pass, applied here before this story is claimed -- discovered by AF-6jta's own deliver-only follow-up developer): the digest binds to `{{.imageTag}}`, NOT `{{.values.imageTag}}`. Argo CD's git *files* generator exposes a discovered file's top-level keys directly, with no prefix -- `release.yaml`'s `imageTag` key is top-level (AF-hb2f's `tasks.yaml` `yaml-update` step writes `key: imageTag`, top level), and its sibling `values: {}` key is an empty map everywhere across all 18 seeded files, so `.values.imageTag` resolves nowhere and, under this ApplicationSet's own `goTemplateOptions: ["missingkey=error"]`, aborts rendering for all 18 Applications. AF-6jta's actual delivered `appset-workloads.yaml` ships the corrected `{{.imageTag}}` path; this story's cross-file contract checks (item 3) and self-validation regression list (item 7) below are written for that corrected path -- do not write assertions expecting `{{.values.imageTag}}` to appear in the delivered file, and treat EITHER `tag: "{{.imageTag}}"` OR `tag: "{{.values.imageTag}}"` as the forbidden regression substring (either path, bound to the wrong field, is the same class of bug).

ROSTER CORRECTION (separate discovered-bug follow-up, applied here before this story is claimed): the sixth app in this epic's family was originally `overseerr`/`ghcr.io/hotio/overseerr`. hotio retired that image; it is renamed `seerr`/`ghcr.io/hotio/seerr` throughout the epic (AF-j5rz's own per-app parameter table, AF-8r8l, AF-6jta, and a dedicated patch bug, AF-yse2, for AF-hb2f's already-merged `appset-kargo.yaml`/`appproject.yaml`). Every reference to the sixth app below has been updated from `overseerr` to `seerr` accordingly -- this story's cross-file contract checks (item 3), negative assertions (item 4), and collision check (item 5) are all written for the CORRECTED roster. Do not write any assertion that expects or tolerates `overseerr` anywhere under `apps/arr-stack/`; a lingering `overseerr` reference at capstone time is itself a regression this story must catch (see item 4's added check below).

**Sequencing note (mechanical, not narrative):** this story's `e2e/observability_test.rb` extension is written and run to completion BEFORE the live merge (AF-o0rw) is attempted -- writing and passing the static suite first is the whole point of a two-tier verification design, and AF-o0rw's own Step 0 requires confirming this suite is clean before merging. This story's nd ticket, however, is `blocked_by` every other sibling in the epic (including the human-gated live stories) and therefore CLOSES last: closing it is the final act of the epic, re-confirming that the static suite still passes and every negative assertion still holds after the live merge and promotion, not just before it. Author and run the suite early; close the ticket last.

Context:
This repo already has an established, reusable pattern for exactly this kind of test: `e2e/observability_test.rb` (`.vault/knowledge/patterns/Static-only Ruby e2e testing for a GitOps-manifest-only repo.md`), built for the prior `AF-d66a` epic's completion gate. Two hard constraints drove that choice, both apply identically here:
1. `pvg verify --check-e2e` only scans recognized source-file extensions -- a `.sh` file is invisible to that gate regardless of path or name.
2. This repo has zero test tooling installed and no lockfile/dependency-management convention for one. Ruby ships `YAML` and `JSON` in its standard library on both a stock macOS workstation and a stock CI runner -- zero external dependencies.

Reuse `e2e/observability_test.rb`'s harness (assert helpers, `dig_path`, `doc`/`raw` caching) as the base -- extend it with a new section for `arr-stack`, do not fork it into a second test file. There is no installed skill for this methodology yet (it's a pending vault proposal, not yet promoted) -- every specific check below is spelled out explicitly rather than referenced by skill name.

USER INTENT:
Anyone reviewing this epic's delivery needs one command that either says "the whole arr-stack manifest set is internally coherent" or points at the exact cross-file contract that's broken -- not five separate spot-checks that each pass in isolation while the system as a whole is subtly wrong (a 7th app added to one list and not the other, a `hasDownloads` mismatch between the parameter table and the rendered template, a stray reference to an out-of-scope app, a stray reference to the retired `overseerr` image, or a digest silently bound into the wrong app-template field or the wrong param path). Running the suite displays a clear pass/fail per section; the user can trust a clean run as the epic's actual coherence proof, not an agent's paraphrase of one.

IMPLEMENTATION:
Add a new section to `e2e/observability_test.rb` (or a clearly-delineated `arr_stack` method group within it) covering:

1. **Structural / lint checks** (accumulate-and-report, not fail-fast -- every assertion runs regardless of earlier failures):
   - Every YAML file under `apps/arr-stack/` parses cleanly (`YAML.load_stream`), including multi-document `stages.yaml`.
   - `yamllint`/`kubeconform` (or the repo's existing static-check convention) against `appproject.yaml`, `appset-workloads.yaml`, `appset-kargo.yaml`, and every `kargo-chart/templates/*.yaml` -- note that the `kargo-chart/templates/*.yaml` files are Helm templates, not raw manifests, so lint them post-`helm template` render, not as raw YAML with unrendered `{{ }}` syntax.

2. **`helm template` render checks:**
   - `helm template apps/arr-stack/argocd/kargo-chart --set appName=sonarr --set image=ghcr.io/hotio/sonarr` and again with `--set appName=prowlarr --set image=ghcr.io/hotio/prowlarr` (one `hasDownloads: true` app, one `false`, matching AF-hb2f's own verification) -- confirm both render a well-formed, app-name-scoped Project/Warehouse/3xStage/PromotionTask set.
   - Manually render `appset-workloads.yaml`'s `helm.values` block for both a `hasDownloads: true` and `hasDownloads: false` app (hand-substituting the Go-template fields, matching AF-6jta's own verification, using a real `sha256:<hex>` value for `{{.imageTag}}`) and run through `helm template` against the `app-template` chart -- confirm the conditional persistence block parses in both branches AND confirm the rendered container image reference is `<repository>@sha256:<hex>` (never `<repository>:sha256:<hex>`).

3. **Cross-file contract checks (highest-value section -- discover expected sets by glob, not hard-coded lists, per this repo's established methodology):**
   - The app-name set in `appset-workloads.yaml`'s `list` generator == the app-name set in `appset-kargo.yaml`'s `list` generator == the app-name set discovered by globbing `apps/arr-stack/env/*/` (AF-8r8l) == the epic's own per-app parameter table (`sonarr`, `radarr`, `lidarr`, `bazarr`, `prowlarr`, `seerr`) -- all four sources must agree exactly; a 7th app, a missing one, or a stale `overseerr` in any ONE source is a failure.
   - For every app, the `image` value in `appset-workloads.yaml`'s list == the `image` value in `appset-kargo.yaml`'s list (byte-identical `repoURL`, e.g. `ghcr.io/hotio/sonarr` in both; for the sixth app, `ghcr.io/hotio/seerr` in both, never `ghcr.io/hotio/overseerr`).
   - For every app, the `port`/`hasDownloads` values in `appset-workloads.yaml`'s list exactly match the epic's per-app parameter table (not just "some value present").
   - Glob-discover all 18 `apps/arr-stack/env/*/*/release.yaml` files; confirm exactly 18, confirm the (app, stage) pairs are the full cross-product of the 6-app set (including `seerr`, never `overseerr`) x `{dev,staging,prod}`, confirm every file's `values` key is exactly `{}` and every file's `imageTag` value matches `sha256:<64 lowercase hex chars>` (a well-formed digest -- NOT the literal string `release` or any other tag-shaped value, per this story's BUG RESOLUTION note above), and confirm that for each app, all three stage files share one byte-identical `imageTag` value (the shared pre-promotion seed) while different apps are NOT required to match each other.
   - `apps/arr-stack/argocd/appset-workloads.yaml` binds `digest: "{{.imageTag}}"` in its container image block (the corrected param path -- NOT `{{.values.imageTag}}`, which resolves nowhere against the seeded `release.yaml` shape), and does NOT contain the substring `tag: "{{.imageTag}}"` OR `tag: "{{.values.imageTag}}"` anywhere -- either is the exact regression this epic's bug-triage pass exists to prevent, re-verified independently here rather than trusted from AF-6jta's own claim.
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
   - `appset-workloads.yaml`'s container image block does not contain `tag: "{{.imageTag}}"` or `tag: "{{.values.imageTag}}"` anywhere (confirms the digest/tag regression fix wasn't silently reverted under either param path).

5. **Repo-wide collision check:** none of `arr-stack`, `kargo-arr-sonarr`, `kargo-arr-radarr`, `kargo-arr-lidarr`, `kargo-arr-bazarr`, `kargo-arr-prowlarr`, `kargo-arr-seerr`, or any `arr-{app}-{stage}` Application name collides with any existing Application/AppProject/Kargo-Project name already in this repo (`akkoma`, `soju`, and their generated children) -- repo-wide grep, not just a check within `apps/arr-stack/`.

6. **Project hard-rule / quality-gate check:** confirm this epic's stories collectively satisfy the project's registered `lint.quality_gates` patterns (`CreateNamespace=true` present on both ApplicationSets' `syncOptions`, `storageClassName` explicitly discussed/deferred rather than silently absent, no secrets committed anywhere under `apps/arr-stack/` since this design has none, `never add app-specific config` -- confirmed via the bootstrap byte-identity check above).

7. **Self-validation (required delivery evidence, not optional):** before trusting the new test section, deliberately introduce at least 6 single-field regressions against a scratch copy of the manifests (e.g., rename one app in `appset-workloads.yaml`'s list only, remove the skip-rendering marker from one `kargo-chart` file, delete one `release.yaml`, add a `storageClassName` to the persistence block, change one app's `image` in `appset-kargo.yaml` only, and change `appset-workloads.yaml`'s image block from `digest: "{{.imageTag}}"` back to `tag: "{{.imageTag}}"` -- this last one specifically re-introduces the bug this epic's triage pass fixed) and confirm each is caught by the SPECIFIC assertion meant to catch it (not just "some assertion failed") -- discard the scratch copy afterward. Record which regression was introduced and which assertion caught it as delivery evidence. Include a 7th regression reintroducing a stray `overseerr` reference (e.g. revert one `appset-kargo.yaml` list element back to `overseerr`/`ghcr.io/hotio/overseerr`) and confirm the item-4 negative assertion added above catches it. Include an 8th regression changing the image block to the WRONG param path with the RIGHT field (`digest: "{{.values.imageTag}}"`) and confirm the item-3/item-4 assertions above catch that variant too, distinct from the `tag:` regression.

KEY FILES:
Modify: `e2e/observability_test.rb` (extend with the `arr_stack` section; do not fork a second test file). Reference-only (read, not modified): every file under `apps/arr-stack/`, `bootstrap/*.yaml` (for the byte-identity check), the epic body's per-app parameter table.

OUT OF SCOPE:
- Live cluster checks of any kind -- this story is static-only by design; live verification is AF-o0rw/AF-c17x/AF-4wkn (human-gated), which depend on THIS story closing first, not the reverse.
- Rewriting or forking `e2e/observability_test.rb`'s existing `AF-d66a` sections -- this story only adds a new section/method group for `arr-stack`.
- Correcting the design spec doc's own snippet (`docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md` lines ~120, ~170-171, ~203-205, ~296-297) -- tracked as a documentation-only follow-up outside the execution path.

DIFF BUDGET:
1 file modified (`e2e/observability_test.rb`), 0 new files. Expect roughly 150-260 added LOC (a new section comparable in size to the existing 150-assertion file's largest section; slightly larger than the original estimate to cover the digest/tag, param-path, and overseerr/seerr regression checks added by this bug-triage pass).

CONSUMES:
- AF-hb2f: apps/arr-stack/argocd/{appproject.yaml,kargo-chart/,appset-kargo.yaml} -> AppProject + vendored chart + list-generator ApplicationSet
    source: AF-hb2f's own PRODUCES block
- AF-yse2: apps/arr-stack/argocd/{appset-kargo.yaml,appproject.yaml} -> corrected `seerr`/`ghcr.io/hotio/seerr` roster entry and AppProject description
    source: AF-yse2's own AC
- AF-8r8l: apps/arr-stack/env/<app>/<stage>/release.yaml (18 files, roster: sonarr/radarr/lidarr/bazarr/prowlarr/seerr) -> promotion-target contract files
    schema: imageTag (string, top-level key, "sha256:<64 lowercase hex chars>"), values (object, empty map)
    source: AF-8r8l's own PRODUCES block (as amended by this bug-triage pass)
- AF-6jta: apps/arr-stack/argocd/appset-workloads.yaml -> matrix-generator ApplicationSet
    spec: container image block binds digest: "{{.imageTag}}" (not tag:, not .values.imageTag); sixth app is seerr/ghcr.io/hotio/seerr (not overseerr)
    source: AF-6jta's own PRODUCES block (as amended by this bug-triage pass, param-path correction)

PRODUCES:
- `e2e/observability_test.rb` (extended) -> static, mutation-tested assertion suite covering all of `apps/arr-stack/`
    source: this story's own design, extending the existing harness per `.vault/knowledge/patterns/Static-only Ruby e2e testing for a GitOps-manifest-only repo.md`

Acceptance Criteria:
1. [Ubiquitous] `e2e/observability_test.rb` gains a new `arr_stack` section covering all seven implementation items above.
2. [Ubiquitous] All structural/lint checks (item 1) and all `helm template` render checks (item 2) pass, including the corrected digest-reference assertion.
3. [Ubiquitous] All cross-file contract checks (item 3) pass, including the `imageTag` digest-shape check, the `digest: "{{.imageTag}}"` (not `tag:`, not `.values.imageTag`) binding check, and the `seerr` (not `overseerr`) roster check.
4. [Unwanted] All negative assertions (item 4) pass, including the new digest/tag-and-param-path regression check and the new overseerr-regression check.
5. [Ubiquitous] The repo-wide collision check (item 5) and quality-gate check (item 6) pass.
6. [Ubiquitous] Self-validation (item 7) is performed with at least 8 deliberate regressions, including the `digest:`-to-`tag:` reversion (under the corrected `.imageTag` path), the wrong-param-path variant (`digest: "{{.values.imageTag}}"`), and an `overseerr` reintroduction, and each is caught by its specific assertion; this is recorded as delivery evidence, not asserted without detail.
7. Running the full extended `e2e/observability_test.rb` produces zero failures against the real, committed `apps/arr-stack/` manifests.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory), devops-toolkit:yaml-kubernetes-validator (mandatory), devops-toolkit:helm-chart-developer (mandatory -- app-template's `image.digest` vs `image.tag` fields)

## Acceptance Criteria


## Design


## Notes
Bug triage (pvg gates duplication false positive) resolved -- NOT a code defect.

Actual root cause (differs from the discovering developer's hypothesis): the
59-line duplication BLOCK on apps/arr-stack/argocd/appset-workloads.yaml is
jscpd matching that file's rendered template block against a near-verbatim
copy embedded in docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md
(the design spec quotes the manifest for explanatory purposes), NOT
self-duplication from the per-app `list` generator's 6 near-identical
elements as originally suspected. Verified directly with `jscpd . --reporters
console`, which prints both sides of every clone pair -- every one of the 14
pre-existing BLOCKs in this repo (Taskfile.yml, apps/akkoma/argocd/appset.yaml,
apps/soju/kargo/stages.yaml, and the terraform/cluster-lifecycle plan doc) has
a docs/superpowers/{plans,specs}/*.md file on at least one side. Zero real
code-vs-code duplication exists in this repo today.

Tooling limitation found: `pvg settings gates.exclude=...` (any glob syntax
tried: bare dir, trailing slash, `**`, `**/*.md`) has NO effect on the
duplication gate in pvg 1.62.0 -- confirmed by direct A/B testing (jscpd
itself honors the identical glob via `--ignore`, but `pvg gates` output was
byte-identical with and without the setting). Only the numeric
`gates.duplication.min_lines`/`max_pct` settings are actually honored by this
pvg build. This means the "narrow gates.exclude for one file" remediation
shape described in the bug is currently non-functional and should not be
relied on until pvg fixes the wiring.

Remediation applied instead: added `.jscpd.json` at repo root with
`{"ignore": ["docs/superpowers/**"]}`. jscpd (which `pvg gates` shells out to)
auto-discovers this file from cwd, independent of pvg's own settings layer.
This clears all 14 duplication BLOCKs + the aggregate total BLOCK (`pvg
gates` now PASSes except the pre-existing, unrelated file_loc WARN on
e2e/observability_test.rb) without touching gates.duplication.min_lines/
max_pct (left at defaults, 50/10%) and without excluding any manifest file
itself -- apps/arr-stack, apps/akkoma, apps/soju, Taskfile.yml, and
terraform/ remain fully subject to duplication scanning against each other
and any future real code. Only the docs/superpowers/{plans,specs}/ planning
artifact tree (which by the superpowers writing-plans/brainstorming skill's
own convention quotes real manifests/terraform verbatim as design records) is
excluded. Verified via full jscpd clone-pair listing that nothing else would
be masked by this exclusion.

This does not block AF-vm0q's own review. AF-vm0q's actual deliverable (the
extended e2e/observability_test.rb) is untouched by this change; its 463>400
file_loc WARN is real, pre-existing, and unrelated to duplication.

Confirmed post-change: `pvg gates` PASS (1 warn), `pvg rtm check` PASSED,
`pvg lint` PASSED (no artifact collisions).


## nd_contract
status: accepted

### evidence
- PM closeout applied via pvg story accept on 2026-08-20.

### proof
- [x] Story closed after accepted label was applied.


## nd_contract
status: delivered

### evidence
- Transitioned via pvg story deliver on 2026-08-20.

### proof
- [ ] Developer evidence block must remain authoritative above this contract.


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
- 2026-08-19T20:07:16Z dep_removed: was_blocked_by AF-6jta
- 2026-08-19T20:26:27Z dep_removed: was_blocked_by AF-pfbv
- 2026-08-20T14:43:59Z dep_added: blocked_by AF-wb16
- 2026-08-20T14:59:37Z dep_removed: was_blocked_by AF-wb16
- 2026-08-20T15:09:22Z dep_removed: was_blocked_by AF-o0rw
- 2026-08-20T15:12:47Z dep_removed: was_blocked_by AF-c17x
- 2026-08-20T16:00:28Z dep_removed: was_blocked_by AF-4wkn
- 2026-08-20T16:01:17Z status: open -> in_progress
- 2026-08-20T16:01:17Z auto-follows: linked to predecessor AF-iv8x
- 2026-08-20T16:01:17Z auto-follows: linked to predecessor AF-hb2f
- 2026-08-20T16:01:17Z auto-follows: linked to predecessor AF-8r8l
- 2026-08-20T16:01:17Z auto-follows: linked to predecessor AF-yse2
- 2026-08-20T16:01:17Z auto-follows: linked to predecessor AF-6jta
- 2026-08-20T16:01:17Z auto-follows: linked to predecessor AF-pfbv
- 2026-08-20T16:01:17Z auto-follows: linked to predecessor AF-wb16
- 2026-08-20T16:01:17Z auto-follows: linked to predecessor AF-o0rw
- 2026-08-20T16:01:17Z auto-follows: linked to predecessor AF-c17x
- 2026-08-20T16:01:18Z auto-follows: linked to predecessor AF-4wkn
- 2026-08-20T16:01:18Z claimed by dev-AF-vm0q
- 2026-08-20T16:19:13Z status: in_progress -> in_progress
- 2026-08-20T16:39:20Z status: in_progress -> closed

## Links
- Parent: [[AF-j5rz]]
- Was blocked by: [[AF-q5yh]], [[AF-iv8x]], [[AF-hb2f]], [[AF-8r8l]], [[AF-yse2]], [[AF-6jta]], [[AF-pfbv]], [[AF-wb16]], [[AF-o0rw]], [[AF-c17x]], [[AF-4wkn]]
- Follows: [[AF-iv8x]], [[AF-hb2f]], [[AF-8r8l]], [[AF-yse2]], [[AF-6jta]], [[AF-pfbv]], [[AF-wb16]], [[AF-o0rw]], [[AF-c17x]], [[AF-4wkn]]

## Comments

### 2026-08-19T15:02:56Z ada
BUG TRIAGE (Sr PM): amended this capstone's static verification IMPLEMENTATION/ACs in lockstep with AF-8r8l and AF-6jta to match the corrected release.yaml/appset-workloads.yaml contract (imageTag holds a sha256 digest, seeded per-app with a real resolvable value; appset-workloads.yaml binds digest: not tag:). Also added a dedicated regression check (item 4 negative assertion + item 7 self-validation regression #6) so a future revert of the digest: binding back to tag: is caught by the static suite before it ever reaches a live cluster. See AF-8r8l/AF-6jta comments for the full discovered-bug context (originally surfaced by AF-hb2f's deliver-only follow-up developer).

### 2026-08-19T19:56:52Z ada
BUG TRIAGE (Sr PM), param-path correction: amended this capstone's IMPLEMENTATION/ACs/CONSUMES in lockstep with AF-6jta's own deliver-only follow-up discovery -- the digest binds to .imageTag (top-level key in release.yaml), NOT .values.imageTag (values is an empty map in all 18 seeded files; that path aborts rendering under this ApplicationSet's own goTemplateOptions missingkey=error). Item 2's render check, item 3's cross-file contract check, item 4's negative assertion, item 7's self-validation regression list, and AC #3/#4/#6 are all amended to assert digest: "{{.imageTag}}" and to forbid tag: under BOTH the .imageTag and .values.imageTag paths (either wrong-field variant, under either path, is the same class of regression this suite must catch). Self-validation regression count raised from 7 to 8 to add the wrong-param-path-right-field variant (digest: "{{.values.imageTag}}") as its own distinct regression, since a suite that only catches the tag:-vs-digest field swap could still miss a path regression. AF-6jta's actual delivered appset-workloads.yaml already ships the corrected .imageTag path; this amendment only brings this capstone's own regression check into agreement with that delivered file (previously it was written to assert the now-superseded .values.imageTag literal, which would have caused this capstone's own suite to fail against the correct, already-delivered file). See AF-6jta's comments for full discovered-bug evidence.

### 2026-08-20T14:44:16Z ada
LOCKSTEP AMENDMENT (Sr PM bug triage, AF-wb16): a 4th distinct arr-stack drift point was found live during AF-o0rw -- apps/arr-stack/argocd/appset-workloads.yaml's OCI Helm source was missing the mandatory `chart:` field (repoURL carried an `oci://`-prefixed path with the chart name embedded instead), causing all 18 workload Applications to fail Argo CD spec validation (InvalidSpecError) on the real instance. Fixed forward by AF-wb16 (P0, not blocking any closed story); AF-wb16 is wired as a blocker of this capstone and of AF-o0rw's continuation. When this story's static suite is authored, fold in two more checks alongside the existing item-3/item-4 lists: (a) cross-file contract check -- appset-workloads.yaml's template.spec.source has repoURL with no oci:// prefix and a non-empty chart field; (b) negative assertion -- no oci:// substring anywhere under apps/arr-stack/argocd/appset-workloads.yaml. Self-validation (item 7) should add a 9th regression: reintroduce the oci://-prefixed repoURL with chart: removed, confirm the new assertion catches it. Not a required AC change by itself (this comment documents the fold-in so the eventual author doesn't have to re-derive it from AF-wb16), but should be treated as part of "all seven implementation items" once authored.

### 2026-08-20T16:20:46Z ada
DELIVERED: arr-stack static verification capstone.

Commit: `65ed8e0dbee71629f42911485178e897fcbb2c33` on `story/AF-vm0q`
File: `e2e/observability_test.rb` (extended in place -- no second test file, no fork of the AF-d66a sections)

## PROOF

### Command and result

```
$ ruby e2e/observability_test.rb
RESULT: PASS -- 589 assertions, 0 failures      (exit 0)
```

Produced from commit `65ed8e0dbee71629f42911485178e897fcbb2c33`, against the real, committed
`apps/arr-stack/` manifests. Ruby 2.6.10 (stock macOS), helm v4.2.4.

Pre-change baseline re-run from `65ed8e0~1` for comparison: `RESULT: PASS -- 150 assertions, 0 failures`.
Delta: **+439 assertions, 0 failures, 0 skipped, 0 warnings** (also clean under `ruby -w`).

There are no other test files in the repo (`find` for `*_test*`/`*.spec.*` returns only this file),
so this run IS the full suite -- nothing was skipped or scoped down. No `skipif`, env-var gate,
`xfail`, or conditional-skip construct exists anywhere in the file.

### Per-section assertion counts (new sections 10-15)

| Section | Assertions |
|---|---|
| 10. arr-stack structural / lint checks | 180 |
| 11. arr-stack helm template renders | 79 |
| 12. arr-stack cross-file contracts | 122 |
| 13. arr-stack negative assertions | 35 |
| 14. arr-stack repo-wide name collision check | 6 |
| 15. arr-stack project hard-rule / quality-gate checks | 17 |
| (pre-existing AF-d66a sections 1-9, unmodified) | 150 |

### `pvg verify`

```
$ pvg verify e2e/observability_test.rb
VERIFY: PASSED (1 files scanned, 0 issues)
```

### Acceptance criteria

| AC | Verdict | Evidence |
|---|---|---|
| 1. New `arr_stack` section covers all 7 implementation items (+ AF-wb16 fold-in) | PASS | Sections 10 (item 1), 11 (item 2), 12 (item 3 + fold-in a), 13 (item 4 + fold-in b), 14 (item 5), 15 (item 6); item 7 + fold-in c below |
| 2. Structural/lint + helm render checks pass, incl. corrected digest reference | PASS | 259 assertions in §10-11. `helm template` of the vendored Kargo chart renders the Project/Warehouse/3xStage/PromotionTask set for sonarr (hasDownloads=true) and prowlarr (false); `helm template` of the real `oci://ghcr.io/bjw-s-labs/helm/app-template` 4.x with the generated values renders `ghcr.io/hotio/sonarr@sha256:e029ce…` -- `@`, never `:sha256:` |
| 3. Cross-file contracts pass, incl. digest shape, `digest: "{{.imageTag}}"` binding, `seerr` roster, OCI repoURL/chart shape | PASS | §12a four-way roster agreement (table == workloads list == kargo list == `env/*/` glob); §12c all 18 `imageTag` values match `sha256:[0-9a-f]{64}`, `values` is `{}`, per-app stage trio byte-identical; §12d `digest` bound structurally to `{{.imageTag}}` with no `tag` key at all; §12g repoURL has no `oci://` prefix and `chart: app-template` is non-empty |
| 4. Negative assertions pass, incl. digest/tag + param path, overseerr, `oci://` | PASS | §13: no plex/qbittorrent/rflood/sabnzbd, no kargo-shared/CustomPromotionStep, no `overseerr` (case-insensitive), no `oci://` anywhere, no `tag: "{{.imageTag}}"` or `tag: "{{.values.imageTag}}"`, no `.values.imageTag` path at all, no `imageTag: release`, no `storageClassName`, no Stage `verification`/AnalysisTemplate, bootstrap byte-identical |
| 5. Repo-wide collision check + quality-gate check pass | PASS | §14 (28 generated names vs 30 discovered pre-existing fleet names, empty intersection); §15 (CreateNamespace=true on both appsets, no secrets, sync-wave + skip-file-rendering + authorized-stage all present, promote-loop guard) |
| 6. Self-validation with >=9 regressions, each caught by its specific assertion | PASS | **14** regressions, 14/14 caught by the named assertion -- table below |
| 7. Full extended suite: zero failures against real committed manifests | PASS | `589 assertions, 0 failures`, exit 0 |

### Self-validation (item 7 + AF-wb16 fold-in c): 14/14 regressions caught

Method: for each regression, back the target file up to scratch, introduce exactly ONE deliberate
defect, run the full suite, require that the **specific named assertion** appears in the `FAIL:`
output (not merely that something failed), restore from git, and re-confirm `git status` is clean.
Driver output archived; final state verified clean and back to `589 assertions, 0 failures`.

| # | Regression introduced | Caught by (specific assertion) | Total fails |
|---|---|---|---|
| R1 | rename one app in `appset-workloads.yaml`'s list ONLY (`sonarr`->`sonarrr`) | `arr/roster: appset-workloads list == the epic parameter table`; `… == appset-kargo list` | 7 |
| R2 | remove `+argocd:skip-file-rendering` from `warehouse.yaml` | `arr/chart: EVERY file under kargo-chart/ carries +argocd:skip-file-rendering` | 2 |
| R3 | delete `env/bazarr/staging/release.yaml` | `arr/release: exactly 18 release.yaml promotion targets exist`; `… full 6x3 cross-product` | 4 |
| R4 | hard-code `storageClassName: local-path` in the persistence block | `arr/scope: no storageClassName is hard-coded anywhere under apps/arr-stack/`; `arr/values …: no storageClassName in the rendered persistence block` | 3 |
| R5 | change `lidarr`'s image in `appset-kargo.yaml` ONLY | `arr/params lidarr: appset-kargo image matches the parameter table`; `… agree byte-for-byte on the image` | 2 |
| **R6** | **revert `digest: "{{.imageTag}}"` -> `tag: "{{.imageTag}}"`** (the original epic bug) | `arr/regress: no \`tag: "{{.imageTag}}"\` binding`; `arr/binding: app-template digest is bound to the top-level {{.imageTag}} parameter`; `arr/binding: the image block binds NO tag field at all`; `arr/values …: derived container image reference is digest-pinned` | 17 |
| **R7** | **reintroduce `overseerr`/`ghcr.io/hotio/overseerr` in `appset-kargo.yaml`** | `arr/scope: no \`overseerr\` reference anywhere (retired upstream image)`; `arr/roster: appset-kargo list == the epic parameter table` | 6 |
| **R8** | **wrong param path, right field: `digest: "{{.values.imageTag}}"`** | `arr/regress: the \`.values.imageTag\` param path appears nowhere`; `arr/binding: app-template digest is bound to the top-level {{.imageTag}} parameter` | 9 |
| **R9** | **reintroduce `repoURL: oci://…/app-template` with `chart:` removed (AF-wb16)** | `arr/oci: source.repoURL carries NO oci:// scheme prefix`; `arr/oci: source.chart is present and non-empty`; `arr/regress: no \`oci://\` substring anywhere in appset-workloads.yaml` | 7 |
| R10 | revert one `imageTag` to the literal tag-shaped `release` | `arr/regress: no \`imageTag: release\` tag-shaped seed survives`; `arr/regress: every imageTag is digest-shaped…`; `arr/release bazarr/staging: imageTag is a well-formed sha256 digest` | 4 |
| R11 | flip `prowlarr`'s `hasDownloads` away from the parameter table | `arr/params prowlarr: hasDownloads matches the parameter table` | 1 |
| R12 | drift the `authorized-stage` annotation from the name template | `arr/authz: authorized-stage annotation is <app>:<stage>`; `arr/authz: the name template and the annotation interpolate the same two tokens` | 4 |
| R13 | remove `sync-wave: "-1"` from the Kargo Project | `arr/chart: project.yaml carries argocd.argoproj.io/sync-wave "-1"`; `arr/gate: skip-file-rendering + sync-wave + authorized-stage are ALL present` | 4 |
| R14 | drop `CreateNamespace=true` from `appset-kargo.yaml` | `arr/gate: appset-kargo.yaml syncOptions includes CreateNamespace=true` | 1 |

R6/R8/R9 are the three production bug-triage regressions this capstone exists to guard, and each is
caught by a *distinct* assertion family -- R6 by the field check, R8 by the param-path check, R9 by
the OCI-shape check -- so no one of the three can mask another.

R11 and R14 each fire exactly one assertion, which is the precision evidence: the suite pinpoints
the broken contract rather than collapsing into a wall of noise.

### Notes on scope and honesty

- **Wiring**: this story's deliverable *is* the verification entry point -- `ruby e2e/observability_test.rb`,
  the same single command the AF-d66a epic gate already uses. It is wired by being the repo's only
  test file, at the path the completion gate scans, and it exercises the real committed manifests
  (not fixtures) plus the real upstream `app-template` chart through `helm template`. No mocks anywhere.
- **Diff budget overrun, declared**: the story budgeted ~150-260 added LOC; actual is **901 added lines
  (~600 code, ~300 comment/blank)** in 1 file, 0 new files. Driver: the AF-wb16 fold-in plus the full
  7-item scope across 6 sections and 439 assertions. Code-per-assertion is 1.4 vs the existing file's
  2.2, so the overrun is scope, not bloat. I trimmed the header prose once (-8 lines) but did not
  remove assertions to hit a line count. Flagging rather than hiding it.
- **`pvg gates` FAIL is pre-existing and not mine.** 15 duplication BLOCKs. I verified this properly
  rather than asserting it: I ran `pvg gates` with my file swapped back to its `65ed8e0~1` content and
  got byte-identical output (12.1% vs 12.0% total; same 15 files). `pvg gates` also resolves the
  project root, not this worktree, so it never saw my change either way. No BLOCK names
  `e2e/observability_test.rb`. See the DISCOVERED_BUG below for the one entry inside this epic.
- **`file_loc` WARN**: once merged, `e2e/observability_test.rb` is 1254 non-blank lines against a
  400-line warn threshold (warn, not block). Pre-existing at 463; this story pushes it further. If the
  team wants it under the threshold, splitting `e2e/` into `observability_test.rb` + `arr_stack_test.rb`
  is the natural fix -- but the story explicitly forbade a second test file, so I did not do it.
- **One network dependency, handled without a skip.** §11c renders through the real
  `oci://ghcr.io/bjw-s-labs/helm/app-template`, which is an external registry. It was reachable on this
  run and the assertions executed. If it is ever unreachable, the suite prints a `NOTE:` and the
  digest-vs-tag *outcome* is still asserted offline in §11b, which re-derives app-template's own
  `repository@digest` vs `repository:tag` rule -- so R6 and R8 are caught with or without network.
  Nothing is gated behind an env var and no assertion is ever collected-but-unexecuted.
- The OCI chart reference used by §11c is *derived from the manifest under test*
  (`oci://<repoURL>/<chart>`), so R9 breaks the render too, not just the structural check.
- `kargo-chart/templates/*.yaml` are Helm templates, so they are linted post-`helm template` render
  (per the story's own note) rather than parsed as raw YAML; that render is where `stages.yaml`'s
  multi-document shape is validated. `verification`/`AnalysisTemplate` are asserted absent
  *structurally on rendered docs* plus via key-anchored regexes, because both words appear in
  `stages.yaml`'s explanatory comments -- a prose-level grep would have false-positived on the very
  comment documenting their absence.
- Live-cluster checks remain out of scope by design (AF-o0rw/AF-c17x/AF-4wkn). Nothing here touches a cluster.

DISCOVERED_BUG:
  title: pvg duplication gate blocks on apps/arr-stack/argocd/appset-workloads.yaml (59 duplicated lines)
  context: `pvg gates` reports `[BLOCK] duplication apps/arr-stack/argocd/appset-workloads.yaml 59>50`,
    which will block the epic completion gate. This looks like a false positive against the DRY
    generator design itself: the file's six `list` elements are deliberately near-identical
    (name/image/port/hasDownloads leaves under one shared template), which is the entire point of
    the pattern this epic set out to prove. Collapsing them would defeat the design. The repo-wide
    total (12.0% > 10%) is likewise pre-existing and dominated by files outside this epic
    (Taskfile.yml 66, apps/akkoma/argocd/appset.yaml 53, apps/soju/kargo/stages.yaml 61, and 10
    fenced code blocks inside docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md).
    Verified pre-existing: gate output is byte-identical with this story's change reverted. Likely
    resolutions are a `gates.exclude` entry for docs plan files and generator list-element blocks, or
    raising `gates.duplication.min_lines` -- a settings decision, not a code fix, and not mine to make.
  affected_files: apps/arr-stack/argocd/appset-workloads.yaml, Taskfile.yml, apps/akkoma/argocd/appset.yaml,
    apps/soju/kargo/stages.yaml, docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
  discovered_during: AF-vm0q

## LEARNINGS

- **`dig_path` silently lies about Kubernetes annotation keys.** The harness's `dig_path` splits on
  `.`, so `'metadata.annotations.argocd.argoproj.io/sync-wave'` becomes four bogus segments and
  returns `nil` -- which reads as a *passing* absence check if you wrote the assertion the other way
  round. Every annotation this epic cares about (`argocd.argoproj.io/sync-wave`,
  `kargo.akuity.io/authorized-stage`) has dots in its key. I added an `arr_annotation` helper that
  fetches the map and indexes it directly. Any future story asserting on annotations in this repo
  needs the same, and any *existing* `dig_path` call with a dotted leaf key is suspect.
- **Grepping raw text for a forbidden word false-positives on the comment that documents its
  absence.** `stages.yaml` explains at length why it ships no `verification` block and no
  `AnalysisTemplate` -- so the obvious `grep -i verification` fires on the proof of correctness.
  The fix that generalizes: assert on parsed/rendered structure, and where a text check is still
  wanted, anchor it to YAML key syntax (`/^\s*verification:/`) rather than prose.
- **Mutation-testing the test suite caught a real defect in my own work, and pure line-counting
  would not have.** My first pass had a hard-coded `27` expected generated names where the templates
  produce 28 -- the suite failed immediately on real manifests. Rewriting it as a derived sum
  (`4 + apps * (1 + stages)`) removed the magic number. Separately, requiring each regression to fire
  a *named* assertion (not just "something failed") is what proves R6/R8/R9 are independently guarded;
  R6 alone trips 17 assertions, so "a failure occurred" would have told me nothing about which
  contract actually holds the line.
- **Two of the three epic regressions are only catchable structurally, not textually.** `digest:` vs
  `tag:` and `.imageTag` vs `.values.imageTag` both live inside a `values: |` *block scalar*, i.e.
  a YAML string, so they are invisible to normal document traversal. Reading that string back as YAML
  (drop the `{{- if}}`/`{{- end}}` lines, quote the bare leaf actions) turns the binding into
  something assertable field-by-field, which is strictly stronger than a regex and survives reformatting.
- **Deriving the epic base commit from history beats hard-coding a SHA.** The bootstrap byte-identity
  check needs a baseline; `parent of the oldest commit touching apps/arr-stack/` is stable under later
  merges and even under a squash-to-main, whereas a pinned SHA rots the first time the branch is
  rebased. Same instinct as globbing instead of listing app names.
- **Gate output can be about a directory you are not in.** `pvg gates` resolved the project root
  rather than my worktree, so its FAIL had nothing to do with my change -- and the only way to know
  that was to swap my file back to its parent commit's content and diff the output. Worth doing before
  either claiming a gate failure is pre-existing or accepting blame for it.
