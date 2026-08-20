---
id: AF-c17x
title: "Human-gated: confirm Sonarr healthy in arr-stack-dev + Kargo trio healthy on kargo cluster"
status: closed
priority: 1
type: task
labels: [human-execution-required, external-integration]
parent: AF-j5rz
created_at: 2026-08-18T18:59:18Z
created_by: ada
updated_at: 2026-08-20T15:12:46Z
content_hash: "sha256:3d14e34fe427c9fe5153d06b392f9a22f1baa0e483be1502ba70a79e2a792d51"
was_blocked_by: [AF-pfbv, AF-o0rw]
closed_at: 2026-08-20T15:12:46Z
close_reason: "Human-verified: Sonarr Synced/Healthy, PVCs Bound, pod Running, Kargo Project/Warehouse/3xStage all reconciled with no Error condition"
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
The user can trust the DRY-proof promotion in Story 9 only once this story's evidence shows a real, healthy app underneath it. The user needs to see, with their own eyes, one complete real app running end to end on the real instance -- not just "the ApplicationSet rendered the right count" (AF-o0rw) but "a real Sonarr pod is Running, its PVCs are Bound, and its Kargo pipeline objects exist and are healthy on the kargo cluster" -- the concrete, observable proof that this design produces a genuinely deployable app, not just a syntactically-plausible-looking generator.

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
- 2026-08-18T18:59:24Z dep_added: blocked_by AF-o0rw
- 2026-08-18T18:59:25Z dep_added: blocked_by AF-pfbv
- 2026-08-18T18:59:25Z status: open -> deferred
- 2026-08-18T19:00:17Z dep_added: blocks AF-4wkn
- 2026-08-18T19:06:20Z dep_added: blocks AF-vm0q
- 2026-08-19T20:26:27Z dep_removed: was_blocked_by AF-pfbv
- 2026-08-20T15:09:22Z dep_removed: was_blocked_by AF-o0rw
- 2026-08-20T15:12:46Z status: deferred -> closed
- 2026-08-20T15:12:47Z dep_removed: no_longer_blocks AF-4wkn
- 2026-08-20T15:12:47Z dep_removed: no_longer_blocks AF-vm0q

## Links
- Parent: [[AF-j5rz]]
- Was blocked by: [[AF-pfbv]], [[AF-o0rw]]

## Comments

### 2026-08-20T15:12:36Z ada
HUMAN-SUPERVISED LIVE VERIFICATION (dispatcher-run, user directly present throughout, following AF-o0rw and AF-pfbv both closed):

Step 1 -- Sonarr Argo CD Application:
$ argocd app get arr-sonarr-dev
Sync Status: Synced to 4.x | Health Status: Healthy
destination: demo1 / arr-stack-dev
Children: PVC arr-sonarr-dev-downloads (Healthy), PVC arr-sonarr-dev-config (Healthy), Service arr-sonarr-dev (Healthy), Deployment arr-sonarr-dev (Healthy)

Step 2 -- PVC binding on demo1:
$ kubectl --context k3d-demo1 -n arr-stack-dev get pvc
arr-sonarr-dev-config      Bound   local-path
arr-sonarr-dev-downloads   Bound   local-path
Both Bound, not Pending. AF-pfbv's StorageClass finding held true live.

Step 3 -- Sonarr pod:
$ kubectl --context k3d-demo1 -n arr-stack-dev get pods
arr-sonarr-dev-766965d76-62c67   1/1   Running   0   5m31s

Step 4 -- Kargo trio on the Akuity-hosted kargo control plane (accessed via the kargo CLI, not a separate kubeconfig context -- 'kargo' is not a distinct k3d cluster, it is Akuity's own managed Kargo hosting, confirmed via terraform output showing kargo_hostname as a distinct akuity.cloud endpoint with kargo_agent_ids registered against demo1/demo2):
$ kargo get project sonarr -> READY: True, 'Project is synced and ready for use'
$ kargo get warehouse --project sonarr -> sonarr warehouse present; -o yaml confirms conditions Ready=True, Healthy=True (ReconciliationSucceeded), and it has ALREADY autonomously discovered real Freight (735f2fe4.../'veering-ibex', origin Warehouse/sonarr, from ghcr.io/hotio/sonarr:release digest sha256:2a67fa7b... -- naturally drifted from AF-8r8l's seed digest since time passed, exactly as that story anticipated and documented as expected/harmless)
$ kargo get stage --project sonarr -> dev/staging/prod all present, all show READY: False / 'Stage has no current Freight' -- confirmed via -o yaml this is reason: NoFreight, NOT an Error condition (no Error reason anywhere in any Stage's conditions). This is the expected pre-promotion state: Freight has been discovered by the Warehouse but not yet promoted into any Stage, which is exactly what Story AF-4wkn (trigger one real promotion) exists to do next -- not a defect here.

AC #1-5 all satisfied. One complete vertical slice (Sonarr, workload + Kargo pipeline) confirmed genuinely live-healthy, real PVCs Bound, real pod Running, real Freight already discovered. Foundation is solid for AF-4wkn's promotion trigger.
