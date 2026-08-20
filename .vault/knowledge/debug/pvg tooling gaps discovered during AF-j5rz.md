---
type: debug
project: argo-fleet
status: active
actionable: pending
epic: AF-j5rz
created: 2026-08-20
---

# pvg tooling gaps discovered during AF-j5rz

## `gates.exclude` has no effect on the duplication gate (pvg 1.62.0)
`pvg gates`'s duplication check (jscpd under the hood) fired 14 pre-existing BLOCKs across this repo, all of them `docs/superpowers/{plans,specs}/*.md` planning documents quoting real manifests/terraform verbatim for explanatory purposes -- not real code-vs-code duplication. `pvg settings gates.exclude=...` was tested with every glob syntax tried (bare dir, trailing slash, `**`, `**/*.md`) and confirmed, via direct A/B `pvg gates` output comparison, to have **zero effect** on the duplication gate in this pvg build -- only the numeric `gates.duplication.min_lines`/`max_pct` settings are actually honored. **Working remediation**: add a repo-root `.jscpd.json` (`{"ignore": ["docs/superpowers/**"]}`) -- jscpd (which `pvg gates` shells out to) auto-discovers this file from cwd independent of pvg's own settings layer. Verified this clears all 14 pre-existing BLOCKs plus the aggregate total BLOCK without touching `min_lines`/`max_pct` and without excluding any real manifest/source file from duplication scanning.
**Action**: until pvg fixes the `gates.exclude` wiring, use a `.jscpd.json` (or equivalent tool-native config) as the actual remediation path for gate false-positives caused by planning docs quoting real code, and verify any `gates.exclude` change with a before/after `pvg gates` diff rather than trusting the setting took effect.

## `pvg verify` is a structural no-op on `.yaml` files
Every manifest-only story in this epic that ran `pvg verify` on changed `.yaml` files got `PASSED (0 files scanned)` -- `.yaml` is not a recognized source extension for its scanner, so it is vacuously true on every GitOps-manifest change in this repo. This was correctly flagged as non-substantive by every developer who hit it, but it recurred story after story, suggesting the pattern deserves standing documentation rather than rediscovery each time.
**Action**: for any manifest-only repo/story, treat `pvg verify` output on `.yaml` as a formality only; the real static gate is the Ruby (or equivalent) e2e/render-diff suite. Consider filing this as a pvg feature request (recognize `.yaml`/`.yml` for at least a parse-level check) rather than re-flagging it per-epic.

## `pvg story accept --next <id>` can cross epic boundaries (reported by orchestrator, not independently reproduced in story bodies read for this retro)
The dispatcher observed this convenience flag twice suggest/claim a story from a different, unrelated epic rather than scoping to the current epic's own ready queue during this epic's execution -- caught and released both times via `pvg story release`, but it is a live tooling gap: `--next` should scope suggestions to the dispatched epic's own subtree, not the global ready queue.
**Action**: flag to pvg maintainers as a containment bug in `--next`'s candidate-selection query; until fixed, dispatchers should treat any `--next`-suggested story as needing an epic-membership check before claiming.
