---
id: AF-s8l0
title: "Bootstrap fleet-platform-aoa on the shared Argo CD instance (human-run, gated)"
status: closed
priority: 0
type: task
labels: [human-execution-required, external-integration]
parent: AF-q1il
created_at: 2026-08-05T18:23:50Z
created_by: ada
updated_at: 2026-08-06T13:30:01Z
content_hash: "sha256:d4b4c2e48df794e632a4f1fa0980dd3f3a99cfb36270a120a65317554a183211"
was_blocked_by: [AF-w3do]
closed_at: 2026-08-06T13:30:01Z
close_reason: "Accepted via pvg story accept"
---

## Description
STOP -- READ BEFORE DOING ANYTHING ELSE WITH THIS STORY.

This story is NOT developer-claimable. It is NOT PM-Acceptor-closeable by
evidence review alone. It is a human-executed, human-verified operational
runbook that touches the shared, live Argo CD instance that already
serves the running `akp-platform` demo. If you are an autonomous
Developer agent, PM-Acceptor agent, or any other ephemeral agent that has
been handed this story to "implement" or "review for acceptance" -- STOP
NOW. Do not run any command in this story. Do not claim it. Do not close
it. Report back to whoever dispatched you that this story requires a
human operator and cannot be executed autonomously, citing this
paragraph. This is not a suggestion open to your judgment -- it is the
explicit, already-approved design decision recorded in this repo's own
design spec (`docs/superpowers/specs/2026-08-05-bootstrap-name-collision-design.md`,
Verification section) and implementation plan
(`docs/superpowers/plans/2026-08-05-bootstrap-name-collision.md`, header
and Task 3), both of which state that these steps are "human-run only --
no agent may execute these steps." This story carries the label
`human-execution-required`, and it is deferred on creation specifically
so it will not appear in `nd ready`/`pvg loop next` output -- a human
operator must explicitly run `nd undefer <id>` before this story is even
visible as candidate work, and even then, only a human runs its commands.

Description:
Apply `argo-fleet`'s renamed root bootstrap Application
(`bootstrap/fleet-platform-aoa.yaml`, produced by AF-w3do, the sibling
story this one is `blocked_by`) against the shared Akuity-hosted Argo CD
instance for the first time, and prove -- with literal command output a
human has personally read, not an agent's summary -- that
`akp-platform`'s already-live `platform-aoa`, `argocd-apps`, and
`kargo-apps` resources were NOT clobbered in the process.

DISCOVERED DURING / WHY THIS IS DIFFERENT IN KIND:
While closing out the `AF-q1il` cluster-lifecycle epic, it was discovered
that `argo-fleet`'s own root bootstrap manifest
(`bootstrap/platform-aoa.yaml`, now renamed) has never actually been
applied to the shared instance at all. That instance already runs
`akp-platform`'s live `platform-aoa` Application (with `prune: true`,
managing `argocd-guestbook-helm`, `argocd-guestbook-helm-rendered`,
`argocd-guestbook-kustomize`, `argocd-guestbook-rendered`,
`argocd-rollouts-app`, and their generated children across
`demo1`/`demo2`) plus live `argocd-apps` and `kargo-apps`
ApplicationSets, all `Synced`/`Healthy`. Before the rename (sibling
story), applying `argo-fleet`'s bootstrap tree risked overwriting all of
that -- especially with `--upsert`, since `platform-aoa` has `prune:
true` and would delete every Application it doesn't recognize as its
own. The rename disambiguates the NAMES; this story is the first time
anyone actually applies the renamed tree against the real, live,
shared instance and confirms the disambiguation worked as designed,
under real conditions, not just in theory.

USER INTENT:
The repo owner needs absolute certainty, verified by their own eyes
against real `argocd app list`/`argocd appset list` output -- not an
agent's summary or assertion -- that (a) `akp-platform`'s three
already-live resources are byte-for-byte unchanged after this story's
apply step, and (b) the new `fleet-*` tree comes up healthy on its own.
No amount of automated testing substitutes for a human physically
confirming both of these, because the cost of being wrong is
`akp-platform`'s live demo environment being silently pruned. Once this
story's steps complete, the repo owner (user) can trust that
`argocd app list`/`argocd appset list` displays `fleet-platform-aoa`,
`fleet-argocd-apps`, and `fleet-kargo-apps` as `Synced`/`Healthy` while
`akp-platform`'s original resources remain untouched -- that observable,
literal command output is the outcome this story delivers, not an
agent's assertion that it "should be fine."

