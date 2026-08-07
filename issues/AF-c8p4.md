---
id: AF-c8p4
title: "Migrate 5 existing infra ApplicationSets from static list generator to clusters generator"
status: closed
priority: 1
type: task
parent: AF-d66a
created_at: 2026-08-07T15:06:16Z
created_by: ada
updated_at: 2026-08-07T15:57:42Z
content_hash: "sha256:a4e1f59ee0708bcd197e3168021caa21bf7a4e0d448fe3a53d3725ebedfbe3c0"
was_blocked_by: [AF-ogxu]
assignee: dev-AF-c8p4
follows: [AF-ogxu]
labels: [accepted]
closed_at: 2026-08-07T15:57:17Z
close_reason: "Accepted via pvg story accept"
led_to: [AF-qmy9]
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
- 2026-08-07T15:07:23Z dep_added: blocked_by AF-ogxu
- 2026-08-07T15:07:23Z dep_added: blocks AF-qmy9
- 2026-08-07T15:07:24Z dep_added: blocks AF-7u8n
- 2026-08-07T15:33:33Z dep_removed: was_blocked_by AF-ogxu
- 2026-08-07T15:38:59Z status: open -> in_progress
- 2026-08-07T15:38:59Z auto-follows: linked to predecessor AF-ogxu
- 2026-08-07T15:38:59Z claimed by dev-AF-c8p4
- 2026-08-07T15:47:19Z status: in_progress -> in_progress
- 2026-08-07T15:57:17Z status: in_progress -> closed
- 2026-08-07T15:57:17Z dep_removed: no_longer_blocks AF-qmy9
- 2026-08-07T15:57:17Z dep_removed: no_longer_blocks AF-7u8n

## Links
- Parent: [[AF-d66a]]
- Was blocked by: [[AF-ogxu]]
- Follows: [[AF-ogxu]]
- Led to: [[AF-qmy9]]

## Comments

### 2026-08-07T15:48:16Z ada
DELIVERED AF-c8p4 -- migrate 5 infra ApplicationSets from `list` to `clusters` generator

Branch: story/AF-c8p4
Commit SHA: bba5433e7d9707b4320dc41f974af10b696d6f36 (pushed to origin)
Base: 97105f5 (== epic/AF-d66a head; verified no already-landed work on the epic)
Diff: 5 files changed, 40 insertions(+), 30 deletions(-)

## PROOF

### Commands run (all against commit bba5433)

1. `pvg verify --format text <5 changed files>`
   -> `VERIFY: PASSED (0 files scanned, 0 issues)` exit 0.
   Note: 0 files scanned because pvg verify is a source-code scanner and skips
   .yaml manifests. It is not a meaningful gate for this story; the real gates
   are yamllint + kubeconform + argocd appset generate below.

2. `yamllint -d '{extends: default, ... indentation: {spaces: 2, indent-sequences: false}}' infrastructure/*/argocd/appset.yaml`
   -> exit 0, ZERO errors, ZERO warnings on all 5 files.
   `indent-sequences: false` matches this repo's house style (repo ships no
   .yamllint config). Under yamllint's *default* indent-sequences:true the 5
   files report 15 errors -- but the pre-change HEAD versions report the SAME
   15 errors, all of class "non-indented block sequence". So the change
   introduces zero new lint findings. Baseline vs post-change both = 15.

3. `kubeconform -summary -strict -verbose -schema-location default -schema-location <datreeio CRDs-catalog> infrastructure/*/argocd/appset.yaml`
   -> `Summary: 5 resources found in 5 files - Valid: 5, Invalid: 0, Errors: 0, Skipped: 0`, exit 0.
   All 5 validated against the real ApplicationSet CRD schema in strict mode
   (strict = unknown/misspelled fields rejected).

