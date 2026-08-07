---
id: AF-ogxu
title: "Spike: confirm Argo CD clusters generator discovers demo1/demo2 on the Akuity-hosted instance"
status: open
priority: 0
type: task
labels: [spike]
parent: AF-d66a
created_at: 2026-08-07T15:06:16Z
created_by: ada
updated_at: 2026-08-07T15:06:16Z
content_hash: "sha256:ff419342746996984973bc746b59e6fab16b63c49878b66b14682b16cd942954"
blocks: [AF-c8p4]
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

The risk: standard OSS Argo CD's `clusters: {}` generator works by listing Kubernetes `Secret` objects labeled `argocd.argoproj.io/secret-type: cluster` in the Argo CD namespace -- these are normally hand-authored (or created by `argocd cluster add`) with the target cluster's server URL and credentials embedded. On this repo's Akuity-hosted instance, cluster registration does NOT go through that mechanism: `devops-toolkit:akp-platform`'s `references/argocd-declarative-setup.md` states explicitly (Akuity-hosted divergence section): "cluster/agent registration instead goes through the `akp` Terraform provider... the Akuity Agent connects outbound and no cluster credentials are stored centrally, so this Secret-based mechanism isn't something you author yourself here." Whether Akuity's control plane creates an equivalent, generator-discoverable Secret under the hood for each Terraform-registered cluster is genuinely unknown from documentation alone -- this story exists to answer that question empirically, against the real instance, before 5 existing files and 1 new file are all rewritten to depend on the answer.

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
  source: empirical observation against the live Akuity-hosted Argo CD instance (this story's own execution), cross-checked against `devops-toolkit:akp-platform`'s `references/argocd-declarative-setup.md` Akuity-hosted divergence section and `https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Cluster/`.

TESTING:
Not applicable in the unit/integration sense -- this is an empirical verification spike. "Testing" here means the observation itself: apply the throwaway ApplicationSet, observe the Application(s) it generates (or doesn't), and record the exact result. No automated test is written.

Acceptance Criteria:
1. [Event] When the throwaway `clusters: {}` ApplicationSet is applied against the live instance, the resulting set of generated `Application` resources (including zero) is captured and recorded.
2. [Ubiquitous] The template field the generator actually populates (`{{name}}`, `{{server}}`, or a label-derived field) is documented, if the generator produces any output at all.
3. [Unwanted] The spike shall not leave the throwaway `ApplicationSet` or any resources it generated behind on the live instance after this story closes.
4. A clear go/no-go decision is recorded: either "confirmed -- clusters generator works, use `<exact YAML shape>`" or "confirmed failed -- use fallback: `<fallback approach>`", so the follow-on stories can proceed without re-deriving this themselves.
5. If the decision is "confirmed failed," the fallback approach is specific enough to implement (not just "figure something out") -- e.g., naming the exact mechanism (templated list generator sourced from `terraform.tfvars`, a small pre-commit script, a `git` generator over `.kubeconfigs/*.yaml` filenames) even though the fallback's own implementation is out of scope for this story.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory -- especially `references/argocd-declarative-setup.md`'s Akuity-hosted divergence section and `references/terraform-provisioning.md` for how cluster registration actually works on this instance)

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-07T15:07:23Z dep_added: blocks AF-c8p4

## Links
- Parent: [[AF-d66a]]
- Blocks: [[AF-c8p4]]

## Comments