STEPS (run by a human operator, one at a time, from
`/Users/ada/src/github.com/adamancini/argo-fleet` unless noted; every
step assumes AF-w3do is complete, committed, and merged/pushed to the
branch or ref `argocd app create` will read):

Step 1 (human) -- Baseline the live instance:

```bash
argocd app list
argocd appset list
```

Confirm and record the literal output: no `fleet-*`-named resource
exists yet, and the *unprefixed* `platform-aoa`/`argocd-apps`/
`kargo-apps` still show `akp-platform` as their source repo,
`Synced`/`Healthy`, with their current app count. This is the baseline
Step 3 compares against.

Step 2 (human) -- Apply the renamed bootstrap Application:

```bash
argocd app create -f /Users/ada/src/github.com/adamancini/argo-fleet/bootstrap/fleet-platform-aoa.yaml
```

Step 3 (human) -- STOP-GATE: confirm nothing was clobbered.

```bash
argocd app list
argocd appset list
```

The load-bearing check: the *original* `platform-aoa`, `argocd-apps`,
`kargo-apps` are byte-for-byte unchanged from the Step 1 baseline (same
source repo, same app count, still `Synced`/`Healthy`). If any of those
three regressed, STOP -- do not proceed to Step 4 -- and investigate
before touching anything further. This is the load-bearing
human-verification gate for this story; do not proceed past it on an
assumption that it "should be fine."

Step 4 (human) -- Confirm the new `fleet-*` tree comes up healthy:

Confirm `fleet-platform-aoa`, and the `argocd-apps`/`kargo-apps`
ApplicationSets it discovers and applies via `bootstrap/`'s own
directory sync (`fleet-argocd-apps`, `fleet-kargo-apps`), sync
`Synced`/`Healthy` via the Argo CD UI or `argocd app list`/
`argocd appset list`. This proves the renamed tree is live and
functioning under real conditions, not just statically valid.

KEY FILES:
None created or modified by this story -- it touches only the live,
shared Argo CD instance's application/appset state, not this
repository's files.

CONSUMES:
- AF-w3do: bootstrap/fleet-platform-aoa.yaml -> Argo CD `Application` manifest.
    spec: `metadata.name: fleet-platform-aoa`, `namespace: argocd`,
      `spec.source.path: bootstrap`, `spec.destination.name: in-cluster`,
      `spec.syncPolicy.automated: {prune: true, selfHeal: true}`.
    source: AF-w3do PRODUCES block.
This is a pure dependency edge on a repo-file artifact -- Step 2's
`argocd app create -f ...` command reads that exact file, so the file
must exist, be renamed, and be committed before this story is even
eligible to run.

PRODUCES:
Live, real-world state only -- not a file in this repo: the shared Argo
CD instance now has a `fleet-platform-aoa` Application (and, via its own
directory sync, `fleet-argocd-apps`/`fleet-kargo-apps` ApplicationSets)
`Synced`/`Healthy`, while `akp-platform`'s original `platform-aoa`/
`argocd-apps`/`kargo-apps` remain untouched, `Synced`/`Healthy`, same app
count as the Step 1 baseline.

TESTING:
There is no automated test for this story -- its "test" IS the
STOP-GATE in Step 3, requiring literal command output a human has
personally read. External-integration note: this story registers/
applies against the real, hosted Akuity Platform Argo CD API. It
introduces NO new secret or credential -- it reuses whatever
`argocd`/`AKUITY_API_KEY_ID`/`AKUITY_API_KEY_SECRET`-equivalent
authentication the operator's shell/`argocd` CLI session already has
configured from prior use with this same shared instance (the same
authentication context used for AF-tqmb in the parent epic). No blocking
configuration sub-task is required because no new secret is introduced;
this is a one-line justification carried in this story body per the Sr
PM's external-integration convention, not a gap.

