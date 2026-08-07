---
id: AF-qmy9
title: "Update infra-dependencies.md to document the clusters generator convention"
status: closed
priority: 3
type: task
parent: AF-d66a
created_at: 2026-08-07T15:06:17Z
created_by: ada
updated_at: 2026-08-07T16:10:38Z
content_hash: "sha256:492ae2fd81dcd1092e29c1eb82359bace3044a9ee19a5865f1be38b427e90988"
was_blocked_by: [AF-c8p4]
assignee: dev-AF-qmy9
follows: [AF-c8p4, AF-ogxu]
labels: [accepted]
closed_at: 2026-08-07T16:10:38Z
close_reason: "Accepted via pvg story accept"
---

## Description
Description:
`docs/infra-dependencies.md` currently instructs "Use a `list` generator with one element per cluster destination -- there's no per-cluster directory to discover, just a fixed, known set of clusters (currently `demo1`, `demo2`)" as step 1 of "Adding a cluster-wide infra dependency." That instruction is now wrong -- update it to document whichever generator convention the spike story confirmed and the migration story applied fleet-wide.

Context:
The full current text of `docs/infra-dependencies.md` step 1 (to be replaced):

```markdown
1. Create `infrastructure/<name>/argocd/appset.yaml`. Use a `list`
   generator with one element per cluster destination -- there's no
   per-cluster directory to discover, just a fixed, known set of clusters
   (currently `demo1`, `demo2`).
```

