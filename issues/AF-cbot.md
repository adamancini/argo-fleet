---
id: AF-cbot
title: "Full static verification of Terraform migration & new infrastructure layers"
status: closed
priority: 1
type: task
labels: [capstone, accepted]
parent: AF-q1il
created_at: 2026-08-05T14:33:25Z
created_by: ada
updated_at: 2026-08-05T16:28:40Z
content_hash: "sha256:cec3afab289c20e7f834547e560d68ab8ed36d6bfef9ead7505c456666a3cef1"
was_blocked_by: [AF-4wcm, AF-8ik8, AF-qujb, AF-pydv, AF-vwvq, AF-uw18]
assignee: dev-AF-cbot
follows: [AF-4wcm, AF-8ik8, AF-qujb, AF-pydv, AF-vwvq, AF-uw18, AF-9bc8]
closed_at: 2026-08-05T16:28:39Z
close_reason: "Accepted via pvg story accept"
blocked_by: [AF-9bc8, AF-cu83, AF-i2t5, AF-tqmb]
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
COMPLETED: all 5 static-verification steps executed at 9949b51 with literal output recorded. Step1 YAML 6/6 OK (4 AC files + sealed-secrets appset + tf kustomization). Step2 terraform validate 'Success! The configuration is valid.' (-backend=false, no tfvars present). Step3 6/6 diff -rq empty rc=0 + SHA-256 match on all 8 files, zero whitespace drift; .terraform.lock.hcl and terraform.tfvars.example also identical. Step4 helm search exactly 1 row each for localpv-provisioner 4.5.1 and traefik 41.1.1; gateway-api v1.5.1 tag confirmed via ls-remote. Step5 no live-mutation commit; akp-infra/03-clusters clean with state mtimes predating epic. AC6 git status empty throughout (only gitignored .terraform/ cache). NOTE: epic grew past AC5's five named stories -- AF-wx9b, AF-cu83, AF-uw18 also audited, all file-only. NEXT: PM review; AF-tqmb statically cleared.


## nd_contract
status: accepted

### evidence
- PM closeout applied via pvg story accept on 2026-08-05.

### proof
- [x] Story closed after accepted label was applied.


## nd_contract
status: delivered

### evidence
- Transitioned via pvg story deliver on 2026-08-05.

### proof
- [ ] Developer evidence block must remain authoritative above this contract.


## History
- 2026-08-05T14:33:39Z dep_added: blocked_by AF-4wcm
- 2026-08-05T14:33:40Z dep_added: blocked_by AF-pydv
- 2026-08-05T14:33:40Z dep_added: blocked_by AF-8ik8
- 2026-08-05T14:33:40Z dep_added: blocked_by AF-vwvq
- 2026-08-05T14:33:41Z dep_added: blocked_by AF-qujb
- 2026-08-05T14:34:59Z dep_added: blocks AF-tqmb
- 2026-08-05T15:15:12Z dep_removed: was_blocked_by AF-4wcm
- 2026-08-05T15:27:26Z dep_removed: was_blocked_by AF-8ik8
- 2026-08-05T15:33:50Z dep_removed: was_blocked_by AF-qujb
- 2026-08-05T15:55:23Z dep_added: blocked_by AF-uw18
- 2026-08-05T16:02:31Z dep_removed: was_blocked_by AF-pydv
- 2026-08-05T16:08:13Z dep_removed: was_blocked_by AF-vwvq
- 2026-08-05T16:16:07Z dep_removed: was_blocked_by AF-uw18
- 2026-08-05T16:17:34Z status: open -> in_progress
- 2026-08-05T16:17:34Z auto-follows: linked to predecessor AF-4wcm
- 2026-08-05T16:17:35Z auto-follows: linked to predecessor AF-8ik8
- 2026-08-05T16:17:35Z auto-follows: linked to predecessor AF-qujb
- 2026-08-05T16:17:35Z auto-follows: linked to predecessor AF-pydv
- 2026-08-05T16:17:35Z auto-follows: linked to predecessor AF-vwvq
- 2026-08-05T16:17:35Z auto-follows: linked to predecessor AF-uw18
- 2026-08-05T16:17:35Z claimed by dev-AF-cbot
- 2026-08-05T16:24:51Z status: in_progress -> in_progress
- 2026-08-05T16:24:51Z auto-follows: linked to predecessor AF-9bc8
- 2026-08-05T16:28:39Z status: in_progress -> closed
- 2026-08-05T16:28:39Z dep_removed: no_longer_blocks AF-tqmb
- 2026-08-05T18:24:02Z dep_added: blocked_by AF-9bc8
- 2026-08-05T18:24:03Z dep_added: blocked_by AF-cu83
- 2026-08-05T18:24:03Z dep_added: blocked_by AF-i2t5
- 2026-08-05T18:24:03Z dep_added: blocked_by AF-tqmb

