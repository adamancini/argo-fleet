---
id: AF-iv8x
title: "Spike: confirm ApplicationSet matrix generator interpolates sibling list params into git files path"
status: open
priority: 0
type: task
labels: [spike]
parent: AF-j5rz
created_at: 2026-08-18T18:55:02Z
created_by: ada
updated_at: 2026-08-18T18:55:02Z
content_hash: "sha256:8b4bbfa195ad34cbca4e4282253951a9ffe0eea54e70ef4e72e3718359f50733"
blocks: [AF-6jta, AF-vm0q]
---

## Description
Description:
SPIKE -- confirm, before `appset-workloads.yaml` is implemented for real, whether the shared `demo1`/`demo2`/`kargo` instance's Argo CD version supports a `matrix` generator's inner `git files` generator interpolating `{{.name}}` from the outer `list` generator's sibling element (the exact shape `apps/arr-stack/argocd/appset-workloads.yaml`'s design requires: `path: "apps/arr-stack/env/{{.name}}/*/release.yaml"`, where `.name` comes from the OUTER `list` generator, not the `git files` generator itself). This is a hard gate, not a nice-to-have: the design spec's own language is explicit that this "must be settled before implementation, not deferred silently," and the user has separately confirmed spike-first over guessing.

Context:
Argo CD's `matrix` generator combines two child generators; whether one child generator's template fields can reference the OTHER child generator's params (as opposed to only the matrix's own combined output being usable downstream in `template:`) is a version- and generator-pair-dependent capability, not something safe to assume from the top-level `matrix` generator's existence alone. `sedemo-platform`'s `demo-microservices` precedent (referenced in the design spec) uses two static `list` generators in its matrix, which does NOT exercise this exact cross-generator-interpolation-inside-a-generator's-own-config capability -- it is not a valid precedent for THIS specific shape, only for "matrix generators work on this instance in general."

Per this repo's own established discipline (`AGENTS.md`'s Argo CD section): check the `devops-toolkit:akp-platform` skill and Argo CD source (`~/src/github.com/argoproj/argo-cd`) / declarative-setup docs (https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/) before guessing at generator behavior. Then, per the design spec's own explicit preference: if a live check against the shared instance is safe and read-only (creates nothing), prefer that over a source-only guess -- specifically `argocd version` (confirms the exact ApplicationSet-controller version actually running, which may differ from the OSS release the source you're reading corresponds to) and a dry-run `argocd appset generate` against a throwaway matrix+git-files generator block (server-side RPC, creates nothing, safe even on this shared instance -- see `.vault/knowledge/patterns/Render-diff verification primitive for ApplicationSet changes.md`).

USER INTENT:
The user needs a documented, evidence-based answer -- not an assumption -- to "does the exact generator shape this design needs actually work on the instance we're deploying to," because the two possible answers lead to materially different downstream stories (Story 4 as currently scoped, vs. a not-yet-written fallback story that drops the auto-pickup mechanism entirely). Guessing wrong here means Story 4 either wastes a full implementation cycle on an unsupported shape, or -- worse -- silently ships something that looks like it works in a dry-run but never actually re-renders on a real promotion.

