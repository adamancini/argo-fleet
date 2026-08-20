---
id: AF-wb16
title: "Bug: arr-stack workload Applications fail Argo CD spec validation -- OCI repoURL cannot embed chart name, chart: field is mandatory"
status: closed
priority: 0
type: bug
parent: AF-j5rz
created_at: 2026-08-20T14:43:53Z
created_by: ada
updated_at: 2026-08-20T14:59:38Z
content_hash: "sha256:4764ab7c2040ec8301c35643c9bc46bbd9238f9b4e0c6726fddaa26bb527a8f8"
assignee: dev-AF-wb16
follows: [AF-pfbv, AF-6jta]
labels: [accepted]
closed_at: 2026-08-20T14:59:37Z
close_reason: "Accepted: explicit chart field fixes InvalidSpecError on 18 workload Applications. Verified independently: diff dda74d9..HEAD is exactly 1 file +2/-1 touching only repoURL/chart lines; 63efac6..HEAD log for stages.yaml and the design-spec doc is empty (branch never touched them); merge-base --is-ancestor confirms neither main-only commit is ancestor of HEAD; fixed file confirms repoURL: ghcr.io/bjw-s-labs/helm, chart: app-template, targetRevision: 4.x unchanged, zero oci:// occurrences; bootstrap/*.yaml untouched; re-ran ruby e2e/observability_test.rb -- 150/150, 0 failures; independently confirmed both Argo CD citations (util/argo/argo.go:610/613, reposerver/repository/repository.go:1225-1226); pvg verify and pvg gates both clean."
---

## Description
Description:
`apps/arr-stack/argocd/appset-workloads.yaml` (merged to `main` via AF-6jta, commit `63efac6`) sets its 18 workload Applications' `template.spec.source` to `repoURL: oci://ghcr.io/bjw-s-labs/helm/app-template` with no `chart:` field. Confirmed live against the real shared `demo1`/`demo2`/`kargo` instance during AF-o0rw's dispatcher-run verification: Argo CD rejects every one of the 18 generated Applications with `InvalidSpecError -- spec.source.repoURL and either spec.source.path or spec.source.chart are required`. Fix: drop the `oci://` scheme from `repoURL` and add an explicit `chart: app-template` field -- the same shape this repo's own live-working `apps/akkoma/argocd/appset.yaml` already uses for its OCI source.

DISCOVERED DURING:
AF-o0rw (dispatcher-run, human-gated live verification of the epic's merge to `main`). Step 3 (wrapper Application health) and Step 4 (ApplicationSet child counts) both passed cleanly -- `argocd-arr-stack` wrapper Synced/Healthy, `arr-stack-workloads` generated exactly 18 children, `arr-stack-kargo` generated exactly 6, all named through `seerr` (confirming this epic's prior overseerr-rename and digest-binding fixes are correct on the real instance). Step 5 ("confirm nothing broken") is where this surfaced: all 18 `arr-<app>-<stage>` workload Applications show `Sync Status: Unknown` / `Health Status: Unknown` with an `InvalidSpecError` condition. The 6 `kargo-arr-*` Applications are unaffected and remain Synced/Healthy.

This is a clean validation-time rejection, not a broken deployment: Argo CD refuses to even attempt a sync when the spec is invalid, so nothing was actually created for any of the 18 Applications -- no pods, no PVCs, no partial state. Safe and fully reversible by this fix; not a live incident requiring rollback.

SYMPTOMS:
- `argocd app get arr-sonarr-dev` (and all 17 sibling workload Applications) shows `Sync Status: Unknown`, `Health Status: Unknown`.
- Condition: `InvalidSpecError -- spec.source.repoURL and either spec.source.path or spec.source.chart are required`.
- The 6 `kargo-arr-*` Kargo pipeline Applications are unaffected (Synced/Healthy) -- this is isolated to the workload half of the design (`appset-workloads.yaml`), not the Kargo half (`appset-kargo.yaml`).

EVIDENCE:
- Live rendered `spec.source` for e.g. `arr-sonarr-dev`, confirmed via `argocd app get arr-sonarr-dev -o yaml` during AF-o0rw:
  ```yaml
  source:
    repoURL: oci://ghcr.io/bjw-s-labs/helm/app-template
    targetRevision: "4.x"
    helm: {values: "..."}
  ```
  No `chart:` field, no `path:` field. This matches `appset-workloads.yaml`'s committed `template.spec.source` exactly (see `apps/arr-stack/argocd/appset-workloads.yaml` lines 115-118 as merged by AF-6jta) -- not a rendering fluke, the file itself is wrong.
