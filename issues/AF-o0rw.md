---
id: AF-o0rw
title: "Human-gated: merge arr-stack, confirm wrapper Application + ApplicationSet child counts live"
status: deferred
priority: 1
type: task
labels: [human-execution-required, external-integration]
parent: AF-j5rz
created_at: 2026-08-18T18:58:35Z
created_by: ada
updated_at: 2026-08-18T19:06:10Z
content_hash: "sha256:0ee349047fabb6e04d5e56bd01f7ef8e55ea7fe8bf95ae49842faeac26c36014"
blocks: [AF-c17x]
was_blocked_by: [AF-vm0q]
blocked_by: [AF-6jta]
---

## Description
STOP -- READ BEFORE DOING ANYTHING ELSE WITH THIS STORY.

This story is NOT developer-claimable. It is NOT PM-Acceptor-closeable by evidence review alone. It is a human-executed, human-verified operational runbook that touches the shared, live Argo CD/Kargo instance that already serves the running `akp-platform` demo. If you are an autonomous Developer agent, PM-Acceptor agent, or any other ephemeral agent that has been handed this story to "implement" or "review for acceptance" -- STOP NOW. Do not run any command in this story. Do not claim it. Do not close it. Report back to whoever dispatched you that this story requires a human operator, citing this paragraph and the precedent at `AF-s8l0`/`AF-tqmb` in this repo's own history. This story carries the labels `human-execution-required` and `external-integration`, and it is deferred on creation specifically so it will not appear in `nd ready`/`pvg loop next` output -- a human operator must explicitly run `nd undefer <id>` before this story is even visible as candidate work, and even then, only a human runs its commands.

Description:
Merge the completed `arr-stack` epic branch to `main`, confirm it's actually pushed to `origin/main` (not just merged locally), and prove -- with literal command output a human has personally read -- that (a) no pre-existing resource on the shared instance is disturbed, (b) `fleet-argocd-apps.yaml` picks up `apps/arr-stack/argocd` and creates a healthy wrapper Application `argocd-arr-stack`, and (c) both `arr-stack-workloads` and `arr-stack-kargo` ApplicationSets generate exactly the expected child counts (18 and 6 respectively).

DISCOVERED DURING / WHY THIS IS DIFFERENT IN KIND:
This is the first time anything under `apps/arr-stack/` touches the real shared instance -- everything up to this point (AF-q5yh, AF-8r8l, AF-iv8x's spike, AF-6jta, AF-vm0q's static suite) was authored and verified statically, deliberately, per this epic's two-tier design. This repo's own vault knowledge (`.vault/knowledge/debug/Argo CD targetRevision: HEAD resolves against remote default branch.md`) documents a standing trap directly relevant here: `HEAD` on an Application/ApplicationSet source resolves against the git REMOTE's default branch, not local checkout state -- an unpushed local merge is invisible to a live `syncPolicy.automated` reconcile. Confirm the merge is actually on `origin/main` before expecting anything below to happen.

USER INTENT:
The user needs certainty, verified by their own eyes against real `argocd app list`/`argocd appset list` output -- not an agent's summary -- that merging this epic's branch did not disturb anything already running on the shared instance, and that the new `arr-stack` tree comes up healthy with exactly the child counts the design predicts. The user can trust that story AF-c17x's Sonarr-specific health check rests on a correctly-sized foundation only once this story's recorded output confirms it. A wrong child count (17 instead of 18, 5 instead of 6) is the first observable sign of exactly the kind of cross-file drift Story AF-vm0q's static suite is meant to prevent -- but a live generator can still surprise even a clean static pass (e.g. if the spike's confirmed generator shape behaves differently against real live git-files discovery than a dry-run predicted).

STEPS (run by a human operator, one at a time, from `/Users/ada/src/github.com/adamancini/argo-fleet`; every step assumes AF-6jta -- the last implementation story -- is complete and committed):

Step 0 -- Confirm the static suite is clean BEFORE merging (mechanical dependency note: this story's nd ticket is NOT `blocked_by` AF-vm0q, the capstone, because the capstone's own ticket is `blocked_by` every sibling including this one and would deadlock otherwise -- but the static suite's CONTENT must still be written and passing before this step, regardless of whether AF-vm0q's ticket has formally closed yet):
```bash
ruby e2e/observability_test.rb
```
Expected: 0 failures. Do not proceed to Step 1 if this fails or hasn't been run.