IMPLEMENTATION:
1. Check `devops-toolkit:akp-platform` skill and Argo CD source/docs first (per `AGENTS.md`): search `~/src/github.com/argoproj/argo-cd` for the `matrix` generator's implementation (`applicationset/generators/matrix.go` or equivalent) and confirm from the code/CHANGELOG whether/when cross-generator param interpolation within a sibling generator's own config fields (as opposed to only in the final `template:` block) was added, and whether it's gated behind `goTemplate: true` (the design's `appset-workloads.yaml` already sets `goTemplate: true`, `goTemplateOptions: ["missingkey=error"]`).
2. Run `argocd version` against the shared instance to confirm the exact Argo CD version in use (do not assume it matches whatever OSS release tag the locally-cloned source happens to be checked out at).
3. If a dry-run RPC check is possible without touching anything real: construct a throwaway `matrix` generator block (2-3 dummy list elements x a `git files` generator referencing `{{.name}}` in its `path`, pointed at a `path` that's safe to probe -- e.g. `apps/arr-stack/env/{{.name}}/*/release.yaml` once AF-8r8l's files exist, or a narrower probe against an existing app's `env/*/release.yaml` shape if AF-8r8l hasn't landed yet) and run it through `argocd appset generate -o json --grpc-web` (server-side dry-run, creates nothing). Confirm whether the rendered output actually reflects per-element interpolated paths, or errors, or silently renders the literal unresolved string.
4. Document BOTH possible outcomes explicitly in this story's resolution (Notes/Comments), not just the one that turns out true:
   - (a) SUPPORTED: proceed with Story 4 exactly as currently scoped (git-files-generator design, per the committed spec).
   - (b) UNSUPPORTED: Story 4 as currently scoped must NOT be implemented as written. Report back to the Sr PM (via the dispatcher) so a replacement story can be authored for the fallback: a static `dev`/`staging`/`prod` list generator as the matrix's second generator (matching `sedemo-platform`'s `demo-microservices` precedent), accepting the loss of the "Kargo commits to release.yaml and the ApplicationSet just picks it up" auto-pickup mechanism `akkoma`/`soju` rely on. Do NOT write the fallback's implementation yourself in this story -- the design spec and the epic are explicit that guessing at the fallback now, before the spike resolves, is exactly the failure mode this story exists to prevent.

KEY FILES:
No files created or modified under normal resolution -- this is an investigation story. If outcome (b) occurs, this story's ONLY file-producing action is a comment/note recording the finding; a NEW story is created separately for the fallback implementation.

OUT OF SCOPE:
- Implementing `appset-workloads.yaml` itself, under either outcome -- that is Story 4 (if supported) or a not-yet-created follow-up story (if unsupported). This story produces a decision record, not code.
- Any live mutation of the shared instance -- every live-touching step in this story (`argocd version`, `argocd appset generate` dry-run) is explicitly read-only/server-side-dry-run and creates nothing; if at any point a step would create, update, or delete a real resource, stop and treat that as a signal this story's scope has drifted, not a green light to proceed.

DIFF BUDGET:
0 files under normal resolution (pure investigation). If a throwaway probe file is needed to construct a dry-run generator block, it must live outside `apps/arr-stack/` (e.g. a scratch file, never committed) and must be deleted before this story closes.

PRODUCES:
- This issue's own Notes/Comments -> decision record
    spec: supported: true | false; evidence: [argocd version output, appset generate dry-run output or source/changelog citation]; fallback_required: true | false
    source: this story's own empirical finding -- consumed by Story 4 (AF-<workloads>, created after this spike closes) exactly as AF-d3ax consumed AF-ogxu's decision record in this repo's own prior epic (same pattern, reused deliberately)

TESTING:
This is a spike -- "testing" here means the verification steps in IMPLEMENTATION themselves (source/changelog citation, `argocd version`, dry-run `argocd appset generate` diff) are the deliverable, not a separate test suite. The bar for closing this story: the resolution documents BOTH the confirmed answer AND the evidence used to confirm it (a citation or command output a reviewer could independently re-run), not just a stated conclusion.

Acceptance Criteria:
1. [Ubiquitous] The Argo CD version actually running on the shared `demo1`/`demo2`/`kargo` instance is confirmed and recorded (`argocd version` output, not an assumption).
2. [Event] The matrix-generator-references-sibling-params question is answered with cited evidence: either a source/changelog citation (with exact file/line or PR/release reference) or a dry-run `argocd appset generate` render showing genuinely interpolated per-element paths.
3. [Ubiquitous] Both possible outcomes (supported / unsupported) and their downstream consequences are documented in this story's resolution, not just the one that turned out true.
4. [Unwanted] No live resource is created, updated, or deleted against the shared instance by any step in this story.
5. If unsupported: this story's resolution explicitly states that Story 4 (AF-<workloads>) must not be implemented as currently scoped, and that a new fallback story is required -- and does NOT itself contain that fallback's implementation.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory -- check before guessing at generator behavior, per `AGENTS.md`)

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-18T18:56:07Z dep_added: blocks AF-6jta
- 2026-08-18T18:57:53Z dep_added: blocks AF-vm0q

## Links
- Parent: [[AF-j5rz]]
- Blocks: [[AF-6jta]], [[AF-vm0q]]

## Comments