- Argo CD source, verified directly against a local clone (`~/src/github.com/argoproj/argo-cd`), not guessed:
  - `util/argo/argo.go:598-614` (`validateSourcePermissions`, single-source branch): `if source.RepoURL == "" || (source.Path == "" && source.Chart == "")` fails with the exact `InvalidSpecError` message above whenever both `path` and `chart` are empty. This check is unconditional -- there is no special case for an `oci://`-prefixed `repoURL`, and no code path treats "chart name embedded in the OCI URL's path" as satisfying the requirement.
  - `reposerver/repository/repository.go:1225-1226`: Argo CD does `strings.TrimPrefix(r.Repository, "oci://")` with the comment "trimming oci:// prefix since it is currently not supported by Argo CD (OCI repos just have no scheme)" -- `repoURL` for an OCI Helm source is expected to be the bare registry+namespace host/path with NO `oci://` scheme, and the chart name is supplied via the separate, mandatory `chart:` field, never appended to `repoURL`'s path.
- This repo's own already-live, already-working `akkoma` Application (`apps/akkoma/argocd/appset.yaml`, live-verified via `argocd app get akkoma-dev -o yaml` in a prior epic) proves the correct shape directly:
  ```yaml
  repoURL: ghcr.io/adamancini/charts    # no oci:// scheme
  chart: akkoma                          # explicit, separate field
  targetRevision: 0.6.1
  ```
  This is exactly the shape `appset-workloads.yaml` should have used and did not.
- Root cause of the wrong assumption: `docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md`'s own snippet stated "oci:// source: chart name is part of the path, so `chart:` stays unset, per onboarding.md's documented rule for OCI sources." That "onboarding.md rule" is real (`docs/onboarding.md`'s step 1, "`chart.name` must stay unset for `oci://` URLs") but it describes Kargo's `Warehouse` `chart:` subscription schema (a distinct object from an Argo CD `Application.spec.source`), where the rule is correct: for an OCI registry, each `repoURL` is dedicated to one chart, so Kargo's separate `name` field must stay unset. The design spec conflated the two unrelated schemas and carried Kargo's rule over into the Argo CD Application source, where the opposite is true (a separate, mandatory `chart:` field is always required for OCI Helm sources, regardless of `oci://` prefixing). `onboarding.md` itself does not state the wrong rule as a general Argo CD convention -- it is correctly scoped to the Kargo Warehouse subscription it documents; this triage pass added a clarifying note there distinguishing the two schemas so a future onboarder doesn't repeat the same conflation (see Links/Notes below).

ROOT CAUSE (confirmed, not a hypothesis):
1. `apps/arr-stack/argocd/appset-workloads.yaml`'s `template.spec.source` block sets only `repoURL: oci://ghcr.io/bjw-s-labs/helm/app-template` and `targetRevision: 4.x` -- no `chart:` field.
2. Argo CD's single-source spec validation (`util/argo/argo.go:598-614`) unconditionally requires `path` or `chart` to be non-empty; an `oci://`-prefixed `repoURL` does not satisfy this by itself.
3. The design spec's own rationale comment for this omission misapplied `docs/onboarding.md`'s Kargo-Warehouse-specific "chart name stays unset for oci:// URLs" rule to the unrelated Argo CD Application source schema.

CONFIG (if relevant):
Not applicable -- no live cluster config involved; this is a static manifest edit to an already-merged file. No new secrets, env vars, or credentials are introduced (this OCI registry pull is the same unauthenticated `ghcr.io` pull pattern `apps/akkoma/argocd/appset.yaml` already uses live).

