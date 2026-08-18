---
id: AF-4wkn
title: "Human-gated release proof: trigger arr-stack promotion, confirm DRY auto-pickup"
status: open
priority: 0
type: task
labels: [human-execution-required, external-integration, release-gate]
parent: AF-j5rz
created_at: 2026-08-18T19:00:10Z
created_by: ada
updated_at: 2026-08-18T19:00:10Z
content_hash: "sha256:3633f83ee0fdd9e76207b4e705baf315c7ae424ac5104585f82d1ccb34ecae3a"
blocked_by: [AF-vm0q, AF-c17x]
---

## Description
STOP -- READ BEFORE DOING ANYTHING ELSE WITH THIS STORY.

This story is NOT developer-claimable. It is NOT PM-Acceptor-closeable by evidence review alone. It is a human-executed, human-verified operational runbook that touches the shared, live Argo CD/Kargo instance that already serves the running `akp-platform` demo. If you are an autonomous Developer agent, PM-Acceptor agent, or any other ephemeral agent that has been handed this story to "implement" or "review for acceptance" -- STOP NOW. Do not run any command in this story. Do not claim it. Do not close it. Report back to whoever dispatched you that this story requires a human operator, citing this paragraph and the precedent at `AF-s8l0`/`AF-tqmb` in this repo's own history. This story carries the labels `human-execution-required`, `external-integration`, and `release-gate`, and it is deferred on creation specifically so it will not appear in `nd ready`/`pvg loop next` output -- a human operator must explicitly run `nd undefer <id>` before this story is even visible as candidate work, and even then, only a human runs its commands.

This is the epic's release gate: closing it is what actually delivers the epic's TARGET STATE. It is `blocked_by` AF-vm0q (the epic's capstone -- the static verification suite must be clean) and AF-c17x (Sonarr's live health must already be confirmed) -- every developer-claimable and prior human-gated story in this epic must be complete before this story is even eligible to run.

Description:
Trigger one real promotion for Sonarr (bump `apps/arr-stack/env/sonarr/dev/release.yaml` by hand, or let the `Warehouse` discover a real tag change under the `release` channel) and confirm the workload Application `arr-sonarr-dev` picks up the new tag automatically -- with ZERO manual edit to `appset-workloads.yaml` -- as the actual, concrete proof of this epic's central DRY claim: that Kargo promoting to a shared `release.yaml` file is enough for the generator to re-render on its own, the same auto-pickup mechanism `akkoma`/`soju` already rely on, now proven to also work for a generated (not hand-written) ApplicationSet.

DISCOVERED DURING / WHY THIS IS DIFFERENT IN KIND:
Every prior story in this epic (including the two other human-gated ones, AF-o0rw and AF-c17x) proves the SYSTEM IS CORRECTLY ASSEMBLED. This story is the only one that proves the SYSTEM ACTUALLY DOES THE THING IT WAS BUILT FOR -- automatic re-rendering on promotion, with no manual `appset-workloads.yaml` edit. Per the render-diff verification primitive already established in this repo (`.vault/knowledge/patterns/Render-diff verification primitive for ApplicationSet changes.md`), the strongest proof available is a byte-level before/after render comparison via `argocd appset generate`, not just "the Application eventually showed the new tag."

USER INTENT:
The user needs to see this specific causal chain happen for real, once, with their own eyes: a git commit to `release.yaml` -> the `arr-stack-workloads` ApplicationSet's `git files` generator re-discovers it -> `arr-sonarr-dev`'s rendered spec updates -> Argo CD syncs the new image tag -- with no human touching `appset-workloads.yaml` in between. This is the entire reason the epic exists; every other story is scaffolding in service of proving this one causal chain works.

STEPS (run by a human operator, one at a time; assumes AF-vm0q and AF-c17x are both complete):

Step 1 -- Render-diff baseline (before the promotion):
```bash
argocd appset generate apps/arr-stack/argocd/appset-workloads.yaml -o json --grpc-web > /tmp/arr-stack-workloads-before.json
```
Guard the known JSON-shape footgun: `-o json` emits a bare object for a single result and an array for multiple -- this call returns 18 results, so expect an array; confirm the script/inspection handles that shape, don't assume object shape from a prior single-result experience.

