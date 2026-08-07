---
id: AF-c8p4
title: "Migrate 5 existing infra ApplicationSets from static list generator to clusters generator"
status: in_progress
priority: 1
type: task
parent: AF-d66a
created_at: 2026-08-07T15:06:16Z
created_by: ada
updated_at: 2026-08-07T15:47:20Z
content_hash: "sha256:b633326aae25c72e892fb9ef246bf19039bdc845130b8f54fc81ff04b96ba8cb"
blocks: [AF-qmy9, AF-7u8n]
was_blocked_by: [AF-ogxu]
assignee: dev-AF-c8p4
follows: [AF-ogxu]
labels: [delivered]
---

## Description
Description:
Replace the hardcoded `list` generator (`elements: [{cluster: demo1}, {cluster: demo2}]`) in all 5 existing `infrastructure/*/argocd/appset.yaml` files with the generator approach confirmed by the spike story -- either Argo CD's native `clusters: {}` generator, or the documented fallback if the spike found `clusters: {}` doesn't work on this Akuity-hosted instance. Apply the exact same fix pattern to all 5 files; this is one mechanical change repeated identically, not five separate designs.

Context:
The 5 files, and their current identical generator block, are:

`infrastructure/sealed-secrets/argocd/appset.yaml`, `infrastructure/traefik-gateway/argocd/appset.yaml`, `infrastructure/gateway-api-crds/argocd/appset.yaml`, `infrastructure/openebs-localpv/argocd/appset.yaml`, `infrastructure/argo-rollouts-crds/argocd/appset.yaml` -- each currently has:

```yaml
spec:
  generators:
  - list:
      elements:
      - cluster: demo1
      - cluster: demo2
  template:
    metadata:
      name: '<app-name>-{{cluster}}'
    spec:
      ...
      destination:
        name: '{{cluster}}'
        ...
```

