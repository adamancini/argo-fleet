---
id: AF-tqmb
title: "Recreate demo1/demo2 with GitOps-managed storage & ingress; retire akp-infra Terraform state (human-run, gated)"
status: deferred
priority: 0
type: task
labels: [release-gate, human-execution-required, external-integration]
created_at: 2026-08-05T14:34:47Z
created_by: ada
updated_at: 2026-08-05T16:33:40Z
content_hash: "sha256:585ec48caf0669ff5b3bddabc53ac3d8eb48f4e7b7094b0876668171a2c27608"
was_blocked_by: [AF-cu83, AF-uw18, AF-cbot]
parent: AF-q1il
---

## Description
STOP -- READ BEFORE DOING ANYTHING ELSE WITH THIS STORY.

This story is NOT developer-claimable. It is NOT PM-Acceptor-closeable by
evidence review alone. It is a human-executed, human-verified operational
runbook. If you are an autonomous Developer agent, PM-Acceptor agent, or
any other ephemeral agent that has been handed this story to "implement"
or "review for acceptance" -- STOP NOW. Do not run any command in this
story. Do not claim it. Do not close it. Report back to whoever dispatched
you that this story requires a human operator and cannot be executed
autonomously, citing this paragraph. This instruction is not a suggestion
open to your judgment -- it is the explicit, already-approved design
decision recorded in this repo's own plan document
(docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md),
which states in its header: "Do not dispatch Task 7 to an autonomous
implementer the same way as Tasks 1-6 ... If you are an agent executing
this plan and you reach Task 7, stop and hand it back rather than running
these commands yourself." This story is that Task 7, translated into
backlog form. It carries the labels `release-gate` and
`human-execution-required`, and it is deferred on creation specifically so
it will not appear in `nd ready`/`pvg loop next` output -- a human operator
must explicitly run `nd undefer <id>` before this story is even visible as
candidate work, and even then, only a human runs its commands.

Description:
Recreate the real, currently-running k3d clusters `demo1` and `demo2`
without k3s's bundled Traefik/local-path, re-register both as Argo CD/Kargo
destinations from the new `terraform/clusters/` location (AF-4wcm), confirm
both agents report healthy, retire `akp-infra/03-clusters`' old Terraform
state, and sync the three new infrastructure layers (AF-8ik8, AF-vwvq,
AF-qujb). This is the epic's release gate: closing it is what actually
delivers the epic's TARGET STATE. It is `blocked_by` AF-cbot (the epic's
capstone, "Full static verification...") -- every developer-claimable story
in this epic must be complete, committed, and pushed before this story is
even eligible to run. Once Steps 2-7 complete, a user can trust -- because a human operator
(never an automated agent) personally read the STOP-GATE output, not
because an agent asserted it -- that `demo1`/`demo2` are genuinely
re-registered Argo CD/Kargo destinations and that the three new
infrastructure layers' ApplicationSets have each emitted healthy, synced
Applications per cluster; that trust is the observable outcome this story
delivers.

DISCOVERED DURING / WHY THIS IS DIFFERENT IN KIND:
`demo1` currently runs the ENTIRE `akp-platform` demo environment: all four
`guestbook-*` variants (`guestbook-helm`, `guestbook-helm-rendered`,
`guestbook-kustomize`, `guestbook-rendered`), each with dev/staging/prod
namespaces, PLUS `rollouts-app` (dev/staging). `demo2` runs `rollouts-app`
(prod). Both clusters run the Akuity agent stack (`akuity-agent`, Argo CD
application-controller/repo-server, Kargo controller/promotion-controller/
rollouts/webhook) in the `akuity` namespace. Recreating the k3d cluster
destroys ALL of this, by design, per the already-approved design spec.
Re-deploying `akp-platform`'s demo apps afterward
(`argocd app create -f bootstrap/platform-aoa.yaml`, run manually from the
`akp-platform` repo) is explicitly NOT automated by this story or any
story in this epic.

USER INTENT:
The person running this repo needs absolute certainty, verified by their
own eyes against real command output -- not an agent's summary or
assertion -- that (a) they have decided this destruction is acceptable
right now, (b) the new cluster registrations are genuinely healthy before
the old registration is ever touched, and (c) there is zero unexpected
Terraform drift before the old state is retired. No amount of automated
testing substitutes for a human physically confirming these three things,
because the cost of being wrong is real, currently-running infrastructure
and a currently-live demo environment.

STEPS (run by a human operator, one at a time, from
`/Users/ada/src/github.com/adamancini/argo-fleet` unless noted; every step
assumes AF-4wcm through AF-cbot are complete, committed, and pushed):