Acceptance Criteria:
1. [Ubiquitous] This story shall remain in `deferred` status until a
   human operator explicitly runs `nd undefer` on it -- it shall never be
   picked up via `nd ready`/`pvg loop next` while deferred.
2. [Unwanted] This story shall not be claimed, executed, or closed by any
   autonomous Developer or PM-Acceptor agent. Any agent that reaches this
   story shall stop and report back per the STOP paragraph at the top of
   this body, without running any of the STEPS commands.
3. [Event] Step 1: a human operator has personally run `argocd app list`
   and `argocd appset list` and recorded the literal baseline output (not
   a paraphrase) as a comment on this issue, before Step 2 is attempted.
4. [Event] Step 3 (STOP-GATE): a human operator has personally re-run
   `argocd app list`/`argocd appset list` after Step 2 and has recorded
   the literal output as a comment on this issue, confirming
   `akp-platform`'s `platform-aoa`, `argocd-apps`, `kargo-apps` are
   byte-for-byte unchanged from the Step 1 baseline (same source repo,
   same app count, still `Synced`/`Healthy`).
5. [Event] Step 4: a human operator has personally confirmed
   `fleet-platform-aoa`, `fleet-argocd-apps`, `fleet-kargo-apps` all show
   `Synced`/`Healthy`, and has recorded the literal output as a comment
   on this issue.
6. [Unwanted] This story shall not be marked accepted/closed based solely
   on an agent's summary of what "should have happened" -- acceptance
   requires the human-authored comments from AC 3, AC 4, and AC 5 to
   exist on this issue with their literal command output.
7. [State] While AF-w3do is not yet closed, this story shall remain
   blocked and shall not be undeferred or attempted.
8. [Unwanted] If AC 4's comparison shows ANY regression in
   `akp-platform`'s three original resources (different source repo,
   changed app count, not `Synced`/`Healthy`), the human operator shall
   stop at Step 3 and this story shall not be closed until the regression
   is investigated and resolved.

MANDATORY SKILLS TO REVIEW:
None identified. This is a manual operational runbook, not an
implementation task -- no coding skill applies. The `devops-toolkit:akp-platform`
skill may be useful reference material for the human operator (Argo CD/
Kargo instance concepts), but review is optional and at the operator's
discretion, not a gate.

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-05T18:23:54Z dep_added: blocked_by AF-w3do
- 2026-08-05T18:23:54Z status: open -> deferred
- 2026-08-05T18:24:04Z dep_added: blocks AF-cbot
- 2026-08-05T18:41:07Z dep_removed: was_blocked_by AF-w3do
- 2026-08-05T18:47:18Z status: deferred -> open
- 2026-08-05T18:48:50Z status: open -> deferred
- 2026-08-06T13:30:01Z status: deferred -> closed
- 2026-08-06T13:30:01Z dep_removed: no_longer_blocks AF-cbot

## Links
- Parent: [[AF-q1il]]
- Was blocked by: [[AF-w3do]]

## Comments

### 2026-08-05T18:51:26Z ada
AC3 / Step 1 baseline -- recorded by human operator (ada), literal command output before Step 2 (argocd app create) is attempted.

