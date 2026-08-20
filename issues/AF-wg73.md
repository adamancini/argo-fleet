---
id: AF-wg73
title: "Clean up pre-existing pvg gates repo-wide duplication findings"
status: in_progress
priority: 3
type: task
created_at: 2026-08-07T19:14:07Z
created_by: ada
updated_at: 2026-08-20T16:39:21Z
content_hash: "sha256:05252f677f1552a810eddda2d0aea84cf2d45ab002c9883a949235a5112f9a59"
assignee: dev-AF-wg73
---

## Description
Description:
`pvg gates` fails repo-wide with ~14-15 findings when run unscoped, on `main` and on every branch alike. This is pre-existing duplication debt, not a regression from any specific epic -- flagged here purely so it is not lost, per the discovering developer's explicit note not to block or attach it to any in-flight epic's completion.

Context:
Discovered by AF-7u8n (capstone verification story of epic AF-d66a) while confirming that epic's own scoped `pvg gates` runs were clean. The developer verified this predates AF-d66a entirely, and is not asking for it to be cleaned up now:

```
pvg gates                              => FAIL (14 block, 0 warn, 0 skipped)   # epic/AF-d66a branch
pvg gates  (pristine origin/main clone) => FAIL (15 block, 0 warn, 0 skipped)  # SAME findings, confirms pre-existing
pvg gates --changed origin/main         => PASS (0 warn, 0 skipped)            # AF-d66a's own diff is clean
pvg gates --changed origin/epic/AF-d66a => PASS (no changed files to scan)     # AF-7u8n's own diff is clean
```

The one-fewer-block delta between the two unscoped runs (14 vs 15) is not an epic fix; it was not investigated further since scoped runs already proved the epic introduces zero new findings.

Affected files (per the discovering developer's report, not independently re-verified by this triage pass -- confirm findings are still current before starting):
- `Taskfile.yml`
- `apps/akkoma/argocd/appset.yaml`
- `apps/soju/kargo/stages.yaml`
- `docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md`

USER INTENT:
No user request exists for a repo-wide `pvg gates` cleanup. This entry exists purely as a paper trail so the debt is visible in the backlog rather than only living in a closed epic's capstone comment thread, where it would be easy to lose. It is explicitly NOT gating epic AF-d66a's completion and has no parent epic.

IMPLEMENTATION:
Not scoped or designed by this triage pass -- deliberately left open for whoever picks this up to investigate `pvg gates`' specific duplication findings in each affected file and decide the right fix per file (likely de-duplicating repeated blocks/config, not a single mechanical change across all four).

KEY FILES:
`Taskfile.yml`, `apps/akkoma/argocd/appset.yaml`, `apps/soju/kargo/stages.yaml`, `docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md` (per AF-7u8n's report; re-run `pvg gates` unscoped at pickup time to get the current, authoritative finding list -- do not assume this list is still exhaustive or accurate).

OUT OF SCOPE:
- Any change to epic AF-d66a or its stories -- this debt predates that epic and must not be conflated with it.
- Investigating whether the 14 vs 15 count delta between branches is meaningful -- not requested, not investigated.

DIFF BUDGET:
Unknown until scoped -- likely small per-file de-duplication fixes. Whoever picks this up should re-run `pvg gates` unscoped first to size the actual work before estimating.

TESTING:
`pvg gates` (unscoped) exits clean (0 block, 0 warn) after the fix, or every remaining finding is explicitly justified as a false positive in the closing comment.

Acceptance Criteria:
1. [Ubiquitous] `pvg gates` run unscoped from repo root exits with 0 block findings (or each remaining block finding is documented as a deliberate false positive with rationale).
2. Each of the 4 files identified above is re-examined for the specific duplication finding(s) `pvg gates` reports against it at pickup time (not assumed identical to AF-7u8n's list).
3. No functional behavior change is introduced to `Taskfile.yml`, `apps/akkoma/argocd/appset.yaml`, or `apps/soju/kargo/stages.yaml` as a side effect of de-duplication -- this is a lint/gates cleanup, not a refactor of behavior.
4. Confirmed via `pvg gates --changed origin/main` before and after that this cleanup's own diff introduces no new findings.

MANDATORY SKILLS TO REVIEW:
None identified (gates/lint cleanup, no framework-specific pattern involved).

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-19T15:59:16Z status: open -> in_progress
- 2026-08-19T15:59:16Z claimed by dev-AF-wg73
- 2026-08-19T16:00:14Z status: in_progress -> open
- 2026-08-19T16:00:14Z released by ada
- 2026-08-20T16:39:21Z status: open -> in_progress
- 2026-08-20T16:39:21Z claimed by dev-AF-wg73

## Links


## Comments