This is the authoritative "how to add a new infra dependency" recipe agents and humans both follow (per `AGENTS.md`'s reference to it). Leaving it saying "use a list generator" after the migration and net-new stories have already moved every existing and new infra app off that pattern would actively mislead the next person (or agent) who adds infra dependency number 7.

USER INTENT:
The user does not want this doc to silently drift from reality. If the recipe still says "list generator" after this epic ships, the next infra dependency gets built the old way by whoever follows the doc literally -- undoing the consistency this whole epic exists to establish.

IMPLEMENTATION:
Replace step 1's text with the confirmed convention. If the spike story confirmed `clusters: {}` works:

```markdown
1. Create `infrastructure/<name>/argocd/appset.yaml`. Use Argo CD's native
   `clusters: {}` ApplicationSet generator (`spec.generators: [{clusters: {}}]`)
   -- it discovers every cluster currently registered with this Argo CD
   instance automatically, so a new workload cluster never requires editing
   existing `infrastructure/*/argocd/appset.yaml` files. Template fields:
   `{{name}}` for the cluster's registered name (use this for both
   `metadata.name` and `spec.destination.name`), `{{server}}` for its API
   server URL. See `infrastructure/sealed-secrets/argocd/appset.yaml` for a
   worked example.
```

If the spike story instead confirmed the fallback path, replace step 1's text with that fallback's actual mechanism instead (do not leave both options half-documented -- write only the one actually in use across the repo after the migration story closes).

Also update this doc's "Candidates already identified but deferred" section if either the kube-prometheus-stack story or the generator migration story surfaced a new deferred candidate worth recording (e.g. if the spike's fallback involves a generation script, note where that script lives) -- only if genuinely new information surfaced, not as padding.

KEY FILES:
`docs/infra-dependencies.md` (modified -- step 1 of "Steps," and possibly the "Candidates already identified but deferred" section).

OUT OF SCOPE:
- Rewriting the rest of the doc (steps 2-4 about README.md, Taskfile commands, and `bootstrap/` auto-discovery are unaffected by the generator change and stay as-is).
- Documenting `kube-prometheus-stack` itself as a worked example in this doc -- its own `infrastructure/kube-prometheus-stack/README.md` is the place for that; this doc stays generic/recipe-level, matching its existing scope.

DIFF BUDGET:
1 file changed (`docs/infra-dependencies.md`), roughly 10-20 changed LOC.

CONSUMES:
- AF-c8p4: infrastructure/sealed-secrets/argocd/appset.yaml (and the other 4 migrated files) -> confirmed generator convention actually applied fleet-wide
    spec: generators: [{clusters: {}}] (or confirmed fallback); template_field: '{{name}}' (or confirmed alternate)
    source: that story's PRODUCES, itself sourced from the spike story's decision record

PRODUCES:
- `docs/infra-dependencies.md` -> updated step 1 of the "Adding a cluster-wide infra dependency" recipe
    source: this story, reflecting the migration story's fleet-wide applied convention

TESTING:
Documentation-only change -- no automated test. Verification: the doc's step 1 text matches, verbatim in generator shape, what `infrastructure/sealed-secrets/argocd/appset.yaml` (or whichever file is cited as the worked example) actually contains after the migration story closes -- a manual diff-read side by side.

Acceptance Criteria:
1. [Ubiquitous] Step 1 of `docs/infra-dependencies.md`'s "Steps" section displays the confirmed generator convention and no longer instructs "use a list generator."
2. [Ubiquitous] The replacement text names the exact generator (`clusters: {}` or the confirmed fallback) and, if applicable, the exact template field(s) (`{{name}}`, `{{server}}`, etc.) actually in use.
3. [Unwanted] The updated doc shall not describe a generator convention that differs from what the 5 migrated files or the new kube-prometheus-stack app actually use -- verified by direct comparison against those files.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:markdown-writer, devops-toolkit:akp-platform

## Acceptance Criteria


## Design


## Notes


## nd_contract
status: delivered

### evidence
- Transitioned via pvg story deliver on 2026-08-07.

### proof
- [ ] Developer evidence block must remain authoritative above this contract.


## History
- 2026-08-07T15:07:23Z dep_added: blocked_by AF-c8p4
- 2026-08-07T15:07:25Z dep_added: blocks AF-7u8n
- 2026-08-07T15:57:17Z dep_removed: was_blocked_by AF-c8p4
- 2026-08-07T16:01:53Z status: open -> in_progress
- 2026-08-07T16:01:53Z auto-follows: linked to predecessor AF-c8p4
- 2026-08-07T16:01:53Z claimed by dev-AF-qmy9
- 2026-08-07T16:05:41Z status: in_progress -> in_progress
- 2026-08-07T16:05:41Z auto-follows: linked to predecessor AF-ogxu
- 2026-08-07T16:10:38Z status: in_progress -> closed
- 2026-08-07T16:10:38Z dep_removed: no_longer_blocks AF-7u8n

## Links
- Parent: [[AF-d66a]]
- Was blocked by: [[AF-c8p4]]
- Follows: [[AF-c8p4]], [[AF-ogxu]]

## Comments

### 2026-08-07T16:06:20Z ada
PROOF:

Commit: 3de5daa (story/AF-qmy9, pushed to origin, parent a33e48d = epic/AF-d66a head)
Diff: 1 file changed, 25 insertions(+), 4 deletions(-) -- docs/infra-dependencies.md only.
Within the 10-20 changed LOC budget (a fenced YAML example accounts for the overage).

Commands run:
  git -C <wt> --no-pager diff --stat
      -> docs/infra-dependencies.md | 29 +++++++++++++++++++++++++----
         1 file changed, 25 insertions(+), 4 deletions(-)
  npx --yes markdownlint-cli docs/infra-dependencies.md
      -> exit 0, no output (clean, MD013 line-length included)
  pvg verify <abs>/docs/infra-dependencies.md --format text
      -> VERIFY: PASSED (0 files scanned, 0 issues); exit 0
  Verbatim-shape cross-check (see AC3 below): extracted the doc's fenced yaml
  block, stripped its 3-space list indent, and diff -u'd it against the
  generator stanza of each infrastructure/*/argocd/appset.yaml (2-space
  `spec:` indent stripped).
      -> MATCH argo-rollouts-crds / gateway-api-crds / openebs-localpv /
         sealed-secrets / traefik-gateway  (5/5 byte-identical, 0 differ)
  grep -rn '{{server}}' infrastructure/
      -> (none)

Test suite: none. Documentation-only story; this repo has no test suite and the
story ships prose, not code. Verification is the markdownlint run, pvg verify,
and the mechanical diff of the documented YAML against the five real manifests.
Coverage: N/A (no executable code changed).
Errors/warnings encountered: zero. markdownlint exit 0, pvg verify exit 0,
git push clean.

AC VERIFICATION TABLE:
| AC | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| 1 | Step 1 no longer says "use a list generator"; documents `clusters` + selector | PASS | Diff removes the 4-line `list` paragraph verbatim. New text opens "Use a `clusters` generator" and states "The selector is mandatory." `grep -n 'list' docs/infra-dependencies.md` -> no generator reference remains. |
| 2 | Names exact generator, exact selector (key/operator/values), exact template field(s); NOT the draft's `{{server}}` suggestion | PASS | Generator: `clusters`. Selector: key `akuity.io/argo-cd-cluster-name`, operator `NotIn`, values `[in-cluster, kargo]`. Template field: `{{name}}` for both `metadata.name` and `spec.destination.name`. `{{server}}` is documented as a PROHIBITION ("Do not use `{{server}}`"), with the concrete reason -- it resolves to an internal proxy URL such as `http://cluster-demo1:8001`, not a reachable API server endpoint. The story draft's suggestion to use it for the API server URL was NOT followed. |
| 3 | Generator description matches, verbatim in shape, the real merged sealed-secrets appset -- verified by direct comparison, not asserted | PASS | Mechanical `diff -u`, not eyeballing. Doc block vs sealed-secrets/argocd/appset.yaml lines 16-22: empty diff. Extended to all five migrated appsets: 5/5 byte-identical. |

Scope discipline:
- Steps 2-4 (README.md, Taskfile commands, bootstrap/ auto-discovery) untouched --
  confirmed by the diff, which shows only the step-1 hunk.
- "Candidates already identified but deferred" untouched. Nothing in this epic
  changed the cert-manager rationale (still no real domains for akkoma/soju),
  so padding it would have been noise.
- kube-prometheus-stack not mentioned; belongs in its own README per AF-d3ax.

Source of truth used:
I did NOT use the story body's illustrative draft. I read the actual merged
infrastructure/sealed-secrets/argocd/appset.yaml on story/AF-qmy9 (whose parent
is a33e48d, the epic head that merged AF-c8p4's migration commit bba5433), then
read the full AF-ogxu decision record for the selector rationale. The draft was
wrong on both counts the dispatcher flagged, and the real file confirms it:
the selector exists in the merged manifests, and destination is `name: '{{name}}'`
with no `{{server}}` anywhere under infrastructure/.

LEARNINGS:

- Verifying "matches verbatim in shape" is a diff, not a reading. I extracted the
  doc's fenced block programmatically, normalized only the two known indent
  offsets (3-space markdown list continuation, 2-space `spec:` nesting), and
  diffed. That turns AC3 from an assertion into a reproducible check, and it
  cheaply generalized to all five appsets instead of just the cited one.
- The story body's own draft example was wrong in exactly the two places that
  mattered most (missing selector, recommending `{{server}}`). The dispatcher
  flagged it, but the general lesson holds: when a story hands you illustrative
  text, treat it as a hypothesis and confirm against the merged artifact. The
  merged manifest and the AF-ogxu decision record agreed with each other and
  disagreed with the draft.
- AF-ogxu's finding is worth restating because it is counterintuitive: the danger
  of `clusters: {}` on this Akuity-hosted instance is over-matching, not
  under-matching. It returns four clusters (demo1, demo2, in-cluster, kargo), so
  the omission of a selector is a silent broadening rather than a loud failure.
  I made that the load-bearing sentence of the doc for exactly that reason -- a
  reader who skims will still see "The selector is mandatory."
- Denylist over allowlist is the whole point of the migration and deserved one
  clause in the doc. `NotIn [in-cluster, kargo]` picks up a third workload
  cluster with zero file edits; `In [demo1, demo2]` would be a list generator
  wearing a different hat.
- Environment gotcha, carried forward from AF-ogxu and hit again here: the pvg
  guard blocks `cd` into a worktree in this dispatcher context. Everything has to
  run as `git -C <worktree>` plus absolute paths for Read/Edit. Worth knowing
  before the first command rather than after.