KEY FILES:
Modify: `apps/arr-stack/argocd/appset-workloads.yaml` (`template.spec.source` block only). No other file needs a code change -- `apps/arr-stack/argocd/appset-kargo.yaml`, `apps/arr-stack/argocd/kargo-chart/`, and all 18 `apps/arr-stack/env/*/*/release.yaml` files are unaffected (this defect is isolated to the workload ApplicationSet's Helm chart source, not the Kargo pipeline generator or the promotion-target contract files).

IMPLEMENTATION:
In `apps/arr-stack/argocd/appset-workloads.yaml`, change the `template.spec.source` block from:
```yaml
      source:
        repoURL: oci://ghcr.io/bjw-s-labs/helm/app-template
        targetRevision: 4.x
        helm:
          values: |
            ...
```
to:
```yaml
      source:
        repoURL: ghcr.io/bjw-s-labs/helm
        chart: app-template
        targetRevision: 4.x
        helm:
          values: |
            ...
```
Three changes only: (1) `oci://` scheme prefix removed from `repoURL`, (2) `app-template` removed from `repoURL`'s path (it was the final path segment), (3) a new `chart: app-template` field added. `targetRevision: 4.x` is unchanged. The entire `helm.values` block (the multi-line string with `defaultPodOptions`, `controllers`, `service`, `ingress`, `persistence`, and the `hasDownloads` conditional) is byte-identical -- untouched by this fix. The matrix generator's `list`/`git` generators, the `template.metadata` block, `destination`, and `syncPolicy` are all byte-identical -- untouched.

USER INTENT:
The user needs to trust that every workload Application this design generates is a spec Argo CD will actually accept and reconcile -- not just a manifest that looks plausible under `helm template`/static YAML linting, which is exactly why this defect passed every static check in this epic (AF-6jta's own verification, this repo's `e2e/observability_test.rb` suite) and was only caught by a real Argo CD control plane's spec validation. The fix must be verifiable without a live cluster touch, the same static-verification discipline this epic has used throughout -- by statically confirming the corrected spec satisfies the exact validation rule read directly from Argo CD's source, not by re-guessing or re-trusting the original (wrong) assumption a second time.

OUT OF SCOPE:
- Re-running AF-o0rw's Step 3-5 live checks against the real shared instance to confirm the 18 workload Applications actually reach `Synced`/`Healthy` after this fix merges -- that re-verification happens after this story closes and merges, run by the dispatcher (continuing AF-o0rw), not as part of this story's own scope. This story is static-only, same as every other developer-claimable story in this epic.
- Reopening AF-6jta (the story that introduced this defect) -- this is a forward-fix on an already-merged file, matching this epic's established pattern (AF-yse2 patched AF-hb2f's merged files the same way) of never reopening closed/accepted stories.
- Any change to `apps/arr-stack/argocd/appset-kargo.yaml`, `kargo-chart/`, or any `release.yaml` file -- none are affected by this defect.
- Any change to `bootstrap/*.yaml` -- standing epic-wide negative assertion, unaffected by this fix.
- Correcting every other historical inaccuracy in `docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md` beyond what this triage pass already applied directly (see Notes/Comments) -- the doc has been corrected in place for this defect plus three pre-existing ones (tag/digest, overseerr/seerr, param-path/indentation) and given a top-of-file historical-document disclaimer; it is not this story's scope to re-audit it further.

DIFF BUDGET:
1 file modified (`apps/arr-stack/argocd/appset-workloads.yaml`), 0 files added/deleted. Expect exactly 3 changed lines in the `template.spec.source` block (repoURL value change, one new `chart:` line); everything else in the file is byte-identical to the pre-fix version.

PRODUCES:
- `apps/arr-stack/argocd/appset-workloads.yaml` -> corrected `template.spec.source` block
    spec: `repoURL: ghcr.io/bjw-s-labs/helm` (no `oci://` scheme), `chart: app-template` (new, explicit field), `targetRevision: 4.x` (unchanged), `helm.values` block unchanged
    source: this bug's own AC #1-#3, verified against Argo CD source (`util/argo/argo.go:598-614`, `reposerver/repository/repository.go:1225-1226`) and this repo's live-working `apps/akkoma/argocd/appset.yaml` precedent

TESTING:
Static only -- no live cluster touch required or permitted for this story (matching every other developer-claimable story in this epic; live re-verification is out of scope, see above).
1. Statically substitute the matrix generator's params for at least one `hasDownloads: true` app/stage (e.g. `sonarr`/`dev`) and one `hasDownloads: false` app/stage (e.g. `prowlarr`/`staging`) into the corrected `template.spec.source` block by hand and confirm the resulting `spec.source` YAML has: a non-empty `chart` field, a `repoURL` value with no `oci://` prefix, and no `path` field -- i.e., it satisfies Argo CD's `validateSourcePermissions` single-source rule (`RepoURL != "" && (Path != "" || Chart != "")`) read directly from `util/argo/argo.go:598-614`.
2. Repo-wide grep confirming `apps/arr-stack/argocd/appset-workloads.yaml` contains no `oci://` substring anywhere after the fix, and contains exactly one `chart:` line with value `app-template`.
3. Diff the fixed file against the pre-fix committed version (`git show 63efac6:apps/arr-stack/argocd/appset-workloads.yaml`) and confirm the diff touches only the `repoURL`/`chart` lines inside `template.spec.source` -- everything else (matrix generators, `helm.values` block including the `hasDownloads` conditional, `template.metadata`, `destination`, `syncPolicy`) is byte-identical.
4. Regression: run the existing static suite, `ruby e2e/observability_test.rb`, and confirm it still passes with the same pass count as before this change (this story does not add a new permanent assertion to that suite -- AF-vm0q, the epic's capstone, owns adding the permanent regression check for this specific invariant; this story's own static checks above are its own delivery evidence).

