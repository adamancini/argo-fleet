---
id: AF-4wkn
title: "Human-gated release proof: trigger arr-stack promotion, confirm DRY auto-pickup"
status: closed
priority: 0
type: task
labels: [human-execution-required, external-integration]
parent: AF-j5rz
created_at: 2026-08-18T19:00:10Z
created_by: ada
updated_at: 2026-08-20T16:00:28Z
content_hash: "sha256:8841eb8af686fcb3d513232e049000661e1d6d822f537eab45d890dcfdf69dbd"
was_blocked_by: [AF-vm0q, AF-c17x]
closed_at: 2026-08-20T16:00:28Z
close_reason: "Human-verified: real Kargo promotion, render-diff confined to arr-sonarr-dev only, live pod runs new digest, appset-workloads.yaml never touched -- DRY claim proven end-to-end"
---

## Description
STOP -- READ BEFORE DOING ANYTHING ELSE WITH THIS STORY.

This story is NOT developer-claimable. It is NOT PM-Acceptor-closeable by evidence review alone. It is a human-executed, human-verified operational runbook that touches the shared, live Argo CD/Kargo instance that already serves the running `akp-platform` demo. If you are an autonomous Developer agent, PM-Acceptor agent, or any other ephemeral agent that has been handed this story to "implement" or "review for acceptance" -- STOP NOW. Do not run any command in this story. Do not claim it. Do not close it. Report back to whoever dispatched you that this story requires a human operator, citing this paragraph and the precedent at `AF-s8l0`/`AF-tqmb` in this repo's own history. This story carries the labels `human-execution-required` and `external-integration`, and it is deferred on creation specifically so it will not appear in `nd ready`/`pvg loop next` output -- a human operator must explicitly run `nd undefer <id>` before this story is even visible as candidate work, and even then, only a human runs its commands.

This is the epic's final live proof: closing it is what actually delivers the epic's TARGET STATE. It is `blocked_by` AF-c17x (Sonarr's live health must already be confirmed) -- every developer-claimable and prior human-gated story in this epic must be complete before this story is even eligible to run. (The epic's capstone, AF-vm0q, is in turn `blocked_by` this story -- the capstone closes LAST, re-confirming the static suite still holds after this story's live promotion, which is why this story is not itself blocked_by the capstone: that dependency direction would deadlock the two ledger entries against each other.)

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
- 2026-08-18T19:00:18Z status: open -> deferred
- 2026-08-18T19:06:18Z dep_removed: was_blocked_by AF-vm0q
- 2026-08-18T19:06:21Z dep_added: blocks AF-vm0q
- 2026-08-20T15:12:46Z dep_removed: was_blocked_by AF-c17x
- 2026-08-20T16:00:28Z status: deferred -> closed
- 2026-08-20T16:00:28Z dep_removed: no_longer_blocks AF-vm0q

## Links
- Parent: [[AF-j5rz]]
- Was blocked by: [[AF-vm0q]], [[AF-c17x]]

## Comments

### 2026-08-20T16:00:18Z ada
HUMAN-SUPERVISED LIVE VERIFICATION (dispatcher-run, user directly present throughout, following AF-vm0q... wait, capstone AF-vm0q not yet run -- see note below on dependency ordering):

Step 1 -- render-diff baseline captured before promotion (18 results, array shape as expected):
$ argocd appset generate apps/arr-stack/argocd/appset-workloads.yaml -o json --grpc-web > before.json
arr-sonarr-dev digest (before): sha256:e029ce1988241f9d213ebafbc73012c4684d3c698523f18b597bb014b88d551a (AF-8r8l's original seed)

Step 2 -- promotion triggered via path (b), the real Warehouse-discovered Freight, by the user:
$ kargo promote --project sonarr --stage dev --freight-alias veering-ibex
REAL INCIDENT DISCOVERED AND FIXED along the way: first promotion attempt (dev.01m0fy1nrzwp97q1svkj2s4t4q.735f2fe) Errored at the git-push step: 'fatal: could not read Username for https://github.com: No such device or address'. Root cause: NONE of the 6 new Kargo projects created by this epic (sonarr/radarr/lidarr/bazarr/prowlarr/seerr) had git write credentials registered -- a genuine backlog gap, since AGENTS.md's own onboarding checklist item ('New Kargo project -> new git write credentials for it') was never captured as a story in this epic, unlike akkoma/soju which already had per-project github-creds registered 14 days prior. User registered credentials live (kargo create repo-credentials); a second promotion (dev.01m0fy7pf8baqxgvrn5jc4hvrb.735f2fe) then Succeeded.

Step 3 -- commit confirmed on origin/main:
$ git log --oneline -n 3 origin/main -- apps/arr-stack/env/sonarr/dev/release.yaml
e812598 arr-stack/sonarr/dev: promote image sha256:2a67fa7b63de93f8fe4b2292b2ba968b4c6beb33dfa7b53eb94018c16f6ffc9a
Confirmed committed by 'Kargo <no-reply@kargo.io>', exactly 1 file changed (release.yaml), 1 line.

Step 4 -- render-diff after promotion (had to recapture once -- the first appset-generate call raced ahead of the repo-server's own git refresh and returned a stale snapshot; recaptured ~45s later):
$ diff -u before.json after.json
Diff touches ONLY arr-sonarr-dev's rendered helm.values digest field: e029ce19... -> 2a67fa7b.... All other 17 rendered Applications byte-identical. Confirmed via direct field extraction on both files independently, not just the diff tool.

Step 5 -- live sync + running pod confirmed:
$ argocd app get arr-sonarr-dev -> Synced to 4.x / Healthy
$ kubectl --context k3d-demo1 -n arr-stack-dev get pod ... -o jsonpath='{.items[0].spec.containers[0].image}'
ghcr.io/hotio/sonarr@sha256:2a67fa7b63de93f8fe4b2292b2ba968b4c6beb33dfa7b53eb94018c16f6ffc9a
Fresh pod (arr-sonarr-dev-7fd9fb7bbf-qhg7r), 1/1 Running, 25s old at check time -- the rolling update from the digest change had already happened.

Step 6 -- no manual appset-workloads.yaml edit:
$ git log --oneline -n 5 origin/main -- apps/arr-stack/argocd/appset-workloads.yaml
Most recent commit is 01a49e4 (AF-wb16's hotfix, already accounted for) -- zero commits since, confirming this file was never touched to make the promotion take effect.

Step 5-extra -- no app/stage other than sonarr/dev touched:
$ git show --stat e812598 -> exactly 1 file (apps/arr-stack/env/sonarr/dev/release.yaml), 1 line changed.

NOTE ON DEPENDENCY ORDERING: this story's own header states it assumes 'AF-vm0q and AF-c17x are both complete' as a precondition, but the actual nd dependency graph (and the epic's own design intent, documented on AF-vm0q's own body: 'capstone... closes LAST, re-confirming the static suite still holds after this story's live promotion') has AF-vm0q blocked_by THIS story, not the reverse -- AF-vm0q could not possibly have run first without a dependency cycle. Proceeded per the actual dependency graph and the epic's own stated intent (capstone last), not per this story's own header prose, which appears to be a copy-paste inconsistency from AF-c17x's equivalent precondition line. Flagging for the record, not blocking.

AC #1-6 ALL SATISFIED. The epic's central DRY claim is proven end-to-end: a real Kargo promotion updated release.yaml, the generated ApplicationSet auto-re-rendered with zero manual edits, and a real pod now runs the newly-promoted image. Epic's target state delivered. Only the capstone (AF-vm0q) and epic completion gate remain.
