---
id: AF-w3do
title: "Rename colliding bootstrap resources with fleet- prefix (platform-aoa, argocd-apps, kargo-apps)"
status: open
priority: 1
type: task
parent: AF-q1il
created_at: 2026-08-05T18:23:22Z
created_by: ada
updated_at: 2026-08-05T18:23:22Z
content_hash: "sha256:9f1dcc3e529f68a7b44c82c5e93fe1c07af730f3ae1459a699cea246b4505cda"
blocks: [AF-s8l0, AF-cbot]
---

## Description
Description:
Rename `argo-fleet`'s three bootstrap resources that collide with
`akp-platform`'s already-live equivalents on the shared Akuity-hosted
Argo CD instance (`ada-quickstart-argocd`), by prefixing each with
`fleet-`: filename, `metadata.name`, and (for one file) one
self-referential comment. Update the two `README.md` references that
point at the old filename, and run static verification confirming no
stale unprefixed-name reference remains anywhere it shouldn't.

Context:
This repo (`argo-fleet`) and `akp-platform` both register against the
same Akuity-hosted Argo CD/Kargo instance
(`ada-quickstart-argocd`/`ada-quickstart-kargo`). While closing out the
`AF-q1il` cluster-lifecycle epic, it was discovered that `argo-fleet`'s
own root bootstrap manifest (`bootstrap/platform-aoa.yaml`) has never
actually been applied to that shared instance. Attempting to apply it now
surfaced that it -- and two more of `argo-fleet`'s bootstrap resources --
share EXACT resource names with `akp-platform`'s already-live
equivalents, all in the `argocd` namespace:

| Resource | Kind | `argo-fleet` file | Collides with (live, `akp-platform`) |
| --- | --- | --- | --- |
| `platform-aoa` | Application | `bootstrap/platform-aoa.yaml` | `argocd/platform-aoa` (repo: `akp-platform`, `Synced`/`Healthy`) |
| `argocd-apps` | ApplicationSet | `bootstrap/argocd-apps.yaml` | `argocd/argocd-apps` (repo: `akp-platform`, `Healthy`) |
| `kargo-apps` | ApplicationSet | `bootstrap/kargo-apps.yaml` | `argocd/kargo-apps` (repo: `akp-platform`, `Healthy`) |

Both repos independently converged on the same discovery convention
(`apps/*/argocd`, `apps/*/kargo`) and the same resource names --
unsurprising, since `argo-fleet`'s bootstrap layer was modeled on
`akp-platform`'s. Applying `argo-fleet`'s versions as-is, especially with
`--upsert`, risks overwriting `akp-platform`'s live `platform-aoa`
Application -- which has `prune: true` -- and deleting every Application
it currently manages (`argocd-guestbook-helm`,
`argocd-guestbook-helm-rendered`, `argocd-guestbook-kustomize`,
`argocd-guestbook-rendered`, `argocd-rollouts-app`, and their generated
children across `demo1`/`demo2`).

The *children* these ApplicationSets generate do NOT collide --
`argo-fleet`'s `apps/` directory currently holds `akkoma`/`soju`,
producing child names like `argocd-akkoma`/`kargo-soju`, distinct from
`akp-platform`'s `argocd-guestbook-helm` etc. Only the three top-level
bootstrap resource NAMES collide.

This is a narrow, immediate fix: disambiguate the three colliding names
so `argo-fleet`'s tree can go live safely later (in a separate, human-run
story -- this story does NOT touch the live shared instance, it only
edits files in this repo's working tree). The `fleet-` prefix is a
deliberate signal that these names are temporary -- expected to be
dropped once `akp-platform`'s originals are eventually decommissioned as
part of a later, separate akp-platform/akp-infra consolidation migration
(explicitly out of scope here).

`bootstrap/infra-apps.yaml` (`metadata.name: infra-apps`) does NOT
collide with any live `akp-platform` resource. Do not touch it, its
`metadata.name`, or its content -- any edit to that file is out of scope
and a scope-creep regression.

Full design spec (read for background only -- everything needed to
implement is embedded below):
`docs/superpowers/specs/2026-08-05-bootstrap-name-collision-design.md`
Full implementation plan (Tasks 1 and 2 of this plan map to this story;
Task 3 is deliberately excluded -- see the separate human-only follow-up
story this one produces a prerequisite for):
`docs/superpowers/plans/2026-08-05-bootstrap-name-collision.md`