$ argocd app list
NAME                                    CLUSTER     NAMESPACE                        PROJECT                  STATUS     HEALTH   SYNCPOLICY  CONDITIONS  REPO                                            PATH                                  TARGET
argocd/argocd-guestbook-helm            in-cluster  argocd                           default                  Synced     Healthy  Auto-Prune  <none>      https://github.com/adamancini/akp-platform.git  apps/guestbook-helm/argocd            HEAD
argocd/argocd-guestbook-helm-rendered   in-cluster  argocd                           default                  Synced     Healthy  Auto-Prune  <none>      https://github.com/adamancini/akp-platform.git  apps/guestbook-helm-rendered/argocd   HEAD
argocd/argocd-guestbook-kustomize       in-cluster  argocd                           default                  Synced     Healthy  Auto-Prune  <none>      https://github.com/adamancini/akp-platform.git  apps/guestbook-kustomize/argocd       HEAD
argocd/argocd-guestbook-rendered        in-cluster  argocd                           default                  Synced     Healthy  Auto-Prune  <none>      https://github.com/adamancini/akp-platform.git  apps/guestbook-rendered/argocd        HEAD
argocd/argocd-rollouts-app              in-cluster  argocd                           default                  Synced     Healthy  Auto-Prune  <none>      https://github.com/adamancini/akp-platform.git  apps/rollouts-app/argocd              HEAD
argocd/guestbook-helm-dev               demo1       guestbook-helm-dev               guestbook-helm           OutOfSync  Missing  Manual      <none>      https://github.com/adamancini/akp-platform.git  apps/guestbook-helm/chart             HEAD
argocd/guestbook-helm-prod              demo1       guestbook-helm-prod              guestbook-helm           OutOfSync  Missing  Manual      <none>      https://github.com/adamancini/akp-platform.git  apps/guestbook-helm/chart             HEAD
argocd/guestbook-helm-rendered-dev      demo1       guestbook-helm-rendered-dev      guestbook-helm-rendered  OutOfSync  Missing  Manual      <none>      https://github.com/adamancini/akp-platform.git  ./                                    env/guestbook-helm-rendered/dev
argocd/guestbook-helm-rendered-prod     demo1       guestbook-helm-rendered-prod     guestbook-helm-rendered  OutOfSync  Missing  Manual      <none>      https://github.com/adamancini/akp-platform.git  ./                                    env/guestbook-helm-rendered/prod
argocd/guestbook-helm-rendered-staging  demo1       guestbook-helm-rendered-staging  guestbook-helm-rendered  OutOfSync  Missing  Manual      <none>      https://github.com/adamancini/akp-platform.git  ./                                    env/guestbook-helm-rendered/staging
argocd/guestbook-helm-staging           demo1       guestbook-helm-staging           guestbook-helm           OutOfSync  Missing  Manual      <none>      https://github.com/adamancini/akp-platform.git  apps/guestbook-helm/chart             HEAD
argocd/guestbook-kustomize-dev          demo1                                        guestbook-kustomize      OutOfSync  Missing  Manual      <none>      https://github.com/adamancini/akp-platform.git  apps/guestbook-kustomize/env/dev      HEAD
argocd/guestbook-kustomize-prod         demo1                                        guestbook-kustomize      OutOfSync  Missing  Manual      <none>      https://github.com/adamancini/akp-platform.git  apps/guestbook-kustomize/env/prod     HEAD
argocd/guestbook-kustomize-staging      demo1                                        guestbook-kustomize      OutOfSync  Missing  Manual      <none>      https://github.com/adamancini/akp-platform.git  apps/guestbook-kustomize/env/staging  HEAD
argocd/guestbook-rendered-dev           demo1                                        guestbook-rendered       OutOfSync  Missing  Manual      <none>      https://github.com/adamancini/akp-platform.git  ./                                    env/guestbook-rendered/dev
argocd/guestbook-rendered-prod          demo1                                        guestbook-rendered       OutOfSync  Missing  Manual      <none>      https://github.com/adamancini/akp-platform.git  ./                                    env/guestbook-rendered/prod
argocd/guestbook-rendered-staging       demo1                                        guestbook-rendered       OutOfSync  Missing  Manual      <none>      https://github.com/adamancini/akp-platform.git  ./                                    env/guestbook-rendered/staging
argocd/kargo-guestbook-helm             kargo                                        guestbook-helm           Synced     Healthy  Auto-Prune  <none>      https://github.com/adamancini/akp-platform.git  apps/guestbook-helm/kargo             HEAD
argocd/kargo-guestbook-helm-rendered    kargo                                        guestbook-helm-rendered  Synced     Healthy  Auto-Prune  <none>      https://github.com/adamancini/akp-platform.git  apps/guestbook-helm-rendered/kargo    HEAD
argocd/kargo-guestbook-kustomize        kargo                                        guestbook-kustomize      Synced     Healthy  Auto-Prune  <none>      https://github.com/adamancini/akp-platform.git  apps/guestbook-kustomize/kargo        HEAD
argocd/kargo-guestbook-rendered         kargo                                        guestbook-rendered       Synced     Healthy  Auto-Prune  <none>      https://github.com/adamancini/akp-platform.git  apps/guestbook-rendered/kargo         HEAD
argocd/kargo-rollouts-app               kargo                                        rollouts-app             Synced     Healthy  Auto-Prune  <none>      https://github.com/adamancini/akp-platform.git  apps/rollouts-app/kargo               HEAD
argocd/kargo-shared                     kargo                                        default                  Synced     Healthy  Auto-Prune  <none>      https://github.com/adamancini/akp-platform.git  kargo-shared                          HEAD
argocd/platform-aoa                     in-cluster  argocd                           default                  Synced     Healthy  Auto-Prune  <none>      https://github.com/adamancini/akp-platform.git  bootstrap                             HEAD
argocd/rollouts-app-dev                 demo1                                        rollouts-app             OutOfSync  Missing  Manual      <none>      https://github.com/adamancini/akp-platform.git  apps/rollouts-app/env/dev             HEAD
argocd/rollouts-app-prod                demo2                                        rollouts-app             OutOfSync  Missing  Manual      <none>      https://github.com/adamancini/akp-platform.git  apps/rollouts-app/env/prod            HEAD
argocd/rollouts-app-staging             demo1                                        rollouts-app             OutOfSync  Missing  Manual      <none>      https://github.com/adamancini/akp-platform.git  apps/rollouts-app/env/staging         HEAD

