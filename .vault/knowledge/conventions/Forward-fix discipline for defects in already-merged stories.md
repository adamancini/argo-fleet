---
type: convention
project: argo-fleet
status: active
actionable: pending
epic: AF-j5rz
created: 2026-08-20
---

# Forward-fix discipline for defects found in already-merged/closed stories

## Pattern observed
AF-j5rz found and fixed forward THREE real defects in already-closed, already-merged stories (AF-yse2 patching AF-hb2f's merged `appset-kargo.yaml`/`appproject.yaml`; AF-6jta's own bug-triage amendments to AF-8r8l's and its own body; AF-wb16 patching AF-6jta's merged `appset-workloads.yaml`), plus a chain of story-body amendments cascading corrections through AF-8r8l -> AF-6jta -> AF-vm0q as each new fact was discovered. In every case, the closed/accepted story was **never reopened**; a new bug ticket or a direct amendment to a still-open downstream story's own body carried the fix instead.

This consistently worked well: it kept git history honest (a merged commit's diff reflects what was actually reviewed and accepted at the time), avoided re-litigating already-accepted work, and let dependency wiring (`nd dep add <blocked> <blocker>`) enforce the corrected sequencing (e.g., AF-6jta was hard-blocked on AF-yse2 so the roster-rename landed before the file that cross-checks against it).

## Sequencing failure mode observed once
AF-4wkn's own story header text said it assumed "AF-vm0q and AF-c17x are both complete," but the actual `nd` dependency graph (and the epic's own stated design intent recorded on AF-vm0q's body: "capstone... closes LAST") had AF-vm0q `blocked_by` AF-4wkn, not the reverse -- following the header literally would have required AF-vm0q to run before a dependency that didn't yet exist, an impossible ordering. The prose was a copy-paste artifact from AF-c17x's equivalent precondition line, never updated for AF-4wkn's own position in the chain. The developer reasoned past the prose and followed the actual dependency graph, correctly, but flagged the inconsistency rather than silently fixing it.

## A related, more serious failure caught only by a second pass
A Sr PM triage comment claimed (2026-08-19T19:58:28Z, on AF-j5rz) that the design spec doc had been "corrected in place" for three accumulated defects. A later pass (2026-08-20T14:44:28Z) independently re-verified the doc's actual git history and found **the claim was false** -- the doc had exactly one commit since authoring, and none of the three claimed fixes were present on disk. This was only caught because a subsequent triage pass happened to check the file's real state rather than trusting the prior comment.

## Actionable guidance
- Continue the forward-fix-only convention for closed/accepted stories in this repo; it is working and should be the default assumption for any future epic's bug triage.
- When a story's own header/body prose states a precondition ("assumes X and Y are complete"), that prose is not authoritative if it conflicts with the actual `nd` dependency graph -- prefer `nd dep tree`/`pvg nd path` over story prose when the two disagree, and treat the disagreement itself as worth a one-line flag (not a silent override) so a future reader isn't confused by the stale text.
- **Never treat a "this has been fixed/corrected" comment as ground truth without diffing the actual file/commit history.** This epic had a real instance of a completion claim not matching reality; the fix (an actual correction plus a disclaimer, rather than a fourth "flagged, non-blocking" comment) was more defensible than trusting the trail of prior comments. Any future bug-triage pass that reads "already corrected" in an epic's comment history should verify against `git log`/`git show`, not repeat the claim forward.