Acceptance Criteria:
1. [Ubiquitous] `apps/arr-stack/argocd/appset-workloads.yaml`'s `template.spec.source.repoURL` is `ghcr.io/bjw-s-labs/helm`, with no `oci://` scheme prefix.
2. [Ubiquitous] `template.spec.source` carries an explicit `chart: app-template` field.
3. [Ubiquitous] `targetRevision: 4.x` and the entire `helm.values` block (including the `hasDownloads` conditional in both branches) are byte-identical to the pre-fix version -- no unrelated changes.
4. [Event] Hand-substituting the matrix/git-files params for at least one `hasDownloads: true` app/stage and one `hasDownloads: false` app/stage produces a rendered `spec.source` with a non-empty `chart` and a `repoURL` with no `oci://` prefix, satisfying Argo CD's `validateSourcePermissions` single-source rule confirmed directly against `util/argo/argo.go:598-614`.
5. [Unwanted] The file contains no `oci://` substring anywhere after the fix.
6. [Unwanted] No field outside `template.spec.source`'s `repoURL`/`chart` lines changes -- diff against the pre-fix committed file (`63efac6`) touches only those lines.
7. [Unwanted] `bootstrap/*.yaml` is not modified by this fix (standing epic-wide negative assertion).
8. Regression: `ruby e2e/observability_test.rb` passes with 0 failures after the fix.
9. Root cause (Argo CD's unconditional single-source validation rule, and the design doc's conflation of Kargo Warehouse vs. Argo CD Application source schemas) is documented in the commit message, citing the two Argo CD source locations verified above.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory -- ApplicationSet/Application source conventions, OCI Helm source shape), devops-toolkit:yaml-kubernetes-validator, devops-toolkit:helm-chart-developer

## Acceptance Criteria


## Design


## Notes


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
- 2026-08-20T14:43:59Z dep_added: blocks AF-vm0q
- 2026-08-20T14:44:00Z dep_added: blocks AF-o0rw
- 2026-08-20T14:47:33Z status: open -> in_progress
- 2026-08-20T14:47:34Z auto-follows: linked to predecessor AF-pfbv
- 2026-08-20T14:47:34Z claimed by dev-AF-wb16
- 2026-08-20T14:55:27Z status: in_progress -> in_progress
- 2026-08-20T14:55:27Z auto-follows: linked to predecessor AF-6jta
- 2026-08-20T14:59:37Z status: in_progress -> closed
- 2026-08-20T14:59:37Z dep_removed: no_longer_blocks AF-vm0q
- 2026-08-20T14:59:37Z dep_removed: no_longer_blocks AF-o0rw

## Links
- Parent: [[AF-j5rz]]
- Follows: [[AF-pfbv]], [[AF-6jta]]

## Comments

### 2026-08-20T14:55:20Z ada
DELIVERED: AF-wb16 -- explicit `chart:` field on the arr-stack workload source

COMMIT: 01a49e4e1f13b4d49ae5034adf3874c11d4c8db8 (branch story/AF-wb16, pushed)
BASE:   dda74d9 (epic/AF-j5rz)
DIFF:   1 file changed, 2 insertions(+), 1 deletion(-) -- exactly the 3 line-level
        changes the story specified. `git diff dda74d9..HEAD --stat` =
        apps/arr-stack/argocd/appset-workloads.yaml | 3 ++-

THE CHANGE (apps/arr-stack/argocd/appset-workloads.yaml, template.spec.source):
-        repoURL: oci://ghcr.io/bjw-s-labs/helm/app-template
+        repoURL: ghcr.io/bjw-s-labs/helm
+        chart: app-template
         targetRevision: 4.x

PROOF
=====
All results produced at SHA 01a49e4 with a clean working tree.