USER INTENT:
The repo owner needs to be able to apply `argo-fleet`'s bootstrap tree to
the shared Argo CD instance later with total confidence that doing so
will NOT silently overwrite or delete `akp-platform`'s already-live,
currently-serving-a-real-demo Application/ApplicationSets. That
confidence has to come from the resource names being provably distinct,
byte-verified by grep across the whole repo -- not from an assumption
that "the rename probably worked."

IMPLEMENTATION:
Three files are renamed via `git mv` (so history is preserved) and
edited; then two lines of `README.md` are updated to match; then a
repo-wide static check confirms no stale reference to the old names
remains anywhere unexpected.

Step 1 -- Rename `bootstrap/platform-aoa.yaml`:

```bash
git -C /Users/ada/src/github.com/adamancini/argo-fleet mv bootstrap/platform-aoa.yaml bootstrap/fleet-platform-aoa.yaml
```

The file's current, exact, full content is:

```yaml
# Root app-of-apps. Apply this ONCE against the Argo CD control plane
# (`argocd app create -f bootstrap/platform-aoa.yaml`) and everything else
# in this repo is discovered and deployed automatically by the
# ApplicationSets in this directory. Onboarding a new infra dependency or
# app never requires touching bootstrap/ again.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-aoa
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/adamancini/argo-fleet.git
    targetRevision: HEAD
    path: bootstrap
  destination:
    name: in-cluster
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Replace the content of the renamed file with EXACTLY this (only the
comment's filename reference and `metadata.name` change; every other
line -- `spec.source`, `spec.destination`, `spec.syncPolicy` -- is
byte-identical to the original):

```yaml
# Root app-of-apps. Apply this ONCE against the Argo CD control plane
# (`argocd app create -f bootstrap/fleet-platform-aoa.yaml`) and everything
# else in this repo is discovered and deployed automatically by the
# ApplicationSets in this directory. Onboarding a new infra dependency or
# app never requires touching bootstrap/ again.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fleet-platform-aoa
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/adamancini/argo-fleet.git
    targetRevision: HEAD
    path: bootstrap
  destination:
    name: in-cluster
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Step 2 -- Rename `bootstrap/argocd-apps.yaml`:

```bash
git -C /Users/ada/src/github.com/adamancini/argo-fleet mv bootstrap/argocd-apps.yaml bootstrap/fleet-argocd-apps.yaml
```

In the renamed file, change ONLY:

```yaml
metadata:
  name: argocd-apps
```

to:

```yaml
metadata:
  name: fleet-argocd-apps
```

Every other line -- the leading comment, `spec.generators`,
`spec.template.metadata.name: 'argocd-{{path[1]}}'` (this child-naming
template is UNCHANGED -- it does not collide with anything and touching
it is scope creep), `spec.template.spec.project`, `.source`,
`.destination`, `.syncPolicy` -- stays byte-for-byte identical to the
original.

Step 3 -- Rename `bootstrap/kargo-apps.yaml`:

```bash
git -C /Users/ada/src/github.com/adamancini/argo-fleet mv bootstrap/kargo-apps.yaml bootstrap/fleet-kargo-apps.yaml
```

In the renamed file, change ONLY:

```yaml
metadata:
  name: kargo-apps
```

to:

```yaml
metadata:
  name: fleet-kargo-apps
```

Every other line -- both comment blocks, `spec.generators`,
`spec.template.metadata.name: 'kargo-{{path[1]}}'` (UNCHANGED, same
reasoning as Step 2), `spec.template.spec.project: '{{path[1]}}'`,
`.source`, `.destination`, `.syncPolicy`, `.syncOptions` -- stays
byte-for-byte identical to the original.

Step 4 -- Validate YAML syntax on all three renamed files:

```bash
for f in bootstrap/fleet-platform-aoa.yaml bootstrap/fleet-argocd-apps.yaml bootstrap/fleet-kargo-apps.yaml; do
  ruby -ryaml -e "YAML.load_stream(File.read('/Users/ada/src/github.com/adamancini/argo-fleet/$f'))" && echo "OK: $f"
done
```

Expected: `OK: bootstrap/fleet-platform-aoa.yaml`,
`OK: bootstrap/fleet-argocd-apps.yaml`,
`OK: bootstrap/fleet-kargo-apps.yaml` -- no exceptions raised.

Step 5 -- Confirm `git mv` was tracked as renames, not delete+add:

```bash
git -C /Users/ada/src/github.com/adamancini/argo-fleet status
```

Expected: three entries under "Changes to be committed" reading
`renamed: bootstrap/platform-aoa.yaml -> bootstrap/fleet-platform-aoa.yaml`
(and the `argocd-apps`/`kargo-apps` equivalents), each also showing as
modified (the content edit alongside the rename).

Step 6 -- Update both `README.md` references to `platform-aoa.yaml`.
`README.md`'s current, exact content around these two references:

```markdown
- `bootstrap/` — the one manifest you apply by hand
  (`bootstrap/platform-aoa.yaml`); everything else is discovered
  automatically from `infrastructure/*/argocd` and `apps/*/{argocd,kargo}`.
```

and:

```markdown
2. `argocd app create -f bootstrap/platform-aoa.yaml` — the only manifest
   applied by hand; bootstraps everything else.
```

Change both to:

```markdown
- `bootstrap/` — the one manifest you apply by hand
  (`bootstrap/fleet-platform-aoa.yaml`); everything else is discovered
  automatically from `infrastructure/*/argocd` and `apps/*/{argocd,kargo}`.
```

and:

```markdown
2. `argocd app create -f bootstrap/fleet-platform-aoa.yaml` — the only manifest
   applied by hand; bootstraps everything else.
```

No other line in `README.md` changes.

Step 7 -- Repo-wide grep confirming no live stale reference to the old
unprefixed names remains:

```bash
grep -rnP --exclude-dir=.git '(?<!fleet-)(platform-aoa|argocd-apps|kargo-apps)' /Users/ada/src/github.com/adamancini/argo-fleet
```

Expected: every remaining hit is in one of these SIX pre-existing files
(dated planning/spec documents that record past design decisions -- not
live references -- including this fix's own design spec, which mentions
the old names in its Background section by design, and this story's own
implementation plan document):

- `docs/superpowers/specs/2026-08-05-bootstrap-name-collision-design.md`
- `docs/superpowers/plans/2026-08-05-bootstrap-name-collision.md`
- `docs/superpowers/specs/2026-08-05-cluster-lifecycle-and-ingress-storage-design.md`
- `docs/superpowers/specs/2026-08-04-argo-fleet-bootstrap-design.md`
- `docs/superpowers/plans/2026-08-04-argo-fleet-bootstrap.md`
- `docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md`

No hit shall appear in `README.md`, `bootstrap/*.yaml`, or any other
file. If one does, go back and fix it before proceeding -- do not mark
this story delivered with a stray hit unaccounted for.

Step 8 -- Commit (two commits, matching the plan's own task boundary --
do not squash into one commit, so the rename-only change stays reviewable
separately from the docs change):

```bash
git -C /Users/ada/src/github.com/adamancini/argo-fleet add bootstrap/fleet-platform-aoa.yaml bootstrap/fleet-argocd-apps.yaml bootstrap/fleet-kargo-apps.yaml
git -C /Users/ada/src/github.com/adamancini/argo-fleet commit -m "bootstrap: prefix colliding resource names with fleet-"
git -C /Users/ada/src/github.com/adamancini/argo-fleet add README.md
git -C /Users/ada/src/github.com/adamancini/argo-fleet commit -m "docs: update README bootstrap reference to fleet-platform-aoa.yaml"
```

KEY FILES:
- `bootstrap/platform-aoa.yaml` -> renamed to `bootstrap/fleet-platform-aoa.yaml` (modified)
- `bootstrap/argocd-apps.yaml` -> renamed to `bootstrap/fleet-argocd-apps.yaml` (modified)
- `bootstrap/kargo-apps.yaml` -> renamed to `bootstrap/fleet-kargo-apps.yaml` (modified)
- `README.md` (modified, lines matching the two blocks quoted in Step 6)
- `bootstrap/infra-apps.yaml` -- explicitly NOT touched, do not open this file for editing

CONSUMES:
None. This story modifies pre-existing repository files
(`bootstrap/*.yaml`, `README.md`) that were not produced by any other
backlog story -- they predate this epic's tracked work.

PRODUCES:
- `bootstrap/fleet-platform-aoa.yaml` -> Argo CD `Application`,
  `metadata.name: fleet-platform-aoa`, `namespace: argocd`. Root
  app-of-apps; `spec.source.path: bootstrap`, `spec.destination.name:
  in-cluster`, `spec.syncPolicy.automated: {prune: true, selfHeal: true}`.
