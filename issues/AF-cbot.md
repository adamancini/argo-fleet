---
id: AF-cbot
title: "Full static verification of Terraform migration & new infrastructure layers"
status: open
priority: 1
type: task
labels: [capstone]
parent: AF-q1il
created_at: 2026-08-05T14:33:25Z
created_by: ada
updated_at: 2026-08-05T14:37:35Z
content_hash: "sha256:5a80cd2a28a2deb7fd1107c5acbbbc2bb0e79536e14aaacfc8486a4683d5be5b"
blocked_by: [AF-4wcm, AF-pydv, AF-8ik8, AF-vwvq, AF-qujb]
blocks: [AF-tqmb]
---

## Description
Description:
Run the full static-verification pass over everything produced by
AF-4wcm (Terraform migration), AF-pydv (Taskfile tasks), AF-8ik8
(openebs-localpv), AF-vwvq (traefik-gateway), and AF-qujb
(gateway-api-crds): YAML syntax on every new/modified YAML file, HCL
validation on the migrated Terraform, byte-for-byte fidelity of the
Terraform copy against its `akp-infra` source, real-chart-version
cross-checks against the actual chart repositories, and a git-log audit
confirming nothing so far has mutated a live cluster or real Terraform
state. This is the epic's capstone -- it is the single point that proves
every developer-claimable story in this epic is internally consistent and
safe, before the epic's human-gated release-gate story is allowed to touch
anything real.

Context:
This story creates no new files -- it only runs read-only/static commands
against files the five prior stories already produced, and records their
actual output as proof. Per the design plan's own Global Constraint: "No
task in this plan except Task 7 runs a command that mutates a real k3d
cluster, applies real Terraform against live state, or touches
`akp-infra/03-clusters`' existing state files." This story is the
mechanism that PROVES that constraint held across every prior story in
this epic, not just asserts it.

USER INTENT:
The person operating this repo needs one clear, auditable point where they
can trust that everything built so far is internally consistent (files
parse, Terraform is valid HCL, the copy matches its source, chart versions
are real and not typos) BEFORE anyone -- human or agent -- proceeds to the
one story in this epic that touches real, currently-running infrastructure.
A capstone that only checks "did the files get created" without actually
running `terraform validate`/`diff`/`helm search` would not deliver that
trust. Once this story's five steps all pass and their output is recorded,
a user can trust the epic's release-gate story (AF-tqmb) to run against
real infrastructure -- until then, AF-tqmb stays blocked.

IMPLEMENTATION:
Run each of the following from the repo root
(`/Users/ada/src/github.com/adamancini/argo-fleet`) and record the actual
output of every command as proof -- do not summarize or claim success
without the literal output:

Step 1: YAML-syntax-validate every new/modified YAML file:
```bash
for f in infrastructure/openebs-localpv/argocd/appset.yaml \
         infrastructure/traefik-gateway/argocd/appset.yaml \
         infrastructure/gateway-api-crds/argocd/appset.yaml \
         Taskfile.yml; do
  ruby -ryaml -e "YAML.load_stream(File.read('$f'))" && echo "OK $f" || echo "FAIL $f"
done
```
Expected: `OK` for all four.

Step 2: Validate the migrated Terraform (`terraform validate`, not
`plan` -- no state touched):
```bash
cd terraform/clusters
terraform init -backend=false
terraform validate
```
Expected: `Success! The configuration is valid.` -- `-backend=false` and
no `terraform.tfvars` present at this point means this only checks HCL
correctness and provider schema compatibility; it does not read or write
any state and does not require real credentials.

Step 3: Confirm the migrated Terraform is byte-identical to its source:
```bash
diff -rq /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/main.tf terraform/clusters/main.tf
diff -rq /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/outputs.tf terraform/clusters/outputs.tf
diff -rq /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/providers.tf terraform/clusters/providers.tf
diff -rq /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/variables.tf terraform/clusters/variables.tf
diff -rq /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/modules/cluster terraform/clusters/modules/cluster
diff -rq /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/templates/kustomization.yaml terraform/clusters/templates/kustomization.yaml
```
Expected: no output from any `diff` (identical files). Whitespace-only
differences (from an earlier `terraform fmt -recursive` run in AF-4wcm)
are acceptable; anything beyond whitespace means a transcription error
that must be fixed (reopen AF-4wcm or file a bug) before this story can
close.

Step 4: Cross-check chart versions against the real chart repos:
```bash
helm repo add openebs-localpv https://openebs.github.io/dynamic-localpv-provisioner 2>/dev/null
helm repo add traefik https://traefik.github.io/charts 2>/dev/null
helm repo update
helm search repo openebs-localpv/localpv-provisioner --version 4.5.1
helm search repo traefik/traefik --version 41.1.1
```
Expected: each `helm search` prints exactly one matching row -- confirms
the pinned versions in AF-8ik8's and AF-vwvq's `appset.yaml` are real,
currently-published chart versions, not typos.

