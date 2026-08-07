---
id: AF-ogxu
title: "Spike: confirm Argo CD clusters generator discovers demo1/demo2 on the Akuity-hosted instance"
status: in_progress
priority: 0
type: task
labels: [spike, delivered]
parent: AF-d66a
created_at: 2026-08-07T15:06:16Z
created_by: ada
updated_at: 2026-08-07T15:25:47Z
content_hash: "sha256:ae685f3a64d0a63be609be426dfc8dff7ffb326da2cb80a38715d82c495446a0"
blocks: [AF-c8p4, AF-d3ax, AF-7u8n]
assignee: dev-AF-ogxu
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


## History
- 2026-08-07T15:07:23Z dep_added: blocks AF-c8p4
- 2026-08-07T15:07:23Z dep_added: blocks AF-d3ax
- 2026-08-07T15:07:24Z dep_added: blocks AF-7u8n
- 2026-08-07T15:14:32Z status: open -> in_progress
- 2026-08-07T15:14:32Z claimed by dev-AF-ogxu
- 2026-08-07T15:25:47Z status: in_progress -> in_progress

## Links
- Parent: [[AF-d66a]]
- Blocks: [[AF-c8p4]], [[AF-d3ax]], [[AF-7u8n]]

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