Step 1 -- Confirm you're prepared to lose what's currently on demo1/demo2.
Re-read the DISCOVERED DURING section above. Do not proceed past this step
without having actually decided this is acceptable right now. This step
has no command -- it is a deliberate human decision point.

Step 2 -- Recreate demo1:
```bash
task cluster:recreate -- demo1
```

Step 3 -- Re-register demo1:
```bash
task cluster:register-agent -- demo1
```
This blocks until the Argo CD agent reports healthy
(`ensure_healthy = true` in AF-4wcm's Terraform module) or times out. If it
times out, check `kubectl --context k3d-demo1 -n akuity get pods` before
retrying -- per the migrated module's own comment, agent pods stuck
`Pending` on a small cluster usually means `tune_agent_resources` isn't
taking effect; confirm `terraform/clusters/terraform.tfvars` has
`tune_agent_resources = true` for `demo1` (copy the value from
`akp-infra/03-clusters/terraform.tfvars` if
`terraform/clusters/terraform.tfvars` doesn't exist yet -- it's gitignored,
so AF-4wcm never created it).

Step 4 -- Repeat for demo2:
```bash
task cluster:recreate -- demo2
task cluster:register-agent -- demo2
```

Step 5 -- STOP-GATE 1: verify both agents are healthy before touching
anything in akp-infra. Run:
```bash
kubectl --context k3d-demo1 -n akuity get pods
kubectl --context k3d-demo2 -n akuity get pods
```
Expected: `akuity-agent`, `argocd-application-controller`,
`argocd-repo-server`, `kargo-controller-*`, `kargo-promotion-controller-*`,
`kargo-webhook` all `Running` on both. This is the FIRST of the design
spec's two explicit human-verification gates. Do not proceed to Step 6
until this is true on both clusters, confirmed by a human physically
reading the `kubectl get pods` output (or the Akuity Platform UI) -- not
by an agent's assertion that it "should be fine."

Step 6 -- STOP-GATE 2: confirm zero Terraform drift, then retire the old
state. From the new location, confirm nothing unexpected is pending:
```bash
cd terraform/clusters
terraform plan
```
Expected: `No changes.` (both clusters were just freshly applied in Steps
3/4, so this should be a no-op). This is the SECOND of the design spec's
two explicit human-verification gates. Only once a human has personally
read `No changes.` in the real `terraform plan` output does the following
proceed:
```bash
mv /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/terraform.tfstate \
   /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/terraform.tfstate.superseded-by-argo-fleet
mv /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/terraform.tfstate.backup \
   /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/terraform.tfstate.backup.superseded-by-argo-fleet
```
(Renaming rather than deleting -- the old state remains on disk as a
record, just no longer a filename Terraform will pick up automatically.)

Step 7 -- Sync the new infra layers. Once `demo1`/`demo2` are registered
and `bootstrap/infra-apps.yaml` (already deployed, pre-existing) has
discovered AF-qujb's `gateway-api-crds`, AF-8ik8's `openebs-localpv`, and
AF-vwvq's `traefik-gateway`, confirm all three Applications go
`Synced`/`Healthy` per cluster via the Argo CD UI or `argocd app list`.
Per AF-qujb's README, `traefik-gateway` may show one failed sync attempt
before `gateway-api-crds` lands -- `selfHeal` retries it automatically;
only investigate further if it's still failing after both are `Synced`.

Step 8 -- Re-deploy akp-platform's demo apps (optional, only if you want
demo1's guestbook apps back):
```bash
argocd app create -f /Users/ada/src/github.com/adamancini/akp-platform/bootstrap/platform-aoa.yaml
```
This is `akp-platform`'s own bootstrap, unrelated to anything in this
epic -- included here only because Step 1 named it as the thing destroyed.

KEY FILES:
None created by this story. It mutates real, live infrastructure state
(k3d clusters, Argo CD/Kargo cluster registrations, `akp-infra`'s state
files on disk) and posts one Terraform-managed drift check -- it does not
touch any file tracked in this repo.

CONSUMES:
Note: this story is `blocked_by` AF-cbot (the epic's capstone) as a pure
dependency edge, not a CONSUMES entry -- AF-cbot produces no artifact (it
is verification-only; see its own PRODUCES: None), so there is nothing for
a CONSUMES signature to cite. The dependency edge alone enforces "every
file this story's Steps 2-7 depend on has already been proven
syntactically valid, byte-faithful to source, and pinned to real chart
versions" before this story is even eligible to run.
- AF-4wcm: terraform/clusters/ -> `module.cluster["<name>"]`,
    `ensure_healthy = true` gate.
    spec: Step 3/4's `task cluster:register-agent` calls
      `terraform apply -target='module.cluster["<name>"]'` from
      `terraform/clusters/`.
    source: AF-4wcm PRODUCES block.
- AF-pydv: Taskfile.yml -> `cluster:recreate`, `cluster:register-agent`.
    spec: Step 2-4 run these tasks verbatim.
    source: AF-pydv PRODUCES block.

PRODUCES:
Live, real-world state only -- not a file in this repo: `demo1`/`demo2`
recreated without k3s's bundled Traefik/local-path; both registered as
Argo CD/Kargo destinations from `terraform/clusters/`; `akp-infra/03-clusters`'
old state files renamed to `*.superseded-by-argo-fleet`; the three new
infra layers (AF-8ik8, AF-vwvq, AF-qujb) synced and healthy on both
clusters.

TESTING:
There is no automated test for this story -- its "tests" ARE the two
STOP-GATEs in Steps 5 and 6, each requiring literal command output a human
has personally read. External-integration note: this story registers
clusters against the real, hosted Akuity Platform API
(`AKUITY_API_KEY_ID`/`AKUITY_API_KEY_SECRET` environment variables,
already provisioned in the operator's shell from prior use with
`akp-infra` -- this story introduces no new secret). Credentials must be
configured and verified against the real Akuity Platform endpoint before
Step 3 -- this cannot be checked by mocked tests; it is a manual/live
smoke-test verification requirement, satisfied by STOP-GATE 1 (Step 5)
itself.

Acceptance Criteria:
1. [Ubiquitous] This story shall remain in `deferred` status until a human
   operator explicitly runs `nd undefer` on it -- it shall never be picked
   up via `nd ready`/`pvg loop next` while deferred.
2. [Unwanted] This story shall not be claimed, executed, or closed by any
   autonomous Developer or PM-Acceptor agent. Any agent that reaches this
   story shall stop and report back per the STOP paragraph at the top of
   this body, without running any of the STEPS commands.
3. [Event] STOP-GATE 1 (Step 5): a human operator has personally run
   `kubectl --context k3d-demo1 -n akuity get pods` and
   `kubectl --context k3d-demo2 -n akuity get pods`, and has recorded the
   literal output (not a paraphrase) as a comment on this issue showing
   `akuity-agent`, `argocd-application-controller`, `argocd-repo-server`,
   `kargo-controller-*`, `kargo-promotion-controller-*`, `kargo-webhook`
   all `Running` on both clusters, BEFORE Step 6 is attempted.
4. [Event] STOP-GATE 2 (Step 6): a human operator has personally run
   `terraform plan` from the new `terraform/clusters/` location and has
   recorded the literal `No changes.` output as a comment on this issue,
   BEFORE the `mv` commands retiring `akp-infra/03-clusters`' old state
   are run.
5. [Ubiquitous] `akp-infra/03-clusters/terraform.tfstate` and
   `terraform.tfstate.backup` are renamed to their
   `*.superseded-by-argo-fleet` counterparts (not deleted) only after
   AC 3 and AC 4 are both satisfied and recorded.
6. [Event] After Step 7, `argocd app list` (or the Argo CD UI) shows
   `gateway-api-crds-demo1`, `gateway-api-crds-demo2`,
   `openebs-localpv-demo1`, `openebs-localpv-demo2`,
   `traefik-gateway-demo1`, `traefik-gateway-demo2` all `Synced`/`Healthy`
   -- with the literal `argocd app list` output recorded as a comment.
7. [Unwanted] This story shall not be marked accepted/closed based solely
   on an agent's summary of what "should have happened" -- acceptance
   requires the human-authored comments from AC 3, AC 4, and AC 6 to
   exist on this issue with their literal command output.
8. [State] While AF-cbot (the capstone) is not yet closed, this story
   shall remain blocked and shall not be undeferred or attempted.

MANDATORY SKILLS TO REVIEW:
None identified. This is a manual operational runbook, not an
implementation task -- no coding skill applies. (If a future skill for
Akuity Platform/k3d cluster operations is added to this environment, it
should be reviewed by the human operator, not by an autonomous agent,
before running these steps.)

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-05T14:34:59Z dep_added: blocked_by AF-cbot
- 2026-08-05T14:34:59Z status: open -> deferred
- 2026-08-05T15:23:07Z dep_added: blocked_by AF-cu83
- 2026-08-05T15:39:37Z dep_removed: was_blocked_by AF-cu83
- 2026-08-05T15:54:18Z dep_added: blocked_by AF-uw18
- 2026-08-05T16:16:07Z dep_removed: was_blocked_by AF-uw18
- 2026-08-05T16:28:39Z dep_removed: was_blocked_by AF-cbot

## Links
- Parent: [[AF-q1il]]
- Was blocked by: [[AF-cu83]], [[AF-uw18]], [[AF-cbot]]

## Comments
