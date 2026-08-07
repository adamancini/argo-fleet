---
id: AF-ogxu
title: "Spike: confirm Argo CD clusters generator discovers demo1/demo2 on the Akuity-hosted instance"
status: closed
priority: 0
type: task
labels: [spike, accepted]
parent: AF-d66a
created_at: 2026-08-07T15:06:16Z
created_by: ada
updated_at: 2026-08-07T15:34:24Z
content_hash: "sha256:fe61c79aa6db2be874f06d88a96b8558480b86c5f2a93bd5e78ac630ff19558c"
assignee: dev-AF-ogxu
closed_at: 2026-08-07T15:33:33Z
close_reason: "Accepted spike: GO decision with mandatory selector recorded in issue, independently re-verified against live instance"
led_to: [AF-c8p4, AF-d3ax, AF-qmy9]
---

## Description
Description:
Determine, with evidence (not assumption), whether Argo CD's ApplicationSet `clusters: {}` generator returns `demo1`/`demo2` on this repo's Akuity-hosted Argo CD instance, and if so, exactly which template fields it exposes (`{{name}}`, `{{server}}`, label-derived fields, or something else). This is a verification spike, not an implementation story -- it produces a decision, not a shipped feature.

Context:
This repo (`argo-fleet`) is a personal GitOps repo (Argo CD + Kargo) targeting two k3d clusters, `demo1` and `demo2`, registered against an Akuity-hosted Argo CD/Kargo instance (not plain OSS Argo CD) via Terraform (`terraform/clusters/`, using the `akp` provider's `akp_cluster` + `akp_kargo_agent` resources -- see `terraform/clusters/main.tf` and `terraform/clusters/modules/cluster/main.tf`). Every current `infrastructure/*/argocd/appset.yaml` (5 of them: `sealed-secrets`, `traefik-gateway`, `gateway-api-crds`, `openebs-localpv`, `argo-rollouts-crds`) hardcodes cluster targeting with a static `list` generator:

```yaml
generators:
- list:
    elements:
    - cluster: demo1
    - cluster: demo2
```

The user wants this replaced everywhere with Argo CD's built-in `clusters: {}` ApplicationSet generator so cluster targeting is discovered automatically -- no file edits needed when a third cluster joins the fleet (or when the fleet eventually migrates to the real `annarchy.net`/`staging.annarchy.net` clusters).

The risk: standard OSS Argo CD's `clusters: {}` generator works by listing Kubernetes `Secret` objects labeled `argocd.argoproj.io/secret-type: cluster` in the Argo CD namespace -- these are normally hand-authored (or created by `argocd cluster add`) with the target cluster's server URL and credentials embedded. On this repo's Akuity-hosted instance, cluster registration does NOT go through that mechanism: `devops-toolkit:akp-platform`'s argocd-declarative-setup reference states explicitly (Akuity-hosted divergence section): "cluster/agent registration instead goes through the `akp` Terraform provider... the Akuity Agent connects outbound and no cluster credentials are stored centrally, so this Secret-based mechanism isn't something you author yourself here." Whether Akuity's control plane creates an equivalent, generator-discoverable Secret under the hood for each Terraform-registered cluster is genuinely unknown from documentation alone -- this story exists to answer that question empirically, against the real instance, before 5 existing files and 1 new file are all rewritten to depend on the answer.

USER INTENT:
The user needs confidence that switching to the `clusters` generator is not going to silently break cluster targeting on 5 already-working infra apps. They explicitly asked for a spike specifically because this is "cheap to fail fast on" -- they would rather learn the generator doesn't work on this instance from one throwaway test than from 5 broken production ApplicationSets.

IMPLEMENTATION:
1. Authenticate against the Akuity-hosted Argo CD instance per `Taskfile.yml`'s `argocd:login` task (requires `TF_VAR_admin_password` set and `terraform apply` already run in `terraform/clusters/` -- both should already be true in this environment; if not, that is itself a finding to report, not something to fix as part of this story).
2. Inspect what Argo CD "sees" as registered clusters on this instance: `argocd cluster list` (via the CLI) and, if cluster-scoped access is available, `kubectl -n argocd get secrets -l argocd.argoproj.io/secret-type=cluster` against wherever the Argo CD control-plane components actually run (on Akuity-hosted instances this may not be a cluster you have direct `kubectl` access to at all -- if so, note that as a finding; it is itself evidence about whether the generator's underlying mechanism can work).
3. Create a throwaway `ApplicationSet` (do NOT commit it to `infrastructure/` -- apply it directly with `kubectl apply`/`argocd` CLI against a scratch namespace, or use `argocd appset generate <file>` if the installed Argo CD CLI version supports dry-run generation) using:
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: ApplicationSet
   metadata:
     name: cluster-generator-spike
     namespace: argocd
   spec:
     generators:
     - clusters: {}
     template:
       metadata:
         name: 'spike-{{name}}'
       spec:
         project: default
         source:
           repoURL: https://github.com/adamancini/argo-fleet.git
           targetRevision: HEAD
           path: infrastructure/sealed-secrets/argocd
         destination:
           name: '{{name}}'
           namespace: default
   ```
   Observe what `Application` resources (if any) get templated. If zero, the generator found no clusters -- try `{{server}}` and `{{metadata.labels.*}}` as alternate template fields per the Argo CD ApplicationSet docs (`https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Cluster/`) before concluding total failure.
4. Delete the spike `ApplicationSet` and any `Application`s it generated once the observation is complete -- this story ships a decision, not a running resource. `argocd app delete` cascades by default; pass `--cascade=false` if any generated Application shouldn't take its managed resources with it -- in this spike's case cascade is fine since nothing real was deployed, but note the flag either way per this fleet's known gotcha.
5. Record the finding as a comment/note on this issue: which template field (if any) the generator populates, whether it matches `demo1`/`demo2`, and the exact YAML shape confirmed to work. If the generator returns nothing, record that explicitly and select the fallback (see OUT OF SCOPE / fallback note below), so stories 2 and 3 know which path to implement.

KEY FILES:
No repo files are modified by this story (see PRODUCES -- the finding is recorded in this issue itself, not a source file). Reference-only: `terraform/clusters/main.tf`, `terraform/clusters/modules/cluster/main.tf`, `terraform/clusters/terraform.tfvars`, `infrastructure/sealed-secrets/argocd/appset.yaml` (used as the scratch template's `source.path`, not modified).

OUT OF SCOPE:
- Actually editing any of the 5 existing `infrastructure/*/argocd/appset.yaml` files -- that is the follow-on migration story, which consumes this story's finding.
- Deciding the fallback's exact implementation mechanics (e.g., the specific script/generator that reads `terraform/clusters/terraform.tfvars`) if the generator fails -- this story only decides WHICH path (confirmed-working `clusters: {}`, or fallback) the other stories take; the fallback's own implementation detail is deferred to whichever story picks it up -- flag that back to the Sr PM/dispatcher for re-scoping rather than improvising.

DIFF BUDGET:
0 files changed in the repository (spike only touches the live Argo CD instance with a throwaway resource, then deletes it). 1 issue comment/note recording the finding.

CONSUMES:
None -- this is the first story in the epic and depends on nothing else in this backlog.

PRODUCES:
- This issue's own Notes/Comments -> Decision record with signature:
  spec: generator: 'clusters: {}' | 'list (fallback)'; template_field: '{{name}}' | '{{server}}' | '<other>' | 'N/A (fallback)'; confirmed_cluster_names: ['demo1','demo2'] | []
  source: empirical observation against the live Akuity-hosted Argo CD instance (this story's own execution), cross-checked against devops-toolkit:akp-platform's argocd-declarative-setup reference (Akuity-hosted divergence section) and https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Cluster/

TESTING:
Not applicable in the unit/integration sense -- this is an empirical verification spike. "Testing" here means the observation itself: apply the throwaway ApplicationSet, observe the Application(s) it generates (or doesn't), and record the exact result. No automated test is written.

Acceptance Criteria:
1. [Event] When the throwaway `clusters: {}` ApplicationSet is applied against the live instance, the resulting set of generated `Application` resources (including zero) is captured and recorded.
2. [Ubiquitous] The template field the generator actually populates (`{{name}}`, `{{server}}`, or a label-derived field) is documented, if the generator produces any output at all.
3. [Unwanted] The spike shall not leave the throwaway `ApplicationSet` or any resources it generated behind on the live instance after this story closes.
4. A clear go/no-go decision is recorded: either "confirmed -- clusters generator works, use `<exact YAML shape>`" or "confirmed failed -- use fallback: `<fallback approach>`", so the follow-on stories can proceed without re-deriving this themselves.
5. If the decision is "confirmed failed," the fallback approach is specific enough to implement (not just "figure something out") -- e.g., naming the exact mechanism (templated list generator sourced from `terraform.tfvars`, a small pre-commit script, a `git` generator over `.kubeconfigs/*.yaml` filenames) even though the fallback's own implementation is out of scope for this story.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory -- especially its argocd-declarative-setup reference's Akuity-hosted divergence section and its terraform-provisioning reference for how cluster registration actually works on this instance)

## Acceptance Criteria


## Design


## Notes


## nd_contract
status: accepted

### evidence
- PM closeout applied via pvg story accept on 2026-08-07.

### proof
- [x] Story closed after accepted label was applied.


## nd_contract
status: delivered

### evidence
- Transitioned via pvg story deliver on 2026-08-07.

### proof
- [ ] Developer evidence block must remain authoritative above this contract.


## History
- 2026-08-07T15:07:23Z dep_added: blocks AF-c8p4
- 2026-08-07T15:07:23Z dep_added: blocks AF-d3ax
- 2026-08-07T15:07:24Z dep_added: blocks AF-7u8n
- 2026-08-07T15:14:32Z status: open -> in_progress
- 2026-08-07T15:14:32Z claimed by dev-AF-ogxu
- 2026-08-07T15:25:47Z status: in_progress -> in_progress
- 2026-08-07T15:33:33Z status: in_progress -> closed
- 2026-08-07T15:33:33Z dep_removed: no_longer_blocks AF-c8p4
- 2026-08-07T15:33:33Z dep_removed: no_longer_blocks AF-d3ax
- 2026-08-07T15:33:33Z dep_removed: no_longer_blocks AF-7u8n

## Links
- Parent: [[AF-d66a]]
- Led to: [[AF-c8p4]], [[AF-d3ax]], [[AF-qmy9]]

## Comments

### 2026-08-07T15:25:34Z ada
DECISION: GO -- `clusters: {}` WORKS on this Akuity-hosted instance, but MUST carry a selector.

SIGNATURE:
spec: generator: 'clusters: {} (with selector)'; template_field: '{{name}}'; confirmed_cluster_names: ['demo1','demo2']

## AC1 -- Generated Applications captured

Method: `argocd appset generate` (server-side dry-run RPC, argocd CLI v3.5.0 -> server v3.4.6).
Chosen over `kubectl apply` deliberately: it renders the templated Applications
server-side against the REAL cluster list without creating any resource, so AC3
(no leftovers) is satisfied by construction.

Instance: augtpjfe5xvyty6u.cd.akuity.cloud (`ada-quickstart-argocd`).

`argocd cluster list` -- the Akuity control plane DOES expose Terraform-registered
clusters through the normal Argo CD cluster API, so the generator's underlying
mechanism works here:

  SERVER                          NAME        VERSION  STATUS
  http://cluster-demo1:8001       demo1
  http://cluster-demo2:8001       demo2
  https://kubernetes.default.svc  in-cluster  v1.33.8  Successful
  https://cluster-kargo:6445      kargo       v1.33.8  Successful

Bare `clusters: {}` generated FOUR Applications, not two:

  argocd/spike-demo1       demo1
  argocd/spike-demo2       demo2
  argocd/spike-in-cluster  in-cluster   <-- REGRESSION
  argocd/spike-kargo       kargo        <-- REGRESSION

*** This is the load-bearing finding. A naive `clusters: {}` swap on the 5 existing
appsets is NOT equivalent to today's 2-element list generator -- it would additionally
target the Akuity control plane (`in-cluster`) and the Kargo cluster (`kargo`).
Concretely: `sealed-secrets` would try to install the controller into `kargo`, and
`in-cluster` is namespace-restricted to `argocd` only, so a destination namespace of
`sealed-secrets`/`traefik`/`openebs` would be rejected outright. ***

## AC2 -- Template fields the generator populates

Verified by rendering every candidate field into annotations:

  {{name}}            -> demo1 / demo2 / in-cluster / kargo   <-- USE THIS
  {{nameNormalized}}  -> identical to {{name}} here
  {{server}}          -> http://cluster-demo1:8001            <-- DO NOT USE
  {{project}}         -> "" (empty)
  {{metadata.labels.<key>}} -> resolves, e.g.
        akuity.io/argo-cd-cluster-name -> demo1
        generation                     -> 7

`{{server}}` returns Akuity-INTERNAL proxy URLs, not real API server URLs. Use
`destination.name: '{{name}}'`, never `destination.server`.

GOTCHA (non-goTemplate mode): an unresolved `{{metadata.labels.X}}` renders as the
LITERAL placeholder string, not empty -- e.g. demo1 rendered
`{{metadata.labels.akuity.io/direct-cluster}}` verbatim. Do not rely on a missing
label evaluating falsy. Set `goTemplate: true` if conditional logic is ever needed.

Cluster labels observed (all Akuity-managed; tfvars sets none):
  demo1/demo2 : akuity.io/argo-cd-cluster-name=<name>, generation=7
  in-cluster  : + akuity.io/argo-cd-instance-id=augtpjfe5xvyty6u
  kargo       : + akuity.io/direct-cluster=true

## Selector matrix (all empirically run)

  bare clusters: {} (no selector)              => demo1,demo2,in-cluster,kargo
  NotIn cluster-name [in-cluster,kargo]        => demo1,demo2          <-- RECOMMENDED
  DoesNotExist instance-id + direct-cluster    => demo1,demo2          <-- alternative
  In cluster-name [demo1,demo2]                => demo1,demo2  (a list generator in disguise; rejected)
  matchLabels fleet=true                       => ZERO APPS    (no cluster carries `fleet` today)

matchLabels/Exists confirmed functional via positive controls
(matchLabels akuity.io/direct-cluster=true => kargo; matchLabels cluster-name=demo1 => demo1),
so the ZERO for `fleet=true` is a genuine absent-label result, not a broken selector.

## AC4 -- Exact YAML shape confirmed to work

  spec:
    generators:
    - clusters:
        selector:
          matchExpressions:
          - key: akuity.io/argo-cd-cluster-name
            operator: NotIn
            values: [in-cluster, kargo]
    template:
      metadata:
        name: '<app>-{{name}}'
      spec:
        destination:
          name: '{{name}}'

Migration is `list:` -> `clusters:` + selector, and `{{cluster}}` -> `{{name}}`.

PROOF OF NO-OP: rendered the real infrastructure/sealed-secrets/argocd/appset.yaml
both ways and diffed the generated Applications (name, destination, project, source,
syncPolicy). Result: BYTE-IDENTICAL -- sealed-secrets-demo1 + sealed-secrets-demo2.
Because Application names are unchanged, migration causes no recreation, no prune,
no downtime on the 5 live infra apps.

## AC5 -- Fallback

Not needed (decision is GO). Recorded for completeness: had the generator returned
nothing, the fallback was a templated list generator sourced from the same
`clusters` map in terraform/clusters/terraform.tfvars.

## Follow-on notes for AF-c8p4 / AF-d3ax / AF-7u8n

1. The selector is MANDATORY, not optional. A bare `clusters: {}` is a regression.
2. Denylist (NotIn) is preferred over allowlist so a 3rd workload cluster is picked
   up with zero file edits -- the story's actual goal.
3. Longer-term hardening option: set `labels = { fleet = "true" }` per cluster in
   terraform.tfvars and switch to `matchLabels: {fleet: "true"}`. More robust (does
   not depend on Akuity-internal label semantics) but requires a terraform apply, and
   terraform.tfvars warns labels must be added only AFTER first successful apply
   (two-phase registration, docs/day-2.md). Not done here -- out of scope.
4. Only `infrastructure/*` appsets should migrate. `fleet-argocd-apps`, `infra-apps`,
   and `fleet-kargo-apps` intentionally target in-cluster/kargo via git generators --
   leave them alone.

## AC3 -- Cleanup

Nothing to clean: `argocd appset generate` never persists. Verified after the fact --
10 ApplicationSets and 26 Applications on the instance, all pre-existing, zero matching
spike/cluster-generator/sel-/fields-. All scratch YAML was written to the session
scratchpad, never to the repo. Repo diff: 0 files changed, 0 commits.
(Cascade note per the fleet gotcha: `argocd app delete` cascades by default; had real
Applications been created, `--cascade=false` would have been required to avoid the
generated apps taking managed resources with them. Not exercised -- nothing was applied.)

## Environment finding (reported, not fixed, per story instructions)

`task argocd:login` FAILS from a git worktree. The Taskfile derives
TERRAFORM_CLUSTERS_DIR from {{.ROOT_DIR}}, but terraform/clusters/.terraform/,
*.tfstate and *.tfvars are gitignored, so a worktree has config without state:

  Error: Required plugins are not installed
  - registry.terraform.io/akuity/akp: there is no package for ... 0.13.0 cached in .terraform/providers

Worked around read-only via
`terraform -chdir=<main-repo>/terraform/clusters output -raw argocd_hostname`
then `argocd login` directly. No terraform state was modified. Any future
worktree-based story needing `task argocd:login` / `task kargo:login` will hit this.

### 2026-08-07T15:26:19Z ada
PROOF:

Commands run (all against live instance augtpjfe5xvyty6u.cd.akuity.cloud, argocd CLI v3.5.0 -> server v3.4.6):
  source /Users/ada/src/github.com/adamancini/argo-fleet/.envrc
  terraform -chdir=<main-repo>/terraform/clusters output -raw argocd_hostname
  argocd login "$HOSTNAME" --username admin --password "$TF_VAR_admin_password" --grpc-web
  argocd cluster list --grpc-web [-o json]
  argocd appset generate --grpc-web [-o json] <8 scratch manifests>
  diff -u out-current.json out-migrated.json

Repo SHA results produced from: 97105f5 (story/AF-ogxu, 0 commits ahead of origin/main)
Repo diff: 0 files changed, 0 commits -- matches the 0-file diff budget for a spike.

No automated tests exist or were written -- this is an empirical verification spike,
as the story's Testing section specifies. "Test results" below are the observations.

Observation counts: 8 dry-run generations executed, 8 succeeded, 0 errored.

AC VERIFICATION TABLE:
| AC | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| 1 | Generated Application set captured, including zero | PASS | Bare `clusters: {}` -> 4 apps (spike-demo1, spike-demo2, spike-in-cluster, spike-kargo). Full selector matrix of 8 variants recorded in finding comment, incl. one genuine ZERO result (matchLabels fleet=true). |
| 2 | Template field the generator populates documented | PASS | {{name}}, {{nameNormalized}}, {{server}}, {{project}}, {{metadata.labels.<key>}} all rendered into annotations and captured. {{name}} -> demo1/demo2. |
| 3 | No throwaway ApplicationSet/Applications left behind | PASS | Satisfied by construction -- `argocd appset generate` is a read-only dry-run RPC; nothing was ever applied. Post-check: 10 ApplicationSets / 26 Applications, all pre-existing, 0 matching spike/cluster-generator/sel-/fields-. |
| 4 | Clear go/no-go decision recorded | PASS | GO, with mandatory selector. Exact YAML shape recorded. Plus a byte-identical diff proving migration is a no-op on the 5 live infra apps. |
| 5 | Fallback specific enough to implement if no-go | N/A (PASS) | Decision is GO. Fallback recorded for completeness: templated list generator sourced from the `clusters` map in terraform/clusters/terraform.tfvars. |

pvg verify: not applicable -- 0 files changed, no code to scan.

LEARNINGS:

- The real risk was NOT the one the story predicted. Akuity's control plane does expose
  Terraform-registered clusters to the generator (the documented "no cluster Secrets here"
  divergence does not block it). The actual hazard is the opposite: `clusters: {}` returns
  MORE than expected -- it also matches `in-cluster` and `kargo`. A naive swap would have
  silently broadened targeting on 5 working apps. Exactly the failure the spike was bought
  to prevent, just via a different mechanism than anticipated.
- `argocd appset generate` is the right tool for this class of question: server-side render
  against real cluster state, zero resources created. It made AC3 (no leftovers) true by
  construction rather than by cleanup discipline.
- I burned a cycle on a bad harness, not bad infra: `argocd appset generate -o json` emits a
  bare object for a single result and an array for multiple. My jq guard `if type=="array"`
  silently misreported two working selectors as failures, producing a self-contradictory
  matrix (DoesNotExist excluded kargo while Exists "found" nothing). Lesson: when a result
  matrix contradicts itself, suspect the harness before the system, and never let one branch
  of a guard collapse "empty" and "error" into the same label.
- Diffing the generated output of the current vs proposed manifest was worth more than any
  amount of prose reasoning -- byte-identical output proves no Application churn, which is
  the thing the user actually cared about.
- `task argocd:login` is unusable from a git worktree: the Taskfile resolves
  TERRAFORM_CLUSTERS_DIR from {{.ROOT_DIR}} but terraform state/tfvars/.terraform are
  gitignored, so worktrees get config without state. Future worktree stories touching
  argocd:login / kargo:login need `terraform -chdir=<main-repo>/...` instead.

### 2026-08-07T15:34:24Z ada
PM REVIEW: ACCEPTED. Verified independently against live instance augtpjfe5xvyty6u.cd.akuity.cloud via argocd-akuity MCP (list_clusters, list_applications): cluster list returned exactly demo1/demo2/in-cluster/kargo with matching labels (akuity.io/argo-cd-cluster-name, akuity.io/direct-cluster=true on kargo, akuity.io/argo-cd-instance-id on in-cluster) -- matches the developer's finding byte-for-byte. Application list returned 26 total, zero named spike-*/cluster-generator-spike/sel-*/fields-* -- confirms AC3 no-leftover claim; consistent with argocd appset generate being a read-only dry-run RPC that never persists. Repo verification: story/AF-ogxu and epic/AF-d66a are the same commit (97105f5), git diff --stat empty -- 0 files/0 commits confirmed, matches the 0-file diff budget. Skill cross-check: devops-toolkit:akp-platform's references/argocd-declarative-setup.md Akuity-hosted-divergence section was quoted accurately in the story description; the empirical finding (cluster API still surfaces Terraform-registered clusters despite the Secret-based mechanism not being hand-authored) resolves the skill's explicitly-flagged open question rather than contradicting it -- not a misreading. Critical requirement met: the GO decision is NOT bare -- the mandatory NotIn selector (excluding in-cluster, kargo) is durably recorded in this issue's own comments with exact YAML, a full 5-variant selector matrix, and a byte-identical before/after diff proof on the real sealed-secrets appset, so AF-c8p4/AF-d3ax can consume it without re-deriving anything. Environment finding (task argocd:login broken in worktrees due to gitignored terraform state/tfvars) independently reproduced: this worktree's terraform/clusters/ has no .terraform/, tfstate, or tfvars, matching .gitignore lines 20-24. Workaround (terraform -chdir=<main-repo>/terraform/clusters output -raw) is read-only; no state was modified.