## Links
- Parent: [[AF-q1il]]
- Blocked by: [[AF-9bc8]], [[AF-cu83]], [[AF-i2t5]], [[AF-tqmb]]
- Was blocked by: [[AF-4wcm]], [[AF-8ik8]], [[AF-qujb]], [[AF-pydv]], [[AF-vwvq]], [[AF-uw18]]
- Follows: [[AF-4wcm]], [[AF-8ik8]], [[AF-qujb]], [[AF-pydv]], [[AF-vwvq]], [[AF-uw18]], [[AF-9bc8]]

## Comments

### 2026-08-05T16:24:34Z ada
DELIVERY: AF-cbot -- Full static verification of Terraform migration & new infrastructure layers

Verification-only capstone. No files created, modified, or deleted (AC6 satisfied -- `git status --porcelain` empty at start and end). No commit produced because the story produces no artifact.

Commands run from: /Users/ada/src/github.com/adamancini/argo-fleet/.claude/worktrees/dev-AF-cbot
Branch: story/AF-cbot @ 9949b51 (= epic/AF-q1il HEAD, "Merge branch 'story/AF-uw18' into epic/AF-q1il")
Working tree clean at HEAD; every command below ran against that exact commit.

================================================================
PROOF
================================================================

---------------- STEP 1 -- YAML syntax (AC1) ----------------
$ for f in infrastructure/openebs-localpv/argocd/appset.yaml \
           infrastructure/traefik-gateway/argocd/appset.yaml \
           infrastructure/gateway-api-crds/argocd/appset.yaml \
           Taskfile.yml; do
    ruby -ryaml -e "YAML.load_stream(File.read('$f'))" && echo "OK $f" || echo "FAIL $f"
  done

OK infrastructure/openebs-localpv/argocd/appset.yaml
OK infrastructure/traefik-gateway/argocd/appset.yaml
OK infrastructure/gateway-api-crds/argocd/appset.yaml
OK Taskfile.yml

4/4 OK, 0 FAIL. AC1 PASS.

Supplementary (beyond AC, same command form) -- the epic also ships
infrastructure/sealed-secrets/ and the Terraform kustomization template:
OK infrastructure/sealed-secrets/argocd/appset.yaml
OK terraform/clusters/templates/kustomization.yaml
6/6 OK across every YAML file the epic touches.

Applying devops-toolkit:yaml-kubernetes-validator guidance (no failures to
interpret, so this is a structural sanity pass over the three ApplicationSets):

  openebs-localpv/argocd/appset.yaml
    apiVersion argoproj.io/v1alpha1 | kind ApplicationSet | name openebs-localpv | ns argocd
    generator: list | template name openebs-localpv-{{cluster}}
    source: repoURL=https://openebs.github.io/dynamic-localpv-provisioner chart=localpv-provisioner targetRevision=4.5.1
    destination: {"name"=>"{{cluster}}", "namespace"=>"openebs"}
  traefik-gateway/argocd/appset.yaml
    apiVersion argoproj.io/v1alpha1 | kind ApplicationSet | name traefik-gateway | ns argocd
    generator: list | template name traefik-gateway-{{cluster}}
    source: repoURL=https://traefik.github.io/charts chart=traefik targetRevision=41.1.1
    destination: {"name"=>"{{cluster}}", "namespace"=>"traefik"}
  gateway-api-crds/argocd/appset.yaml
    apiVersion argoproj.io/v1alpha1 | kind ApplicationSet | name gateway-api-crds | ns argocd
    generator: list | template name gateway-api-crds-{{cluster}}
    source: repoURL=https://github.com/kubernetes-sigs/gateway-api.git targetRevision=v1.5.1 path=config/crd/experimental
    destination: {"name"=>"{{cluster}}", "namespace"=>"default"}

  All three carry the required apiVersion/kind/metadata.name, use the current
  argoproj.io/v1alpha1 ApplicationSet API (not deprecated), use lowercase-hyphen
  RFC1123 names, and pin an explicit targetRevision (no `latest`/floating HEAD).
  No schema, naming, or deprecation findings.