Commands run (all synchronous, static only -- no live cluster touch):
  1. git -C <wt> show 63efac6:apps/arr-stack/argocd/appset-workloads.yaml  (baseline capture)
  2. diff <baseline> <worktree file>                     -> IDENTICAL before edit
  3. sed -n '115,118p' <file>                            -> AC1, AC2
  4. grep -n 'oci://' <file>                             -> exit 1, 0 matches (AC5)
  5. grep -cE '^[[:space:]]*chart:' <file>               -> 1  (AC2)
  6. git -C <wt> diff 63efac6 --numstat -- <file>        -> 2  1  (AC6)
  7. diff of unchanged regions + shasum -a 256           -> AC3
  8. ruby scratchpad/ac4_handsub.rb <file>               -> AC4 PASS (exit 0)
  9. ruby e2e/observability_test.rb                      -> 150 assertions, 0 failures, exit 0 (AC8)
 10. pvg verify <file> --format text                     -> VERIFY: PASSED (0 issues)
 11. pvg verify <wt> --check-e2e --format text           -> E2E CHECK: PASSED (1 file)

TEST / ASSERTION COUNTS
  e2e/observability_test.rb  POST-FIX:  150 assertions, 0 failures, exit 0
  e2e/observability_test.rb  BASELINE:  150 assertions, 0 failures  (run against the
      `main` checkout, which still carries the pre-fix file; the test file itself is
      byte-identical between main and this branch --
      sha256 79af15bf30d7f97c461a4fbf5cc7491a6a24d8562e7cd723a9cc44205a206d72 on both)
  => 150/150 before, 150/150 after. No new failures, no new warnings, no skipped tests.
  AC4 hand-substitution harness: 14 assertions across 2 rendered Applications, 0 failures.
  pvg verify: 0 issues. Note it reports "0 files scanned" -- .yaml is not a recognized
  source extension for the scanner, so it is a no-op on this change by design (this is a
  manifest-only repo); the e2e suite is the real static gate and it is green.

