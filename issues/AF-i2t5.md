---
id: AF-i2t5
title: "Bug: AF-tqmb missing parent link to epic AF-q1il, causing epic close-eligible to falsely report full completion"
status: open
priority: 0
type: bug
labels: [discovered-by-pm]
parent: AF-q1il
created_at: 2026-08-05T16:33:32Z
created_by: ada
updated_at: 2026-08-05T16:33:32Z
content_hash: "sha256:11bb59e391174b872151e7e861860cede79814524a4ef050aadd2538ac614395"
---

## Description
Priority: P0 (bugs are always P0)

Description:
AF-tqmb (the epic's human-gated release-gate story) was created without a
`parent` field pointing at its epic, AF-q1il. Every other story in the epic
carries `parent: AF-q1il` in its frontmatter; AF-tqmb's frontmatter has no
`parent` key at all. Because `nd children`, `nd epic tree`, and
`nd epic close-eligible` all resolve an epic's membership via the child's
`parent` field, AF-tqmb was invisible to all three commands even though it
is unambiguously part of this epic (it is `blocked_by` the epic's capstone,
carries the `release-gate` label, and its own body says "This is the
epic's release gate").

DISCOVERED DURING:
AF-cbot (PM acceptance review of the epic's capstone story). Reviewing
AF-cbot's own Links/History before accepting it, the reviewer cross-checked
`pvg nd epic close-eligible AF-q1il` against the epic's actual story list
and found it reported the epic as `10/10 closed` -- eligible for auto-close
-- while AF-tqmb, the epic's own release gate, was still `deferred` and had
not run any of its human-verification steps. `bug_fast_track` is disabled
and this project uses the centralized model, so this correctly routed to
the Sr PM (this agent) for triage rather than being created directly by
the PM-Acceptor.

SYMPTOMS:
- `pvg nd children AF-q1il` lists only the 10 stories that have
  `parent: AF-q1il` set; AF-tqmb is absent even though it is a story in
  this epic.
- `pvg nd epic tree AF-q1il` shows the same 10 stories, all with `[x]`
  (closed), and omits AF-tqmb's row entirely.
- `pvg nd epic close-eligible AF-q1il` reports `AF-q1il ... (10/10 closed)`
  -- treating the epic as fully closed/eligible, when in fact an 11th
  story (AF-tqmb, `deferred`, human-execution-required) still belongs to
  the epic and has not been executed.
- Any automation or agent that trusts `close-eligible`'s verdict at face
  value (rather than manually diffing the epic's story list against the
  command's output, as this review did) would auto-close AF-q1il while
  the destructive live-cluster-recreation release gate is still
  unexecuted.

EVIDENCE:
- `AF-tqmb.md` frontmatter (raw, before fix) had no `parent:` key:
  ```
  id: AF-tqmb
  title: "Recreate demo1/demo2 with GitOps-managed storage & ingress; retire akp-infra Terraform state (human-run, gated)"
  status: deferred
  priority: 0
  type: task
  labels: [release-gate, human-execution-required, external-integration]
  created_at: 2026-08-05T14:34:47Z
  ...
  was_blocked_by: [AF-cu83, AF-uw18, AF-cbot]
  ```
  compare `AF-uw18.md` (another story in the same epic), which correctly
  carries `parent: AF-q1il`.
- `AF-cbot`'s own History log records a one-directional dependency edge
  that was created correctly on AF-cbot's side but is not the actual root
  cause: `2026-08-05T14:34:59Z dep_added: blocks AF-tqmb` (AF-cbot's Links
  section: "blocks AF-tqmb"). Investigation during this triage confirmed
  this edge DID mirror correctly -- AF-tqmb's History independently shows
  `dep_added: blocked_by AF-cbot` at the same timestamp, and both sides
  were symmetrically cleared (`dep_removed: was_blocked_by AF-cbot` /
  `dep_removed: no_longer_blocks AF-tqmb`) when AF-cbot closed. The
  `blocked_by`/`blocks` dependency mechanism itself is NOT the defect;
  AF-tqmb's `blocked_by` being empty now is expected, correct behavior
  (all of AF-tqmb's blockers -- AF-cu83, AF-uw18, AF-cbot -- have closed).
  The actual defect is narrower: AF-tqmb's `parent` field was simply never
  set at creation time, and `nd children`/`nd epic tree`/
  `nd epic close-eligible` key epic membership off `parent`, not off
  dependency edges.
- Full epic-wide audit of every other story's frontmatter (`parent`,
  `blocked_by`, `blocks`, `was_blocked_by`, `follows`, `led_to`) found no
  other missing-`parent` or unmirrored-`blocked_by`/`blocks` pair in this
  epic. AF-4wcm's `blocks: [AF-cu83]` correctly mirrors AF-cu83's
  `blocked_by: [AF-4wcm]`. This is an isolated, single-story defect.

POSSIBLE CAUSES:
1. AF-tqmb was created via `nd create` without a `--parent AF-q1il` flag
   (most likely -- its frontmatter has no parent key at all, not an empty
   one), unlike every sibling story in the epic which does carry the flag.
2. AF-tqmb's unusual authoring path (translated directly from a design
   plan document's "Task 7" section as a deferred, human-gated story
   rather than through the normal Sr PM story-authoring flow used for its
   9 siblings) may have skipped the same creation template/checklist step
   that sets `--parent` on every other story.

CONFIG (if relevant):
Not applicable -- this is nd vault metadata, not application config.

Acceptance Criteria:
1. AF-tqmb's frontmatter has `parent: AF-q1il` set, matching every other
   story in this epic.
2. `pvg nd children AF-q1il` includes AF-tqmb in its output.
3. `pvg nd epic tree AF-q1il` includes AF-tqmb's row (shown as `[ ]`,
   i.e. open, since its status is `deferred`, not closed).
4. `pvg nd epic close-eligible AF-q1il` does NOT report the epic as
   close-eligible while AF-tqmb remains open/deferred -- it must report
   an accurate open-story count (11 total, 10 closed, 1 open) rather than
   `10/10 closed`.
5. Full epic-wide re-audit of every other story's `parent`/`blocked_by`/
   `blocks`/`was_blocked_by` fields confirms no other one-directional-link
   or missing-parent defect exists in this epic.
6. Root cause and fix are recorded on this bug's own record before it is
   closed.

MANDATORY SKILLS TO REVIEW:
None identified (nd vault frontmatter repair; no application code).

## Acceptance Criteria


## Design


## Notes


## History


## Links
- Parent: [[AF-q1il]]

## Comments