---------------- STEP 2 -- terraform validate (AC2) ----------------
$ cd terraform/clusters && terraform init -backend=false && terraform validate

Initializing modules...
- cluster in modules/cluster

Initializing provider plugins...
- Reusing previous version of akuity/akp from the dependency lock file
- Installing akuity/akp v0.13.0...
- Installed akuity/akp v0.13.0 (self-signed, key ID 14B9D2131E732E01)
Partner and community providers are signed by their developers.

Terraform has been successfully initialized!

$ terraform validate
Success! The configuration is valid.

AC2 PASS. Preconditions confirmed rather than assumed:
  - No terraform.tfvars in the repo copy (`ls terraform/clusters | grep -i tfvars`
    -> `terraform.tfvars.example` only), so no real credentials were read.
  - `-backend=false` means no state was read or written.
  - Provider pin akuity/akp 0.13.0 resolved from the committed .terraform.lock.hcl.
  - `terraform init` created the gitignored provider cache
    `terraform/clusters/.terraform/` (shown by `git status --ignored=matching` as
    `!! terraform/clusters/.terraform/`). It is not a repository file and the
    tracked tree stayed clean -- AC6 holds.

---------------- STEP 3 -- byte-fidelity vs akp-infra (AC3) ----------------
SRC=/Users/ada/src/github.com/adamancini/akp-infra/03-clusters
$ diff -rq $SRC/<f> terraform/clusters/<f>   (x6, exit code echoed after each)

rc=0 main.tf
rc=0 outputs.tf
rc=0 providers.tf
rc=0 variables.tf
rc=0 modules/cluster
rc=0 templates/kustomization.yaml

Zero output from all six diffs, all rc=0 -> byte-identical. Not even the
whitespace-only drift AC3 allowed for; `terraform fmt` was a no-op on these files.

SHA-256 cross-check (independent confirmation, per-file including the module's
three files that `diff -rq modules/cluster` covers as a directory):
MATCH main.tf                        cf14a7472e9ac97464bfb328b2fa248493c655286c50c2df02d0c17bbd97847f
MATCH outputs.tf                     ba4dab0012dd15ea3f5424dbbeb3b305a04a31b67c847bb73165c1baf0a2adab
MATCH providers.tf                   dcc9005875b3f8c1f7ff307419057955616a6257bfad339a84fe8801ca4bcd54
MATCH variables.tf                   707fb9e9c1c9db01d6563882c909b171059932551ff3f7fbfb479f5012eecf83
MATCH templates/kustomization.yaml   76ba52e4d76dfd2a3ce97ec7d4d71ef170c30cf6b570be8f5f1a33649af95b9e
MATCH modules/cluster/main.tf        5e214cf1a886815460f7f206fa6bc1cc30a684804ca99cbef2065ab97ac620aa
MATCH modules/cluster/outputs.tf     478b1df9ad1a8f704529b8fa42f7bb397be205f8b611a0bf11a08f5a50a3a4fe
MATCH modules/cluster/variables.tf   4b4f9a187c9161593a069e5bc3836895cc3dee8ad08bbd49ee210ac26a13d485

Supplementary -- the two migrated files AC3 did not enumerate are also identical:
identical: .terraform.lock.hcl
identical: terraform.tfvars.example
=> all 9 files of the migrated stack are byte-identical to their akp-infra source.
AC3 PASS.