- `bootstrap/fleet-argocd-apps.yaml` -> Argo CD `ApplicationSet`,
  `metadata.name: fleet-argocd-apps`, `namespace: argocd`. Git-directory
  generator over `apps/*/argocd`; child template name
  `'argocd-{{path[1]}}'` (unchanged).
- `bootstrap/fleet-kargo-apps.yaml` -> Argo CD `ApplicationSet`,
  `metadata.name: fleet-kargo-apps`, `namespace: argocd`. Git-directory
  generator over `apps/*/kargo`; child template name
  `'kargo-{{path[1]}}'` (unchanged).
- `README.md` -> both bootstrap references now read
  `bootstrap/fleet-platform-aoa.yaml`.
This is the exact renamed path a downstream human-run story consumes to
apply the bootstrap Application against the live shared instance.

TESTING:
Default coverage: static-only verification (no unit/integration test
suite exists for this repo's GitOps manifests; verification is YAML
parse + repo-wide grep, both already specified as Steps 4 and 7 above).
No live cluster or live Argo CD instance is touched by this story -- that
is explicitly out of scope and covered by a separate human-only story.

Test paths (all static, all must pass before this story is delivered):
- All three renamed files parse as valid YAML (Step 4).
- `git status` shows genuine renames, not delete+add (Step 5), so file
  history is preserved.
- Repo-wide grep for the old unprefixed names returns hits ONLY in the
  six pre-existing dated documents enumerated in Step 7 -- zero hits in
  `README.md`, `bootstrap/*.yaml`, or anywhere else.
- `bootstrap/infra-apps.yaml` is byte-identical to its state before this
  story (negative check: `git diff --exit-code bootstrap/infra-apps.yaml`
  after Step 8's commits returns 0).

Acceptance Criteria:
1. [Ubiquitous] `bootstrap/platform-aoa.yaml` is renamed (via `git mv`,
   preserving history) to `bootstrap/fleet-platform-aoa.yaml` with
   `metadata.name: fleet-platform-aoa` and the self-referential comment
   updated to reference the new filename; no other field changes.
2. [Ubiquitous] `bootstrap/argocd-apps.yaml` is renamed to
   `bootstrap/fleet-argocd-apps.yaml` with `metadata.name:
   fleet-argocd-apps`; the child template name `'argocd-{{path[1]}}'` and
   every other field is byte-identical to the original.
3. [Ubiquitous] `bootstrap/kargo-apps.yaml` is renamed to
   `bootstrap/fleet-kargo-apps.yaml` with `metadata.name:
   fleet-kargo-apps`; the child template name `'kargo-{{path[1]}}'` and
   every other field is byte-identical to the original.
4. [Unwanted] `bootstrap/infra-apps.yaml` shall not be renamed, and its
   `metadata.name: infra-apps` and content shall not change.
5. [Event] After the renames, all three renamed files parse as valid
   YAML (`ruby -ryaml -e "YAML.load_stream(...)"` exits 0 for each).
6. [Ubiquitous] `README.md`'s two references to
   `bootstrap/platform-aoa.yaml` (Layout section and Quickstart step 2)
   are updated to `bootstrap/fleet-platform-aoa.yaml`; no other line in
   `README.md` changes.
7. [Unwanted] A repo-wide grep for the old unprefixed names
   (`platform-aoa`, `argocd-apps`, `kargo-apps`, negative-lookbehind for
   the `fleet-` prefix) shall return zero hits in `README.md`,
   `bootstrap/*.yaml`, or any file other than the six pre-existing dated
   planning/spec documents enumerated in Step 7 of IMPLEMENTATION above.
8. [Event] `git status` after the renames shows genuine `renamed:`
   entries for all three files (not delete+add pairs).
9. Changes are committed in two commits matching Step 8 exactly (rename
   commit, then docs commit) -- both present in `git log`.
10. Test coverage: all four static checks in TESTING above pass with
    their literal command output recorded as proof (not paraphrased).

MANDATORY SKILLS TO REVIEW:
None identified (pure YAML/Markdown text edit + `git mv`; no framework-
specific pattern applies).

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-05T18:23:54Z dep_added: blocks AF-s8l0
- 2026-08-05T18:24:04Z dep_added: blocks AF-cbot

## Links
- Parent: [[AF-q1il]]
- Blocks: [[AF-s8l0]], [[AF-cbot]]

## Comments