Step 1 -- Baseline the live instance BEFORE merging:
```bash
argocd app list
argocd appset list
```
Confirm and record the literal output: no `arr-*`/`kargo-arr-*`-named resource exists yet, and every pre-existing Application/ApplicationSet (`akkoma-*`, `soju-*`, the 5 infra apps, `kube-prometheus-stack-*`, `fleet-argocd-apps`, `fleet-kargo-apps`, `fleet-platform-aoa`, `akp-platform`'s own `platform-aoa`/`argocd-apps`/`kargo-apps`) is still `Synced`/`Healthy` with its current child count. This is the baseline the rest of this story compares against.

Step 2 -- Merge the epic branch to `main` and confirm it's pushed:
```bash
git log --oneline -n 1 origin/main
```
Confirm the epic's final commit SHA is actually present in `origin/main`'s history, not just in a local branch -- per the `HEAD`-resolves-against-remote trap above, an unpushed merge is invisible to every automated reconcile below.

Step 3 -- Confirm the wrapper Application appears and is healthy:
```bash
argocd app get argocd-arr-stack
```
Expected: `Synced`/`Healthy`, source path `apps/arr-stack/argocd`, `destination.name: in-cluster`. If this Application shows a manifest-generation error referencing `kargo-chart/`, that is a signal the `+argocd:skip-file-rendering` marker (AF-q5yh) didn't work as expected on the real repo-server -- do not attempt to fix it yourself; file a P0 bug and stop.

Step 4 -- Confirm both ApplicationSets generate the expected child counts:
```bash
argocd appset get arr-stack-workloads
argocd appset get arr-stack-kargo
```
Expected: `arr-stack-workloads` shows exactly 18 generated Applications (`arr-sonarr-dev` ... `arr-overseerr-prod`); `arr-stack-kargo` shows exactly 6 (`kargo-arr-sonarr` ... `kargo-arr-overseerr`). A count that's off by even one is grounds to stop and investigate before proceeding to Story 8 -- do not assume "close enough."

Step 5 -- Confirm pre-existing resources are undisturbed:
```bash
argocd app list
argocd appset list
```
Compare against Step 1's baseline: every pre-existing Application/ApplicationSet must show the SAME `Synced`/`Healthy` status and the same (or expectedly-unchanged) child count as before. Any change here that isn't explained by this epic's own additions is a live incident -- stop and follow this repo's documented recovery pattern (`.vault/knowledge/patterns/Recovering corrupted Argo CD App-of-Apps state from source of truth.md`) rather than improvising.

KEY FILES:
None created or modified by this story -- it is a merge + live-verification runbook.

OUT OF SCOPE:
- Confirming any individual workload's Synced/Healthy status beyond the wrapper/ApplicationSet level -- that's Story 8.
- Triggering a real promotion -- that's Story 9 (the release gate).
- Any rollback/cleanup beyond the recovery pattern referenced in Step 5 if something goes wrong -- a real incident here escalates to the user, it does not get silently patched by this story.

DIFF BUDGET:
0 files. This story's only artifact is recorded command output in its Comments.

TESTING:
Not applicable in the usual sense -- every "test" in this story is a human personally reading real command output against the shared instance. `argocd app list`/`appset list`/`app get`/`appset get` are all read-only.

Acceptance Criteria:
1. [Event] The epic's final commit is confirmed present in `origin/main` (not merely a local merge) before any generator is expected to react to it.
2. [Event] `argocd app get argocd-arr-stack` shows `Synced`/`Healthy`.
3. [Event] `argocd appset get arr-stack-workloads` shows exactly 18 generated Applications; `argocd appset get arr-stack-kargo` shows exactly 6.
4. [Unwanted] No pre-existing Application/ApplicationSet on the shared instance (including `akp-platform`'s own `platform-aoa`/`argocd-apps`/`kargo-apps`) changes status or child count as a side effect of this merge.
5. All command output is recorded literally in this story's Comments, read and confirmed by a human operator -- not summarized by an agent.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory)

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-18T18:58:41Z dep_added: blocked_by AF-vm0q
- 2026-08-18T18:58:41Z status: open -> deferred
- 2026-08-18T18:59:24Z dep_added: blocks AF-c17x
- 2026-08-18T19:06:18Z dep_removed: was_blocked_by AF-vm0q
- 2026-08-18T19:06:18Z dep_added: blocked_by AF-6jta

## Links
- Parent: [[AF-j5rz]]
- Blocks: [[AF-c17x]]
- Blocked by: [[AF-6jta]]
- Was blocked by: [[AF-vm0q]]

## Comments