---------------- STEP 4 -- chart versions are real (AC4) ----------------
$ helm repo add openebs-localpv https://openebs.github.io/dynamic-localpv-provisioner
"openebs-localpv" already exists with the same configuration, skipping
$ helm repo add traefik https://traefik.github.io/charts
"traefik" already exists with the same configuration, skipping
$ helm repo update openebs-localpv traefik
...Successfully got an update from the "openebs-localpv" chart repository
...Successfully got an update from the "traefik" chart repository
Update Complete.

$ helm search repo openebs-localpv/localpv-provisioner --version 4.5.1
NAME                                CHART VERSION  APP VERSION  DESCRIPTION
openebs-localpv/localpv-provisioner 4.5.1          4.5.1        Helm chart for OpenEBS Dynamic Local PV. For in...

$ helm search repo traefik/traefik --version 41.1.1
NAME            CHART VERSION  APP VERSION  DESCRIPTION
traefik/traefik 41.1.1         v3.7.9       A Traefik based Kubernetes ingress controller

Exactly one matching row each. Both pinned versions are real, currently-published
chart versions. AC4 PASS.

The pins were read back out of the manifests rather than trusted from the story text:
  traefik-gateway/argocd/appset.yaml:24   targetRevision: 41.1.1
  openebs-localpv/argocd/appset.yaml:25   targetRevision: 4.5.1
  gateway-api-crds/argocd/appset.yaml:26  targetRevision: v1.5.1

Supplementary (AC4 correctly exempts gateway-api-crds from a chart-repo check
since it is a plain git source; verified the git ref instead, read-only):
$ git ls-remote --tags https://github.com/kubernetes-sigs/gateway-api.git 'refs/tags/v1.5.1*'
e7677b70ae75d14a4448fba94870e7deea6cf0ad	refs/tags/v1.5.1

---------------- STEP 5 -- no live mutation happened (AC5) ----------------
$ git log --oneline origin/main..HEAD

9949b51 Merge branch 'story/AF-uw18' into epic/AF-q1il
875209b Fix cluster:register-agent on a fresh clone: mkdir -p .kubeconfigs
311520f Fix design spec line 164: isDefaultClass must be an unquoted boolean
66240b7 Merge branch 'story/AF-vwvq' into epic/AF-q1il
7f0aa98 Merge branch 'story/AF-pydv' into epic/AF-q1il
e768a49 Merge branch 'story/AF-wx9b' into epic/AF-q1il
7ae24dd Add Taskfile cluster lifecycle tasks: create, delete, recreate, register-agent
efb0556 merge(epic/AF-q1il): integrate AF-cu83
ca7482e Fix plan Task 3: isDefaultClass must be an unquoted boolean, not "false"
573cc4e merge(epic/AF-q1il): integrate AF-qujb
64f9662 Pin akuity/akp provider to 0.13.0 in terraform/clusters
d9eb114 Merge remote-tracking branch 'origin/main' into story/AF-wx9b
fca5308 merge(epic/AF-q1il): integrate AF-8ik8
50c8ab1 merge(epic/AF-q1il): integrate AF-4wcm
03d34cc chore(paivot): ignore pvg runtime state files
850b342 Add openebs-localpv infrastructure layer for demo1/demo2
5ae238c Migrate cluster/agent registration Terraform from akp-infra
80a8ff5 Add traefik-gateway infra layer for demo1/demo2
dc41db5 Add gateway-api-crds infrastructure layer for demo1/demo2

Merge-to-story attribution (`git log <merge>^1..<merge>^2` per merge):
  AF-4wcm -> 5ae238c  Migrate cluster/agent registration Terraform from akp-infra
  AF-8ik8 -> 850b342  Add openebs-localpv infrastructure layer
  AF-qujb -> dc41db5  Add gateway-api-crds infrastructure layer
  AF-vwvq -> 80a8ff5  Add traefik-gateway infra layer
  AF-pydv -> 7ae24dd  Add Taskfile cluster lifecycle tasks
  AF-wx9b -> ca7482e + 9cd3f16 + 6c3124c (design spec / implementation plan docs)
  AF-cu83 -> 64f9662  Pin akuity/akp provider to 0.13.0 (.terraform.lock.hcl only)
  AF-uw18 -> 875209b  Fix cluster:register-agent: mkdir -p .kubeconfigs
  epic-level: 311520f (design-spec doc fix), 03d34cc + 645e754 (paivot chore/.gitignore)