Every `{{cluster}}` reference in every `template:` block (both in `metadata.name` and `spec.destination.name`) must be updated to whatever field the spike story confirmed the new generator exposes (most likely `{{name}}` if `clusters: {}` is confirmed working -- see that story's recorded decision before touching any file). If the spike confirmed the fallback path instead, apply that fallback's generator block identically across all 5 files instead.

This story does not change anything else about these 5 files -- not chart versions, not values, not sync policies, not namespaces. The generator block and the `{{cluster}}` -> new-field renames in the template are the entire diff.

USER INTENT:
The user wants cluster targeting for existing, already-working infra apps to stop being a hand-maintained list, without breaking any of the 5 apps in the process. They explicitly said not to silently skip this -- it's a companion piece to the new kube-prometheus-stack app, not a "maybe later."

IMPLEMENTATION:
1. Read the spike story's recorded decision (comment/note on that issue) for the exact generator block and template field to use.
2. In each of the 5 files, replace only the `spec.generators` block and rename every `{{cluster}}` occurrence in `spec.template` to the new field name. Example (assuming `clusters: {}` with `{{name}}` was confirmed), applied to `sealed-secrets`:
   ```yaml
   spec:
     generators:
     - clusters: {}
     template:
       metadata:
         name: 'sealed-secrets-{{name}}'
       spec:
         project: default
         source:
           repoURL: https://github.com/bitnami-labs/sealed-secrets.git
           targetRevision: helm-v2.16.1
           path: helm/sealed-secrets
           helm:
             valuesObject:
               fullnameOverride: sealed-secrets
         destination:
           name: '{{name}}'
           namespace: sealed-secrets
         syncPolicy:
           automated:
             prune: true
             selfHeal: true
           syncOptions:
           - CreateNamespace=true
   ```
   Apply the same field-rename pattern to the other 4 files' existing `spec.template` blocks -- their `source`/`destination.namespace`/`syncPolicy` content is unchanged from what's already in each file today; only `generators` and the `{{cluster}}` occurrences change.
3. If the spike confirmed the `clusters: {}` generator returns MORE than `demo1`/`demo2` (e.g., it also picks up the internal `kargo` cluster registered by `terraform/clusters`' `02-kargo` stack, or an `in-cluster` entry), add a `selector` to exclude non-workload clusters from these 5 fan-outs -- do not silently deploy Sealed Secrets/Traefik/etc. onto a cluster that isn't a real workload target. Confirm exactly what the generator returns (from the spike's finding) before writing the selector; do not guess a label name.
4. Push the change and confirm, via `argocd app list` or the Akuity Portal, that exactly the same set of `Application` resources exists after the migration as before it (same names modulo the template-field rename, same destinations) -- no cluster silently dropped, no unexpected extra cluster picked up.

KEY FILES:
`infrastructure/sealed-secrets/argocd/appset.yaml`, `infrastructure/traefik-gateway/argocd/appset.yaml`, `infrastructure/gateway-api-crds/argocd/appset.yaml`, `infrastructure/openebs-localpv/argocd/appset.yaml`, `infrastructure/argo-rollouts-crds/argocd/appset.yaml` (all 5 modified in place; no new files).

OUT OF SCOPE:
- Any change to chart versions, Helm values, sync policies, or namespaces in these 5 files -- only the generator block and template field names change. A version bump found "while in there" belongs in its own story, not this one.
- `docs/infra-dependencies.md`'s "use a list generator" instruction -- that's a separate follow-on docs story (updates the doc once both this migration and the new kube-prometheus-stack app confirm the real convention).
- The new `infrastructure/kube-prometheus-stack/` app -- that's a separate follow-on story, which can proceed in parallel with this one (both depend only on the spike, not on each other).

DIFF BUDGET:
5 files changed, all in `infrastructure/*/argocd/appset.yaml`. Each diff is small (one generator block + 1-2 template-field renames) -- expect well under 100 changed LOC total across all 5 files combined.

CONSUMES:
- AF-ogxu: this issue's own Notes/Comments -> Decision record
    spec: generator: 'clusters: {}' | 'list (fallback)'; template_field: '{{name}}' | '{{server}}' | '<other>' | 'N/A (fallback)'; confirmed_cluster_names: ['demo1','demo2'] | []
    source: the spike story's empirical finding (see that issue's comments/notes)

PRODUCES:
- `infrastructure/sealed-secrets/argocd/appset.yaml` -> ApplicationSet using the confirmed generator, template field renamed from `{{cluster}}` to the confirmed field
- `infrastructure/traefik-gateway/argocd/appset.yaml` -> same
- `infrastructure/gateway-api-crds/argocd/appset.yaml` -> same
- `infrastructure/openebs-localpv/argocd/appset.yaml` -> same
- `infrastructure/argo-rollouts-crds/argocd/appset.yaml` -> same
  spec: generators: [{clusters: {}}] (or confirmed fallback); template fields use the field the spike confirmed
  source: the spike story's decision record, applied uniformly

TESTING:
No unit tests exist for YAML ApplicationSet manifests in this repo (there is no test suite here -- this is a GitOps config repo). Verification is operational: after pushing, confirm via `argocd app list` (or `mcp__argocd-akuity__list_applications` if available in the executing environment) that all 5 apps' `Application` resources still exist for both `demo1` and `demo2` with the same destinations as before the migration, and that each app's sync status is `Synced`/`Healthy` (not `OutOfSync` or `Degraded`) after the change. Use `devops-toolkit:yaml-kubernetes-validator` to lint the 5 edited files for YAML/schema correctness before pushing.

Acceptance Criteria:
1. [Ubiquitous] All 5 files use the exact generator block the spike story confirmed -- no file left on the old `list` generator, no file using a different variant than the other 4.
2. [Event] When each ApplicationSet reconciles after the change, it generates the same `Application` resources (same cluster set, same destinations) that existed before the migration -- verified via `argocd app list` or equivalent, not assumed.
3. [Unwanted] The migration shall not silently add a cluster destination (e.g. an internal `kargo` or `in-cluster` entry) that isn't a real workload target -- if the confirmed generator returns extra clusters, a `selector` excludes them, and this AC's verification confirms only `demo1`/`demo2` remain targeted.
4. [Unwanted] No file's `source`, `destination.namespace`, or `syncPolicy` content changes as a side effect -- diff review confirms only the generator block and template field renames changed.
5. All 5 apps report `Synced`/`Healthy` status after the change, confirmed operationally (not just "no YAML errors").

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory -- its gitops-app-patterns and argocd-declarative-setup references), devops-toolkit:yaml-kubernetes-validator

## Acceptance Criteria


## Design


## Notes


## nd_contract
status: delivered

### evidence
- Transitioned via pvg story deliver on 2026-08-07.

### proof
- [ ] Developer evidence block must remain authoritative above this contract.


## History
- 2026-08-07T15:07:23Z dep_added: blocked_by AF-ogxu
- 2026-08-07T15:07:23Z dep_added: blocks AF-qmy9
- 2026-08-07T15:07:24Z dep_added: blocks AF-7u8n
- 2026-08-07T15:33:33Z dep_removed: was_blocked_by AF-ogxu
- 2026-08-07T15:38:59Z status: open -> in_progress
- 2026-08-07T15:38:59Z auto-follows: linked to predecessor AF-ogxu
- 2026-08-07T15:38:59Z claimed by dev-AF-c8p4
- 2026-08-07T15:47:19Z status: in_progress -> in_progress

## Links
- Parent: [[AF-d66a]]
- Blocks: [[AF-qmy9]], [[AF-7u8n]]
- Was blocked by: [[AF-ogxu]]
- Follows: [[AF-ogxu]]

## Comments