Step 5: Confirm no story so far touched a live cluster or real Terraform
state:
```bash
git log --oneline
```
Expected: commit messages match AF-4wcm, AF-pydv, AF-8ik8, AF-vwvq,
AF-qujb only (Terraform migration, cluster Taskfile tasks, three infra
layers) -- nothing about creating/deleting/recreating a k3d cluster,
applying Terraform against real state, or touching `akp-infra`. This
confirms the plan's Global Constraint (no live mutation except in the
epic's release-gate story) was honored by every story leading up to this
one.

KEY FILES:
None created or modified by this story -- verification only.

CONSUMES:
- AF-4wcm: terraform/clusters/ -> Terraform stack (all nine files)
    spec: verified via `terraform validate` (Step 2) and `diff -rq`
      against `akp-infra/03-clusters` (Step 3).
    source: AF-4wcm PRODUCES block.
- AF-pydv: Taskfile.yml -> cluster:create/delete/recreate/register-agent
    spec: verified via the YAML-syntax check (Step 1); `task --list`
      output was already recorded as proof in AF-pydv itself and is not
      re-run here.
    source: AF-pydv PRODUCES block.
- AF-8ik8: infrastructure/openebs-localpv/argocd/appset.yaml -> chart
    localpv-provisioner 4.5.1
    spec: verified via the YAML-syntax check (Step 1) and the
      `helm search repo openebs-localpv/localpv-provisioner --version
      4.5.1` chart-version cross-check (Step 4).
    source: AF-8ik8 PRODUCES block.
- AF-vwvq: infrastructure/traefik-gateway/argocd/appset.yaml -> chart
    traefik 41.1.1
    spec: verified via the YAML-syntax check (Step 1) and the
      `helm search repo traefik/traefik --version 41.1.1` chart-version
      cross-check (Step 4).
    source: AF-vwvq PRODUCES block.
- AF-qujb: infrastructure/gateway-api-crds/argocd/appset.yaml -> Gateway
    API CRDs v1.5.1
    spec: verified via the YAML-syntax check (Step 1). No chart-repo
      cross-check applies (plain git source, not a Helm chart repo).
    source: AF-qujb PRODUCES block.

PRODUCES:
None -- this is a verification-only story. Its deliverable is the
recorded, literal output of Steps 1-5 above (as this story's proof of
work), not a new file.

TESTING:
This entire story IS the testing/verification step for the epic's
developer-claimable stories. There is no separate "how do we verify this
worked" layer -- the five steps in IMPLEMENTATION are both the
implementation and the test. Coverage requirement: every step's actual
command output must be recorded as proof; a step that is skipped or whose
output is asserted rather than shown is an incomplete delivery of this
story.

Acceptance Criteria:
1. [Ubiquitous] Step 1 (YAML syntax) reports `OK` for all four files
   listed, with the literal ruby/YAML output recorded as proof.
2. [Event] Step 2 (`terraform init -backend=false && terraform validate`)
   reports `Success! The configuration is valid.`, with the literal
   output recorded as proof.
3. [Event] Step 3 (`diff -rq` x6) produces no output, or only
   whitespace-only differences explained by AF-4wcm's `terraform fmt`
   run, with the literal (empty or whitespace-diff) output recorded as
   proof.
4. [Event] Step 4 (`helm search repo ... --version ...` x2) each print
   exactly one matching row for `localpv-provisioner` 4.5.1 and `traefik`
   41.1.1, with the literal output recorded as proof.
5. [Event] Step 5 (`git log --oneline`) shows commits corresponding only
   to AF-4wcm, AF-pydv, AF-8ik8, AF-vwvq, AF-qujb -- no commit message
   referencing k3d cluster creation/deletion, `terraform apply` against
   real state, or `akp-infra` mutation.
6. [Unwanted] This story shall not create, modify, or delete any file in
   the repository -- its only output is verification-command results.
7. [Unwanted] This story shall not run `terraform apply`, `terraform
   plan` against a real backend, `k3d cluster create/delete/recreate`, or
   any command that reads real Akuity Platform credentials.

MANDATORY SKILLS TO REVIEW:
`devops-toolkit:yaml-kubernetes-validator` -- Step 1 validates Kubernetes/
Argo CD YAML manifests; load the skill and apply its review guidance when
interpreting any YAML validation failure.

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-05T14:33:39Z dep_added: blocked_by AF-4wcm
- 2026-08-05T14:33:40Z dep_added: blocked_by AF-pydv
- 2026-08-05T14:33:40Z dep_added: blocked_by AF-8ik8
- 2026-08-05T14:33:40Z dep_added: blocked_by AF-vwvq
- 2026-08-05T14:33:41Z dep_added: blocked_by AF-qujb
- 2026-08-05T14:34:59Z dep_added: blocks AF-tqmb

## Links
- Parent: [[AF-q1il]]
- Blocks: [[AF-tqmb]]
- Blocked by: [[AF-4wcm]], [[AF-pydv]], [[AF-8ik8]], [[AF-vwvq]], [[AF-qujb]]

## Comments