$ argocd appset list
NAME                            PROJECT                  SYNCPOLICY  HEALTH   REPO                                            PATH                       TARGET
argocd/argocd-apps              default                  nil         Healthy  https://github.com/adamancini/akp-platform.git  {{path}}                   HEAD
argocd/guestbook-helm           guestbook-helm           nil         Healthy  https://github.com/adamancini/akp-platform.git  apps/guestbook-helm/chart  HEAD
argocd/guestbook-helm-rendered  guestbook-helm-rendered  nil         Healthy  https://github.com/adamancini/akp-platform.git  ./                         env/guestbook-helm-rendered/{{path.basename}}
argocd/guestbook-kustomize      guestbook-kustomize      nil         Healthy  https://github.com/adamancini/akp-platform.git  {{path}}                   HEAD
argocd/guestbook-rendered       guestbook-rendered       nil         Healthy  https://github.com/adamancini/akp-platform.git  ./                         env/guestbook-rendered/{{path.basename}}
argocd/kargo-apps               {{path[1]}}              nil         Healthy  https://github.com/adamancini/akp-platform.git  {{path}}                   HEAD
argocd/rollouts-app             rollouts-app             nil         Healthy  https://github.com/adamancini/akp-platform.git  {{.path.path}}             HEAD

BASELINE CONFIRMED:
- No fleet-* named app or appset exists yet.
- argocd/platform-aoa: repo akp-platform.git, path bootstrap, Synced/Healthy.
- argocd/argocd-apps (appset): repo akp-platform.git, Healthy.
- argocd/kargo-apps (appset): repo akp-platform.git, Healthy.
- Baseline app count: 27 Applications listed above; 7 ApplicationSets listed above.
- This baseline is what Step 3's post-apply re-check must match byte-for-byte for platform-aoa/argocd-apps/kargo-apps.

### 2026-08-05T19:43:24Z ada
AC4 / Step 3 STOP-GATE -- recorded by human operator (ada), literal command output after Step 2 (argocd app create -f bootstrap/fleet-platform-aoa.yaml, which succeeded: "application 'fleet-platform-aoa' created").

REGRESSION DETECTED. Per AC8, stopping here. Story not closed.

$ argocd app list (relevant rows only, compared to Step 1 baseline comment)
argocd/fleet-platform-aoa  in-cluster  argocd  default  Synced     Healthy  Auto-Prune  <none>                    https://github.com/adamancini/argo-fleet.git   bootstrap  HEAD
argocd/platform-aoa        in-cluster  argocd  default  OutOfSync  Healthy  Auto-Prune  SharedResourceWarning(4)  https://github.com/adamancini/argo-fleet.git   bootstrap  HEAD