ACCEPTANCE CRITERIA VERIFICATION
| # | AC | Result | Evidence |
|---|----|--------|----------|
| 1 | repoURL is `ghcr.io/bjw-s-labs/helm`, no `oci://` prefix | PASS | line 116 of file; ruby YAML load reports repoURL="ghcr.io/bjw-s-labs/helm" |
| 2 | explicit `chart: app-template` present | PASS | line 117; `grep -cE '^\s*chart:'` = 1, value `app-template`; YAML source keys = ["repoURL","chart","targetRevision","helm"] |
| 3 | targetRevision 4.x + entire helm.values byte-identical | PASS | lines 1-115 diff-clean vs 63efac6; lines 117..EOF (pre) vs 118..EOF (post) diff-clean AND identical sha256 4170a28c95d655216f5c7ace246fa9f1d391739ed0895f6bee9373c6c785f244 -- covers targetRevision, both hasDownloads branches, destination, syncPolicy |
| 4 | hand-substituted true/false hasDownloads specs satisfy Argo CD's rule | PASS | see AC4 detail below -- 0 conditions for both |
| 5 | no `oci://` substring anywhere in the file | PASS | `grep -n 'oci://'` exit 1, 0 matches |
| 6 | diff vs 63efac6 touches only the repoURL/chart lines | PASS | numstat 2/1; the single diff hunk is @@ -113,7 +113,8 @@ and contains only the repoURL replacement + the new chart line |
| 7 | bootstrap/*.yaml not modified | PASS | `git diff 63efac6 --name-only -- bootstrap/` = 0 files; my commit's own file list is 1 file |
| 8 | e2e/observability_test.rb passes, 0 failures | PASS | 150 assertions, 0 failures, exit 0 -- identical to pre-fix baseline |
| 9 | root cause documented in commit message w/ both Argo CD citations | PASS | commit 01a49e4 body cites util/argo/argo.go:599-617 (rule transcribed) and reposerver/repository/repository.go:1225-1226 (oci:// TrimPrefix + its comment), plus the Kargo-Warehouse-vs-Application schema conflation |

AC4 DETAIL -- hand-substitution against the real validation rule
I transcribed Argo CD's single-source check verbatim from my local clone
(~/src/github.com/argoproj/argo-cd, rev 21804a2acfe096ed748d3309c25b4b1211b1d912):

  util/argo/argo.go:599  func validateSourcePermissions(source, hasMultipleSources)
  util/argo/argo.go:610      if source.RepoURL == "" || (source.Path == "" && source.Chart == "")
  util/argo/argo.go:613          Message: "spec.source.repoURL and either spec.source.path or spec.source.chart are required"
  reposerver/repository/repository.go:1225-1226
                             // trimming oci:// prefix since it is currently not
                             // supported by Argo CD (OCI repos just have no scheme)
                             Repo: strings.TrimPrefix(r.Repository, "oci://")

(Story cited argo.go:598-614; the exact current lines are 599-617 with the
single-source branch at 610 and the message at 613 -- same code, same rule.)

Then I hand-substituted the real matrix + git-files params, taking imageTag from the
actual committed release.yaml files, and rendered template.spec.source:

  arr-sonarr-dev        (hasDownloads=true,  imageTag sha256:e029ce19...)
  arr-prowlarr-staging  (hasDownloads=false, imageTag sha256:fd65c1cb...)

Both rendered to:
    source:
      repoURL: ghcr.io/bjw-s-labs/helm
      chart: app-template
      targetRevision: 4.x
Checks on each: chart non-empty PASS / repoURL has no oci:// prefix PASS / no `path`
field on source PASS / repoURL non-empty PASS / validateSourcePermissions returns 0
conditions PASS. The rendered helm.values re-parses as YAML in both cases, with
persistence keys ["config","downloads"] for sonarr and ["config"] for prowlarr --
confirming the hasDownloads conditional still chomps correctly on both branches --
and image.digest (not image.tag) carries the sha256.

NEGATIVE CONTROL (the check discriminates, it does not merely pass):
The same harness run against the pre-fix file (git show 63efac6:...) FAILS both cases
and returns, verbatim:
  ["InvalidSpecError: spec.source.repoURL and either spec.source.path or spec.source.chart are required"]
which is character-for-character the condition AF-o0rw observed live on all 18
Applications. So the harness reproduces the real defect and clears it after the fix.

DIFF PROVENANCE NOTE (for the acceptor)
`git diff main --name-only` from this branch lists three files, which looks like scope
creep but is not. `apps/akkoma/kargo/stages.yaml` and
`docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md` are MAIN-ONLY commits
(3b5fb78, cb8bf2e) that landed after this branch's base; `git merge-base --is-ancestor`
confirms neither is an ancestor of my HEAD, and `git log 63efac6..HEAD -- <those files>`
is empty -- this branch never touched them. My branch is simply behind main on them.
Authoritative scope check: `git diff dda74d9..HEAD --stat` = 1 file, +2/-1.

OUT OF SCOPE, NOT DONE (per the story)
No live cluster was touched. Confirming the 18 workload Applications actually reach
Synced/Healthy is AF-o0rw's continuation, run by the dispatcher after this merges.
No permanent regression assertion was added to e2e/observability_test.rb -- AF-vm0q
owns that.

DISCOVERED BUGS: none. No errors or warnings appeared in any command output.

LEARNINGS
=========
- Transcribing the upstream validation predicate into a throwaway harness and running
  it against BOTH the pre-fix and post-fix file is worth far more than asserting the
  post-fix file looks right. The pre-fix run reproduced the live InvalidSpecError string
  character-for-character, which upgrades "my fix satisfies the rule I read" into "my
  harness reproduces the real failure and my fix clears it" -- without a cluster.
- Byte-identity claims (AC3) are much stronger as a sha256 over the unchanged region
  than as a visual diff read. Splitting the file at the edit boundary (pre 117..EOF vs
  post 118..EOF) and hashing both halves proves the untouched tail in one line, and it
  would have caught an accidental whitespace change that eyeballing a diff hunk misses.
- Beware `git diff main` as a scope check on a branch whose base is behind main: it
  reported 3 changed files for a 1-file commit. `git diff <base>..HEAD` plus
  `merge-base --is-ancestor` is the honest scope check, and the difference is worth
  pre-empting in the delivery note or the acceptor will read it as scope creep.
- The `oci://` trap is a schema-conflation bug, not a typo: Kargo's Warehouse chart
  subscription genuinely wants the chart name unset for an OCI repoURL, and an Argo CD
  Application.spec.source genuinely requires the opposite. Both rules are correct in
  their own schema. Any doc stating one should name the schema it applies to, or the
  next reader will carry it across.
- pvg verify is a no-op on .yaml (0 files scanned) in this manifest-only repo, so it
  cannot be the pre-delivery gate here -- the Ruby e2e suite is. Worth saying explicitly
  in proof rather than letting "VERIFY: PASSED" imply coverage it does not have.