4. Live auth (read-only) per the spike's documented worktree workaround:
   `source /Users/ada/src/github.com/adamancini/argo-fleet/.envrc`
   `HOSTNAME=$(terraform -chdir=.../terraform/clusters output -raw argocd_hostname)`
   `argocd login "$HOSTNAME" --username admin --password "$TF_VAR_admin_password" --grpc-web`
   -> logged in to augtpjfe5xvyty6u.cd.akuity.cloud. No terraform plan/apply run.
   `argocd cluster list` -> 4 clusters: in-cluster, kargo, demo1, demo2
   (independently reconfirms the spike's cluster inventory).

### Pass/fail counts
- yamllint (repo style): 5/5 files clean -- 0 errors, 0 warnings
- kubeconform strict:    5/5 valid, 0 invalid, 0 errors, 0 skipped
- appset render equivalence: 5/5 byte-identical
- rendered-vs-live match: 10/10 Applications MATCH
- live Sync/Health:      10/10 Synced + Healthy
- TOTAL: 35/35 checks passed, 0 failed, 0 skipped

### AC verification table

| # | Acceptance criterion | Evidence | Result |
|---|---|---|---|
| 1 | All 5 files use the exact spike-confirmed generator block; none left on `list`; no variant drift | Programmatic structural check parsed all 5 and compared `spec.generators` against the spike's literal block -- identical in all 5. `grep -rn '{{cluster}}\|list:' infrastructure/` -> no matches. Diff shows the same +7/-5 generator hunk in each file. | PASS |
| 2 | Rendering each edited appset via `argocd appset generate` produces the same Applications as today's live version -- verified, not assumed | Rendered BOTH the HEAD (pre-change, `list`) and edited (`clusters`) version of each file through the live `appset generate` RPC and diffed the FULL Application JSON: `FULL_JSON_IDENTICAL=True` for all 5 (2 apps each, 10 total). Not just names/destinations -- the entire rendered spec. | PASS |
| 3 | Migration does not add in-cluster/kargo as destinations -- confirmed via rendered dry-run output | Rendered output for all 5 = exactly demo1 + demo2, 2 apps each. Positive control: rendered a temp (uncommitted) bare `clusters: {}` variant -> 4 apps incl. `sealed-secrets-in-cluster` and `sealed-secrets-kargo`. This independently reproduces the spike's warning and proves the selector is load-bearing, not decorative. | PASS |
| 4 | No file's `source`, `destination.namespace` or `syncPolicy` changes as a side effect | Full `git diff` reviewed line by line before commit: every file's hunks are exactly (a) the `generators` block and (b) two `{{cluster}}`->`{{name}}` renames (metadata.name, destination.name). Zero diff lines touch source/chart/targetRevision/helm values/namespace/syncPolicy. AC2's full-JSON identity is independent confirmation. | PASS |
| 5 | Report dry-run-verified Synced/Healthy-equivalence for all 5 | All 10 live Applications are Synced + Healthy, and all 10 rendered (name, destination.name) pairs MATCH live. See limitation note below. | PASS |

### Rendered vs live (all 10)

| App | Cluster | Render match | Live sync | Live health | Live dest |
|---|---|---|---|---|---|
| sealed-secrets | demo1 | MATCH | Synced | Healthy | demo1/sealed-secrets |
| sealed-secrets | demo2 | MATCH | Synced | Healthy | demo2/sealed-secrets |
| traefik-gateway | demo1 | MATCH | Synced | Healthy | demo1/traefik |
| traefik-gateway | demo2 | MATCH | Synced | Healthy | demo2/traefik |
| gateway-api-crds | demo1 | MATCH | Synced | Healthy | demo1/default |
| gateway-api-crds | demo2 | MATCH | Synced | Healthy | demo2/default |
| openebs-localpv | demo1 | MATCH | Synced | Healthy | demo1/openebs |
| openebs-localpv | demo2 | MATCH | Synced | Healthy | demo2/openebs |
| argo-rollouts-crds | demo1 | MATCH | Synced | Healthy | demo1/default |
| argo-rollouts-crds | demo2 | MATCH | Synced | Healthy | demo2/default |

`destination.server` is absent (None) on every rendered AND every live
Application -- confirming the spike's rule that `{{server}}` must never be
used on this instance was honored.

### STATED LIMITATION (per story instructions)
I did NOT observe live reconciliation of my branch's changes. The live
`infra-*` Applications track `HEAD` of the repo's default branch, not
`story/AF-c8p4`, so nothing on my branch has been reconciled by the running
instance. The Synced/Healthy column above is the CURRENT live state produced
by the OLD `list` generator, not proof that my branch reconciled cleanly.
What is proven is stronger than a spot health check: the live `appset
generate` RPC renders my edited files into Applications byte-identical to
what the current live version renders, so on merge there is nothing for the
ApplicationSet controller to change -- zero Application churn, no delete/
recreate, and therefore no reason for the existing Synced/Healthy state to
move. Full live confirmation is only possible after this merges to the
tracked branch.

### Out-of-scope files confirmed untouched
`bootstrap/infra-apps.yaml`, `bootstrap/fleet-argocd-apps.yaml`,
`bootstrap/fleet-kargo-apps.yaml`, `docs/infra-dependencies.md`, and
`infrastructure/kube-prometheus-stack/` -- none appear in the diff (5 files
changed, all `infrastructure/*/argocd/appset.yaml`).

### Errors / warnings encountered
Zero test failures, zero build warnings, zero runtime errors. No
DISCOVERED_BUG to report. `origin/main` advanced during the work (2753ef0
`soju/dev: promote 0.1.10`) -- verified it touches only
`apps/soju/env/dev/release.yaml`, no overlap with my 5 files, and
`epic/AF-d66a` head is still 97105f5 (my base), so no rebase was needed.

### Deviation from plan
None. The spike's confirmed YAML shape was applied verbatim to all 5 files.

## LEARNINGS

- `argocd appset generate` is a genuinely strong verification primitive for
  generator migrations: it executes the generator server-side against the real
  cluster inventory but writes nothing. Rendering the OLD and NEW file versions
  and diffing the full Application JSON turns "this should be a no-op" into a
  proof, and it costs one RPC per file. Worth reaching for on any future
  generator or template change, not just this one.
- The `NotIn` selector is doing real work and is easy to get wrong by omission.
  Kubernetes label-selector semantics say `NotIn` also matches when the key is
  ABSENT -- so the selector only excludes in-cluster/kargo because Akuity
  actually stamps `akuity.io/argo-cd-cluster-name` on them. I verified this
  empirically (bare `clusters: {}` -> 4 apps, with selector -> 2) rather than
  trusting the semantics. Anyone adding a 6th appset must copy the selector, not
  just `clusters: {}`.
- Lint findings need a baseline before they mean anything. yamllint's default
  `indent-sequences: true` flags 15 "errors" on these files -- all pre-existing
  house style, identical count before and after my change. Reporting the
  post-change number alone would have looked like I introduced 15 problems.
  Diffing lint output against HEAD is cheap and prevents that.
- Worktree gotchas the spike documented were real and the workarounds held:
  `.envrc` is gitignored so it must be read by absolute path from the main
  repo, and `terraform -chdir=<main repo>` reads outputs fine without touching
  state. Additionally, the pvg guard blocks `cd` into a worktree, so this whole
  story was done with `git -C <worktree>` and absolute paths -- workable, but
  every non-git command needs absolute paths planned up front.
- `pvg verify` is a no-op on YAML-only stories (0 files scanned). It should not
  be mistaken for a passing quality gate here; the real gates were yamllint,
  kubeconform --strict against the ApplicationSet CRD schema, and the live
  render diff.

### 2026-08-07T15:57:42Z ada
PM REVIEW: ACCEPTED. Independently re-verified: (1) git diff origin/epic/AF-d66a..story/AF-c8p4 --stat matches claim exactly (5 files, +40/-30); full diff review confirms only spec.generators + two {{cluster}}->{{name}} renames changed per file, zero touches to source/chart/targetRevision/helm-values/destination.namespace/syncPolicy. (2) All 5 files' generator blocks are byte-identical (grep -A6 generators: on all 5 -- confirmed via direct comparison, same NotIn selector, same values list). (3) Re-ran the render-equivalence proof myself for 3/5 files (sealed-secrets, traefik-gateway, argo-rollouts-crds) via argocd appset generate --grpc-web -o json against the live instance (logged in via the documented worktree workaround) -- diffed old (list) vs new (clusters) rendered Application JSON: byte-identical (diff exit 0) for all 3. Also independently reproduced the counterfactual: a scratch bare 'clusters: {}' (no selector) on sealed-secrets rendered 4 apps including sealed-secrets-in-cluster and sealed-secrets-kargo, confirming the selector is load-bearing. (4) Confirmed bootstrap/infra-apps.yaml, bootstrap/fleet-argocd-apps.yaml, bootstrap/fleet-kargo-apps.yaml, docs/infra-dependencies.md, infrastructure/kube-prometheus-stack/ are absent from the diff. (5) Confirmed destination.server absent in all 5 edited files (grep for server under destination: no matches). (6) kubeconform --strict re-run by me: 5/5 valid, 0 invalid, 0 errors -- matches claim. yamllint not installed in this environment so I could not independently reproduce that specific claim; treated as low-stakes given kubeconform (stronger schema check) passed and full line-by-line diff review found no stray changes. (7) mcp__argocd-akuity__list_clusters and list_applications independently confirm live cluster inventory (demo1/demo2/in-cluster/kargo, matching labels) and sealed-secrets-demo1/demo2 Synced+Healthy -- consistent with developer's claims. pvg verify: 0 files scanned (confirmed no-op on YAML, as claimed). pvg gates --changed origin/epic/AF-d66a: PASS, 0 warn. Live reconciliation of the story branch itself is structurally unobservable (Applications track default branch) -- not held against this story per its own stated limitation; render-equivalence proof is sufficiently rigorous.