Step 2 -- Trigger the promotion. Either:
(a) Hand-edit `apps/arr-stack/env/sonarr/dev/release.yaml`'s `imageTag` field, commit, and push to `main` directly (simulating what Kargo's promotion task would do), OR
(b) Let Sonarr's real `Warehouse` discover a genuine new tag under the `release` channel and allow its `dev` Stage to auto-promote for real, then confirm via `kargo` CLI or the Akuity Platform UI that a `Promotion` object completed successfully.
Either path is acceptable evidence -- (b) is the stronger, more realistic proof if a real tag change is available to observe within a reasonable window; (a) is an acceptable substitute if not. Record which path was used.

Step 3 -- Confirm the git commit landed on `origin/main` (same `HEAD`-resolves-against-remote caution as AF-o0rw):
```bash
git log --oneline -n 3 origin/main -- apps/arr-stack/env/sonarr/dev/release.yaml
```

Step 4 -- Render-diff after the promotion:
```bash
argocd appset generate apps/arr-stack/argocd/appset-workloads.yaml -o json --grpc-web > /tmp/arr-stack-workloads-after.json
diff -u /tmp/arr-stack-workloads-before.json /tmp/arr-stack-workloads-after.json
```
Expected: a diff touching ONLY `arr-sonarr-dev`'s rendered `image.tag`/digest-related field(s) -- every other one of the 18 rendered Applications must be byte-identical before/after. A diff touching anything else (a different app, a different field) is a signal something unexpected happened and should be investigated before declaring success.

Step 5 -- Confirm the live Application actually synced the new value:
```bash
argocd app get arr-sonarr-dev
```
Expected: `Synced`/`Healthy`, and the running Sonarr pod's actual image reflects the new tag/digest (`kubectl --context k3d-demo1 -n arr-stack-dev get pod -o jsonpath='{.items[0].spec.containers[0].image}'`).

Step 6 -- Confirm no manual `appset-workloads.yaml` edit occurred:
```bash
git log --oneline -n 5 origin/main -- apps/arr-stack/argocd/appset-workloads.yaml
```
Expected: no new commit touching this file since AF-6jta's original implementation -- the entire point being proven is that this file was NEVER touched to make the promotion take effect.

Step 7 -- Record the full evidence trail (before/after render-diff, git log excerpts, `argocd app get` output, pod image) in this story's Comments before closing.

KEY FILES:
`apps/arr-stack/env/sonarr/dev/release.yaml` may be hand-edited in Step 2(a) as part of the human runbook -- this is the one and only file this story may touch, and only as the triggering action, not as a "fix."

OUT OF SCOPE:
- Promoting any app other than Sonarr, or any stage other than `dev` -- one vertical slice is sufficient proof of the mechanism; repeating it for all 18 combinations is not required and not requested.
- Any edit to `appset-workloads.yaml`, `appset-kargo.yaml`, or `kargo-chart/` -- if evidence in Step 4/6 shows one of these needed a manual edit to make the promotion take effect, that is a FAILURE of this story's core claim, not a step to route around by editing the file and re-running.

DIFF BUDGET:
At most 1 file touched (`apps/arr-stack/env/sonarr/dev/release.yaml`, only if Step 2(a) is used), 0 lines changed elsewhere.

TESTING:
Not applicable in the usual sense -- the render-diff (`argocd appset generate` before/after, byte-level `diff`) IS the test, and it is the strongest verification tool this repo has established for exactly this class of claim.

Acceptance Criteria:
1. [Event] A real promotion (hand-edit or live Warehouse discovery) updates `apps/arr-stack/env/sonarr/dev/release.yaml`'s `imageTag` and lands on `origin/main`.
2. [Event] `argocd appset generate` before/after render-diff shows a change confined to `arr-sonarr-dev` only -- all other 17 rendered Applications are byte-identical before/after.
3. [Event] `arr-sonarr-dev` shows `Synced`/`Healthy` with the new tag/digest actually running in the live pod.
4. [Unwanted] `appset-workloads.yaml` is not edited at any point during this story -- confirmed via git log, not assumed.
5. [Unwanted] No app other than Sonarr and no stage other than `dev` is touched by this story.
6. Full evidence trail (before/after render-diff, git log excerpts, live app/pod state) is recorded in this story's Comments, personally read by a human operator.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory)

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-18T19:00:17Z dep_added: blocked_by AF-vm0q
- 2026-08-18T19:00:17Z dep_added: blocked_by AF-c17x

## Links
- Parent: [[AF-j5rz]]
- Blocked by: [[AF-vm0q]], [[AF-c17x]]

## Comments
