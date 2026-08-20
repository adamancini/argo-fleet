---
id: AF-pfbv
title: "Confirm demo1/demo2 default StorageClass before relying on arr-stack's unset storageClassName"
status: closed
priority: 1
type: task
labels: [human-execution-required]
parent: AF-j5rz
created_at: 2026-08-18T18:56:41Z
created_by: ada
updated_at: 2026-08-19T20:26:27Z
content_hash: "sha256:57ef5ea9be745dd404ab3b23e2bf1f5599f4ba3af4166a0988f1cd2c4dd08eec"
closed_at: 2026-08-19T20:26:27Z
close_reason: "Human-verified: both demo1/demo2 confirm local-path (default) StorageClass"
led_to: [AF-wb16, AF-vm0q]
---

## Description
STOP -- READ BEFORE DOING ANYTHING ELSE WITH THIS STORY.

This story touches the shared, live Akuity-hosted Argo CD/Kargo instance that also serves `akp-platform`'s live demo. Per this repo's established convention (`AF-s8l0`/`AF-tqmb` precedent, both `human-execution-required`), every live check against this instance -- even a read-only one like `kubectl get storageclass` -- is treated as human-run only, not agent-executable. If you are an autonomous Developer agent, PM-Acceptor agent, or any other ephemeral agent handed this story to "implement" or "review for acceptance" -- STOP NOW. Do not run any command in this story. Do not claim it. Do not close it. Report back to whoever dispatched you that this story requires a human operator, citing this paragraph. This story carries the label `human-execution-required` and is deferred on creation specifically so it will not appear in `nd ready`/`pvg loop next` output -- a human operator must explicitly run `nd undefer <id>` before this story is even visible as candidate work.

Description:
Confirm, against the real `demo1` and `demo2` clusters (not the committed git file), whether `local-path` is actually the live default StorageClass on both, before any live deploy of `arr-stack`'s workloads (which set no explicit `storageClassName` on their `config`/`downloads` PVCs, per the design spec) trusts that assumption.