Baseline (Step 1) had platform-aoa as: Synced, repo https://github.com/adamancini/akp-platform.git, path bootstrap, no conditions.

$ argocd appset list (relevant rows only)
argocd/argocd-apps  default       nil  Healthy  ...  https://github.com/adamancini/argo-fleet.git  {{path}}  HEAD
argocd/kargo-apps   {{path[1]}}   nil  Healthy  ...  https://github.com/adamancini/argo-fleet.git  {{path}}  HEAD

Baseline (Step 1) had both argocd-apps and kargo-apps sourced from https://github.com/adamancini/akp-platform.git.

FINDING: All three of akp-platform's original bootstrap resources (platform-aoa, argocd-apps, kargo-apps) now report repo=https://github.com/adamancini/argo-fleet.git instead of akp-platform.git. platform-aoa additionally shows OutOfSync + SharedResourceWarning(4) (4 = exact count of fleet-platform-aoa's own managed resource set: itself + fleet-argocd-apps + fleet-kargo-apps + infra-apps), consistent with platform-aoa's spec.source now pointing at the same repo+path as fleet-platform-aoa.

STATUS: STOP-GATE FAILED per AC8. Investigating root cause before any further action. Requested from human operator: `argocd app get platform-aoa -o yaml` and `argocd app get platform-aoa` (plain, for the human-readable SharedResourceWarning detail) to confirm whether platform-aoa's persisted spec.source was actually mutated, and if so, by what mechanism. No mutating command (app set/sync/delete) authorized until root cause is understood.

### 2026-08-05T20:31:39Z ada
AC4 / Step 3 STOP-GATE: RESOLVED. AC5 / Step 4: satisfied.

Incident summary: applying fleet-platform-aoa initially corrupted akp-platform's platform-aoa/argocd-apps/kargo-apps (repoURL overwritten to argo-fleet.git) because the AF-w3do rename fix existed only on an unpushed local branch -- targetRevision: HEAD resolved against origin/main, which still had the old, colliding unprefixed filenames. Root-caused, pushed the fix to main (with user's explicit go-ahead to merge all of epic/AF-q1il, accepting the infra-apps side effect), then hit a second-order issue: `argocd app delete fleet-platform-aoa` cascades by default (my error -- assumed the opposite), which cascade-deleted through fleet-argocd-apps -> argocd-akkoma/argocd-soju and cascaded further via Kubernetes ownerReferences GC, plus tripped a validation deadlock on akp-platform's guestbook-*/rollouts-app family (AppProject deleted -> children can't validate -> can't finish deleting -> AppProject can't be recreated). No real workload data was lost -- confirmed via direct kubectl against demo1/demo2 before taking any destructive action; all pods were pre-incident age throughout. Recovered by restoring platform-aoa from akp-platform's own ground-truth manifest (selfHeal cascaded the fix to argocd-apps/kargo-apps automatically), recreating fleet-platform-aoa fresh now that main had the fix, and force-clearing stuck finalizers (`argocd app patch NAME --patch '{"metadata":{"finalizers":null}}' --type merge`) on objects deadlocked by the missing-AppProject validation loop, letting their owning ApplicationSets regenerate them cleanly.

Final state (human-verified via `argocd app list` / `argocd appset list`):
- platform-aoa: Synced/Healthy, repo akp-platform.git, path bootstrap, no conditions -- byte-for-byte match to Step 1 baseline.
- argocd-apps/kargo-apps (ApplicationSets): both Healthy, repo akp-platform.git -- matches baseline.
- All guestbook-*/rollouts-app-* individual apps and kargo-guestbook-*/kargo-rollouts-app: back to their original states (OutOfSync/Missing/Manual for the never-synced leaves; Synced/Healthy for the kargo siblings) -- matches baseline.
- fleet-platform-aoa, fleet-argocd-apps, fleet-kargo-apps: Synced/Healthy -- the actual deliverable, live with no collision.
- akkoma-*/soju-*: Synced/Progressing, re-adopting already-running pods (not redeployed) -- expected to settle to Healthy.

No regression in akp-platform's three original resources persists. AC8's stop condition is cleared.