Total file surface of the entire epic (`git diff --stat origin/main..HEAD`):
20 files changed, 746 insertions(+), 4 deletions(-) -- .gitignore, Taskfile.yml,
2 design/plan docs, 6 infrastructure files, 10 terraform/clusters files. Nothing
outside the argo-fleet repo; no state file, no kubeconfig, no credential file.

Keyword audit of every epic commit message for live mutation:
$ git log origin/main..HEAD --format='%h %s%n%b' | grep -inE "k3d (cluster )?(create|delete|recreate)|terraform apply|tf apply|akp-infra (mutat|modif|chang)|applied against"
66:k3d cluster create/delete and Terraform's var.clusters map both expect
  -> Single hit, and it is a false positive: it is prose in 7ae24dd's commit body
     explaining what the new Taskfile task DEFINES (bare cluster names are what
     `k3d cluster create/delete` expects), not a record of a cluster being created
     or deleted. No commit records `terraform apply`, a real-backend `terraform
     plan`, or a k3d lifecycle operation being executed.

akp-infra source repo confirmed unmutated by this epic:
$ git -C /Users/ada/src/github.com/adamancini/akp-infra status -uno --short
 M 02-kargo/variables.tf
$ stat 03-clusters/terraform.tfstate{,.backup} 03-clusters/terraform.tfvars
2026-08-04 10:54:23 03-clusters/terraform.tfstate
2026-08-04 10:53:48 03-clusters/terraform.tfstate.backup
2026-08-04 10:50:52 03-clusters/terraform.tfvars
  -> 03-clusters (the directory this epic copied FROM) has ZERO modifications:
     no dirty tracked files, and its state/tfvars files were last written
     2026-08-04, before the epic's earliest commit (2026-08-05 10:54:24, dc41db5).
     The one dirty file in akp-infra is 02-kargo/variables.tf, a pre-existing
     user edit (mtime 2026-08-03 23:51, two days before this epic started) in a
     module this epic never reads. AF-4wcm's "Migrate ... from akp-infra" was a
     read-only copy out of akp-infra, not a write into it.
AC5 PASS.

---------------- pvg verify ----------------
$ pvg verify --format text <13 epic artifact paths: 4 appsets, Taskfile.yml, 8 terraform files>
VERIFY: PASSED (0 files scanned, 0 issues)
exit=0
Reported honestly: `0 files scanned` means pvg verify's scanner does not recognise
.yaml/.yml/.tf/.hcl extensions, so this is a clean exit but a no-op, NOT independent
evidence. The substantive static checks for these file types are Steps 1-4 above.

================================================================
ACCEPTANCE CRITERIA VERIFICATION
================================================================
| AC | Requirement | Result | Evidence |
|----|-------------|--------|----------|
| 1 | Step 1 YAML syntax `OK` for all four files, literal output recorded | PASS | 4/4 OK, 0 FAIL (+2 supplementary OK) |
| 2 | Step 2 `terraform validate` -> "Success! The configuration is valid." | PASS | literal init + validate output; no tfvars, `-backend=false` |
| 3 | Step 3 six `diff -rq` produce no output (or whitespace-only) | PASS | all six empty, rc=0; SHA-256 match on all 8 files; 0 whitespace drift |
| 4 | Step 4 both `helm search` print exactly one matching row | PASS | localpv-provisioner 4.5.1 (1 row), traefik 41.1.1 (1 row) |
| 5 | Step 5 `git log --oneline` shows only the epic's stories, no live mutation | PASS (with noted scope expansion) | full log + merge attribution + keyword audit + akp-infra clean check |
| 6 | Shall not create/modify/delete any repository file | PASS | `git status --porcelain` empty before and after; only gitignored `.terraform/` cache from the AC2-mandated init |
| 7 | Shall not run apply / real-backend plan / k3d lifecycle / read real credentials | PASS | only ruby YAML load, `terraform init -backend=false`, `terraform validate`, `diff`, `shasum`, `helm search`, `git log`/`ls-remote`, `pvg verify` -- all read-only; no terraform.tfvars present |