DISCOVERED DURING / WHY THIS IS DIFFERENT IN KIND:
The design spec states: "no explicit storageClass is set on config/downloads PVCs... relies on the cluster's default StorageClass." This repo has a real, previously-hit failure mode (`.vault/knowledge/debug/Non-default StorageClass leaves PVCs permanently unbound without explicit storageClassName.md`): a PVC with no explicit `storageClassName` never binds -- not slowly, forever -- if the cluster's provisioner isn't actually marked default; the only live symptom is a pod stuck `Pending` with `FailedBinding: no persistent volumes available for this claim and no storage class is set`. The CURRENT committed state of `infrastructure/openebs-localpv/argocd/appset.yaml` (verified by reading it directly during this epic's authoring) sets `hostpathClass.isDefaultClass: true` with an explicit code comment explaining exactly why ("charts (akkoma, soju) don't set storageClassName explicitly, so without a default their PVCs bind to nothing, forever") -- a strong positive signal, but a git file describing intent is not the same as confirmed live cluster state, and this repo's own prior epic (`AF-d66a`, AF-d3ax's story body) independently flagged the same caution: "verify current default-class state at implementation time... this MUST NOT be assumed permanent." This story is that verification, applied to arr-stack's specific reliance on the same assumption.

USER INTENT:
The user needs certainty, from their own eyes reading real `kubectl get storageclass` output, that `arr-stack`'s Sonarr (and the other 5 apps) will not silently hang `Pending` forever the first time it's deployed live -- discovering this live, mid-deploy, with a stuck pod and no clear error surfaced in Argo CD's own health status, is exactly the failure mode this story exists to prevent by moving the check earlier and making it explicit. The user can trust the live Sonarr deploy in Story 8 only once this story's recorded output confirms the assumption it relies on.

STEPS (run by a human operator, one at a time, from `/Users/ada/src/github.com/adamancini/argo-fleet`):

Step 1 -- Confirm live default StorageClass on demo1:
```bash
kubectl --context k3d-demo1 get storageclass
```
Expected: exactly one StorageClass shows `(default)` next to its name, and it is `local-path`. Record the literal output.

Step 2 -- Confirm live default StorageClass on demo2:
```bash
kubectl --context k3d-demo2 get storageclass
```
Same expectation as Step 1. Record the literal output.

Step 3 -- If either cluster does NOT show `local-path` marked default:
Do not proceed with any live deploy of `arr-stack`'s workloads until this is resolved. Report back to the dispatcher/Sr PM -- this becomes a P0 bug blocking Story 7 (`AF-<baseline-merge>`), not something to route around by silently adding `storageClassName` to `appset-workloads.yaml` without also recording why the spec's own stated assumption didn't hold.

Step 4 -- If both clusters confirm `local-path (default)`:
Record the confirmation (literal command output, both clusters) in this story's Comments before closing. This is the evidence Story 8 (`AF-<sonarr-health>`, `blocked_by` this story) relies on before trusting a live Sonarr PVC to actually bind.

KEY FILES:
None created or modified -- this is a pure live-state verification story.

OUT OF SCOPE:
- Fixing a non-default StorageClass if Step 3 triggers -- that becomes a separate P0 bug, not silently absorbed into this story or into Story 4/8.
- Any change to `infrastructure/openebs-localpv/argocd/appset.yaml` -- out of scope for this epic entirely; this story only reads live cluster state, it does not modify infrastructure.

DIFF BUDGET:
0 files. This story's only artifact is a recorded comment with literal command output.

TESTING:
Not applicable in the usual sense -- the "test" is the human operator personally reading real `kubectl get storageclass` output on both clusters and recording it. No agent-run test can substitute for this per this repo's established human-execution-required convention for shared-instance live checks.

Acceptance Criteria:
1. [Event] A human operator has personally run `kubectl get storageclass` against both `demo1` and `demo2` and recorded the literal output in this story's Comments.
2. [Ubiquitous] Both clusters show `local-path` marked `(default)` -- or, if not, a P0 bug has been filed and this story remains open/blocked rather than closed on an unresolved negative finding.
3. [Unwanted] No live resource is created, updated, or deleted by this story -- `kubectl get` is the only command run.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory -- confirms StorageClass/PVC binding conventions on Akuity-hosted clusters before drawing conclusions from `kubectl get storageclass` output)

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-18T18:56:46Z status: open -> deferred
- 2026-08-18T18:59:25Z dep_added: blocks AF-c17x
- 2026-08-18T19:06:19Z dep_added: blocks AF-vm0q
- 2026-08-19T20:26:27Z status: deferred -> closed
- 2026-08-19T20:26:27Z dep_removed: no_longer_blocks AF-c17x
- 2026-08-19T20:26:27Z dep_removed: no_longer_blocks AF-vm0q

## Links
- Parent: [[AF-j5rz]]
- Led to: [[AF-wb16]], [[AF-vm0q]]

## Comments

### 2026-08-19T20:26:18Z ada
HUMAN OPERATOR VERIFICATION (per this story's own required protocol):

Step 1 -- demo1:
$ kubectl --context k3d-demo1 get storageclass
NAME                   PROVISIONER        RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   openebs.io/local   Delete          WaitForFirstConsumer   false                  14d

Step 2 -- demo2:
$ kubectl --context k3d-demo2 get storageclass
NAME                   PROVISIONER        RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   openebs.io/local   Delete          WaitForFirstConsumer   false                  14d

Both clusters confirm local-path marked (default). AC #2 satisfied -- arr-stack's unset storageClassName assumption holds on both live clusters. No live resource created/updated/deleted (AC #3) -- kubectl get was the only command run. Verified with the user directly supervising this session (docker/k3d demo2 needed a manual restart first, kubeconfig confirmed current via kubecm cluster-check before running the get).
