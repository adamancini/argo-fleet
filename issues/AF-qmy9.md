---
id: AF-qmy9
title: "Update infra-dependencies.md to document the clusters generator convention"
status: open
priority: 3
type: task
parent: AF-d66a
created_at: 2026-08-07T15:06:17Z
created_by: ada
updated_at: 2026-08-07T15:06:17Z
content_hash: "sha256:a96fc72b9daab5a3dd1495f898ca0e5e7b8ed01964907af7d87e4a2321b032b4"
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
- (migration story id): infrastructure/sealed-secrets/argocd/appset.yaml (and the other 4 migrated files) -> confirmed generator convention actually applied fleet-wide
    spec: generators: [{clusters: {}}] (or confirmed fallback); template_field: '{{name}}' (or confirmed alternate)
    source: that story's PRODUCES, itself sourced from the spike story's decision record

PRODUCES:
- `docs/infra-dependencies.md` -> updated step 1 of the "Adding a cluster-wide infra dependency" recipe
    source: this story, reflecting the migration story's fleet-wide applied convention

TESTING:
Documentation-only change -- no automated test. Verification: the doc's step 1 text matches, verbatim in generator shape, what `infrastructure/sealed-secrets/argocd/appset.yaml` (or whichever file is cited as the worked example) actually contains after the migration story closes -- a manual diff-read side by side.

Acceptance Criteria:
1. [Ubiquitous] Step 1 of `docs/infra-dependencies.md`'s "Steps" section no longer instructs "use a list generator."
2. [Ubiquitous] The replacement text names the exact generator (`clusters: {}` or the confirmed fallback) and, if applicable, the exact template field(s) (`{{name}}`, `{{server}}`, etc.) actually in use.
3. [Unwanted] The updated doc shall not describe a generator convention that differs from what the 5 migrated files or the new kube-prometheus-stack app actually use -- verified by direct comparison against those files.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:markdown-writer, devops-toolkit:akp-platform

## Acceptance Criteria


## Design


## Notes


## History


## Links
- Parent: [[AF-d66a]]

## Comments
