---
id: AF-c17x
title: "Human-gated: confirm Sonarr healthy in arr-stack-dev + Kargo trio healthy on kargo cluster"
status: open
priority: 1
type: task
labels: [human-execution-required, external-integration]
parent: AF-j5rz
created_at: 2026-08-18T18:59:18Z
created_by: ada
updated_at: 2026-08-18T18:59:18Z
content_hash: "sha256:0bfb48f4601b021ce2d1a0206e8095225956d7269dc8c8f17a97946a6740bac6"
---

## Description
STOP -- READ BEFORE DOING ANYTHING ELSE WITH THIS STORY.

This story is NOT developer-claimable. It is NOT PM-Acceptor-closeable by evidence review alone. It is a human-executed, human-verified operational runbook that touches the shared, live Argo CD/Kargo instance that already serves the running `akp-platform` demo. If you are an autonomous Developer agent, PM-Acceptor agent, or any other ephemeral agent that has been handed this story to "implement" or "review for acceptance" -- STOP NOW. Do not run any command in this story. Do not claim it. Do not close it. Report back to whoever dispatched you that this story requires a human operator, citing this paragraph and the precedent at `AF-s8l0`/`AF-tqmb` in this repo's own history. This story carries the labels `human-execution-required` and `external-integration`, and it is deferred on creation specifically so it will not appear in `nd ready`/`pvg loop next` output -- a human operator must explicitly run `nd undefer <id>` before this story is even visible as candidate work, and even then, only a human runs its commands.

Description:
Confirm at least one full app (Sonarr) reaches `Synced`/`Healthy` in the `arr-stack-dev` namespace on `demo1`, and that its Kargo `Project`/`Warehouse`/`Stage` trio is visible and healthy on the `kargo` cluster -- the first real end-to-end health proof of one complete vertical slice through this design, workload and pipeline together.

DISCOVERED DURING / WHY THIS IS DIFFERENT IN KIND:
This story is `blocked_by` both AF-o0rw (confirms the ApplicationSets generated the right COUNT of children) and AF-pfbv (confirms `local-path` is actually the live default StorageClass on `demo1`/`demo2`) -- a right child count with a wrong StorageClass assumption would surface here as Sonarr's `config`/`downloads` PVCs stuck `Pending` forever, exactly the failure mode AF-pfbv exists to catch ahead of time rather than discover here as a confusing, unexplained health failure.

This repo's own vault knowledge on shared-cluster capacity (`.vault/knowledge/conventions/Agent-operating discipline learnings from AF-d66a.md`, "Shared-cluster capacity is part of the test environment") documents that the k3d/Docker-VM host OOMs under concurrent multi-cluster live deploys, producing OOMKills and spurious sync failures that read exactly like real chart defects but aren't -- if this step needs to touch `demo2` at all (it shouldn't, `arr-stack-dev` runs on `demo1` only per the design), serialize rather than running concurrently, and check `docker stats` before concluding a sync failure is a real defect.

USER INTENT:
The user needs to see, with their own eyes, one complete real app running end to end on the real instance -- not just "the ApplicationSet rendered the right count" (AF-o0rw) but "a real Sonarr pod is Running, its PVCs are Bound, and its Kargo pipeline objects exist and are healthy on the kargo cluster" -- the concrete, observable proof that this design produces a genuinely deployable app, not just a syntactically-plausible-looking generator.

STEPS (run by a human operator, one at a time; assumes AF-o0rw and AF-pfbv are both complete):

Step 1 -- Confirm Sonarr's Argo CD Application health:
```bash
argocd app get arr-sonarr-dev
```
Expected: `Synced`/`Healthy`, `destination.namespace: arr-stack-dev`, `destination.name: demo1`.

Step 2 -- Confirm the PVCs actually bound (this is where AF-pfbv's verification pays off or doesn't):
```bash
kubectl --context k3d-demo1 -n arr-stack-dev get pvc
```
Expected: both `config` and (Sonarr has downloads) `downloads` PVCs show `Bound`, not `Pending`. If either shows `Pending`, check `kubectl --context k3d-demo1 -n arr-stack-dev describe pvc <name>` for `FailedBinding` -- if AF-pfbv's verification said `local-path` was default, this should not happen; if it does anyway, that's a live contradiction of AF-pfbv's recorded finding and should be treated as a fresh P0 bug, not silently worked around.

Step 3 -- Confirm the Sonarr pod itself is healthy:
```bash
kubectl --context k3d-demo1 -n arr-stack-dev get pods
```
Expected: the `arr-sonarr-dev` (or equivalent, per the bjw-s app-template's naming) pod is `Running`, `1/1` or `2/2` ready depending on sidecar count.

Step 4 -- Confirm Sonarr's Kargo Project/Warehouse/Stage trio on the kargo cluster:
```bash
kubectl --context <kargo-cluster-context> -n sonarr get project,warehouse,stage
```
(Use whichever kubeconfig context this repo's Taskfile/terraform output resolves for the `kargo` cluster -- see `AGENTS.md`'s `argocd:login`/`kargo:login` Taskfile commands if a direct kubectl context isn't already configured.) Expected: one `Project` named `sonarr`, one `Warehouse` named `sonarr`, three `Stage` objects (`dev`/`staging`/`prod`), all showing a healthy/reconciled status (no `Error` phase).

Step 5 -- Record and compare:
Record all literal output in this story's Comments. If any single check in Steps 1-4 fails, stop and file a P0 bug describing exactly which check failed and the literal error -- do not proceed to Story 9 (the release-gate DRY-claim proof) on a partially-healthy foundation.

KEY FILES:
None created or modified by this story.

OUT OF SCOPE:
- The other 5 apps' health -- this story only proves ONE complete vertical slice (Sonarr); broader fleet-wide health across all 6 apps x 3 stages is not re-litigated here (the static suite, AF-vm0q, already proved structural consistency across all 18+6; this story proves ONE of them is genuinely live-healthy as the representative sample).
- Triggering a real promotion -- that's Story 9.

DIFF BUDGET:
0 files. Recorded command output only.

TESTING:
Not applicable in the usual sense -- every check is a human personally reading real, read-only command output.

Acceptance Criteria:
1. [Event] `argocd app get arr-sonarr-dev` shows `Synced`/`Healthy`.
2. [Event] Both Sonarr PVCs (`config`, `downloads`) in `arr-stack-dev` on `demo1` show `Bound`.
3. [Event] The Sonarr pod in `arr-stack-dev` on `demo1` shows `Running`.
4. [Event] Sonarr's `Project`/`Warehouse`/3x`Stage` trio exists and is healthy on the `kargo` cluster.
5. [Unwanted] No PVC is left `Pending` and silently accepted as "probably fine" -- a `Pending` PVC is a stop-and-file-a-bug condition, not a pass.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory)

## Acceptance Criteria


## Design


## Notes


## History


## Links
- Parent: [[AF-j5rz]]

## Comments