Pass/fail counts: 7/7 AC pass, 0 fail. Step-level: Step 1 6/6 files OK; Step 2 1/1
validate success; Step 3 6/6 diffs clean + 8/8 checksums match; Step 4 2/2 charts
found with exactly one row each; Step 5 0 live-mutation commits found.
Coverage: 100% of the story's five steps executed with literal output recorded;
0 steps skipped, 0 steps asserted without output.
Producing commit SHA: 9949b51 (story/AF-cbot == epic/AF-q1il HEAD).

================================================================
AC5 SCOPE NOTE (flagged, not a failure)
================================================================
AC5 enumerates five stories (AF-4wcm, AF-pydv, AF-8ik8, AF-vwvq, AF-qujb). The
epic branch actually carries three more that were added to AF-q1il after AF-cbot
was authored -- AF-wx9b (design spec + implementation plan docs), AF-cu83 (pin
akuity/akp 0.13.0 in .terraform.lock.hcl), AF-uw18 (mkdir -p .kubeconfigs fix in
cluster:register-agent) -- plus two paivot chore commits. I audited all of them,
not just the five named. Every one is a file-only change inside argo-fleet; none
creates/deletes a k3d cluster, applies Terraform against real state, or writes to
akp-infra. AC5's substantive condition (no live mutation before the release gate)
holds across the epic's full commit set, which is a superset of what AC5 listed.
Calling this out rather than silently pattern-matching the five names.

================================================================
CONSTRAINT STATEMENT
================================================================
Complete list of commands executed for this story, all read-only:
  ruby -ryaml -e 'YAML.load_stream(...)'   (x6, parse only)
  terraform init -backend=false            (provider download to gitignored cache)
  terraform validate
  diff -rq / diff -q / shasum -a 256
  helm repo add (idempotent, no-op) / helm repo update / helm search repo
  git log / git status / git diff --stat / git ls-remote --tags / stat / ls / grep
  pvg verify
NOT run: terraform apply, terraform plan (any backend), terraform destroy,
k3d cluster create|delete|recreate, kubectl, argocd, akuity CLI, helm install|
upgrade, or anything reading Akuity Platform credentials. Nothing in AF-tqmb's
live-mutating scope was touched.

The epic's release-gate story AF-tqmb is now statically cleared to proceed.

================================================================
LEARNINGS
================================================================
- Story ACs can go stale against their own epic. AC5 named five predecessor
  stories; the epic had grown to eight by the time this capstone ran. Auditing
  the actual commit set and reporting the delta is the honest read -- verifying
  only the five named would have left three stories unaudited while technically
  satisfying the AC text.
- `diff -rq` reports nothing on success, so "no output" is indistinguishable from
  "the command never ran" in a pasted transcript. Echoing `rc=$?` after each diff
  and adding an independent SHA-256 pass turns an absence of evidence into
  positive evidence -- worth doing for any diff-based fidelity AC.
- `pvg verify` silently scans 0 files for .yaml/.tf inputs and still exits 0.
  A green "VERIFY: PASSED" on an infra-only story is a no-op, not a signal;
  read the file count, and say so in the proof rather than banking the green.
- Proving a negative (AC5/AC6/AC7 "nothing live was touched") needs positive
  artifacts, not assertions: mtimes on akp-infra's state files predating the
  epic's first commit, `git status` clean in the source repo, `git diff --stat`
  bounding the epic's entire file surface, and an explicit list of every command
  run. A keyword grep alone produced one false positive (commit prose describing
  a Taskfile task) that needed reading in context before it could be cleared.
- `terraform init` is unavoidable before `validate` and leaves a `.terraform/`
  provider cache. On a story with a "modify no files" AC, check it is gitignored
  and show `git status --ignored=matching` -- otherwise it reads as an AC6
  violation to a reviewer.
