---
id: AF-d3ax
title: "Deploy kube-prometheus-stack as a new cluster-wide infra dependency"
status: in_progress
priority: 1
type: task
labels: [walking-skeleton]
parent: AF-d66a
created_at: 2026-08-07T15:06:16Z
created_by: ada
updated_at: 2026-08-07T16:29:24Z
content_hash: "sha256:64574d7d13d7c340070e0b7000faea7ab698973233b4c5812aeae39b82511bfb"
blocks: [AF-j4fp, AF-7u8n]
was_blocked_by: [AF-ogxu]
assignee: dev-AF-d3ax
follows: [AF-ogxu, AF-qmy9]
---

## Description
Description:
Add `infrastructure/kube-prometheus-stack/` as a new cluster-wide infra dependency (no promotion pipeline, per this repo's existing convention), deploying the single `kube-prometheus-stack` Helm chart (Prometheus Operator + Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics bundled together) to every cluster the generator confirmed by the spike story discovers. Grafana's admin password is wired to a `SealedSecret`, and Prometheus's PVC sets `storageClassName` explicitly.

Context:
This repo's convention for adding a cluster-wide infra dependency (`docs/infra-dependencies.md`, currently instructing a `list` generator that other stories in this epic are replacing) is: create `infrastructure/<name>/README.md` and `infrastructure/<name>/argocd/appset.yaml`, no changes to `bootstrap/` (auto-discovered via `bootstrap/infra-apps.yaml`'s git-directories generator over `infrastructure/*/argocd`), and Taskfile commands under a `<name>:<verb>` namespace only if there are repeatable ops commands (there are none needed here beyond the existing `sealed-secrets:seal` command, already provided).

The closest existing template is `infrastructure/traefik-gateway/argocd/appset.yaml` -- a Helm-repo chart source (`repoURL` = chart repo, `chart` = chart name, `targetRevision` = pinned version), not a git-repo-with-path source like `sealed-secrets`. `kube-prometheus-stack` is published the same way: `repoURL: https://prometheus-community.github.io/helm-charts`, `chart: kube-prometheus-stack`. As of this story's authoring (August 2026) the latest stable chart version is in the `88.x` series (e.g. `88.1.5`) -- confirm the actual current version with `helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm search repo prometheus-community/kube-prometheus-stack --versions` before pinning `targetRevision`; do not assume `88.1.5` is still current by the time this story executes.

Two non-negotiable gotchas from this fleet's own history, both from AGENTS.md and vault knowledge, apply directly to this chart:

1. Grafana admin password: AGENTS.md is explicit -- "Never rely on Helm `lookup` for 'generate once' secrets -- Argo CD renders charts via `helm template` with no cluster access, so values regenerate on every sync." The `kube-prometheus-stack` chart's bundled `grafana` subchart defaults to a randomly generated admin password unless `grafana.admin.existingSecret` is set -- left on defaults, that password would regenerate (and change) on every single Argo CD sync. It MUST be wired to a real `SealedSecret`, created via `task sealed-secrets:seal -- <namespace> <name> <output-path> <key>=<value> [...]` per AGENTS.md's documented invocation, never committed as plaintext.
2. Prometheus storage: this fleet has previously hit the exact failure mode where a PVC never binds because its StorageClass isn't the cluster's default and `storageClassName` wasn't set explicitly (vault note: "Non-Default StorageClass Leaves PVCs Permanently Unbound Without Explicit storageClassName"). `infrastructure/openebs-localpv/argocd/appset.yaml` currently sets `hostpathClass.name: local-path` with `isDefaultClass: true` -- so `local-path` is currently the default StorageClass on both `demo1`/`demo2`. Verify this is still true at implementation time (`kubectl get storageclass` against each cluster, confirm exactly one is marked `(default)`) before deciding whether `storageClassName` is strictly required for binding vs. merely good practice -- but set it explicitly either way; relying on an implicit default is exactly the practice that caused the earlier failure.

The Sealed Secrets keypair is shared across `demo1`/`demo2` (Taskfile's `sealed-secrets:*` tasks operate over `CLUSTERS = k3d-demo1 k3d-demo2`), so one `SealedSecret` ciphertext decrypts on either cluster -- no need to seal it twice. The multi-source Application pattern for syncing a Helm chart alongside a hand-authored manifest living in this repo already exists in `apps/akkoma/argocd/appset.yaml`: one `sources` entry for the chart, one for a git-repo source with `directory: {include: '*.sealed.yaml'}` pointing at this repo's own path -- reuse that shape here instead of inventing a new one.

USER INTENT:
The user wants a real, running Prometheus + Grafana + Alertmanager stack they can actually log into and see data in -- not a stubbed-out ApplicationSet that syncs green with an empty/broken Grafana behind it. Explicitly confirmed out of scope for this round: no custom dashboards, no alerting rules, no storage-sizing tuning beyond a small, sane default. "Just get the stack running" is the bar -- but running means Prometheus is actually scraping and its data survives a pod restart (bounded PVC), and Grafana is actually logged-into-able with real (not chart-default-random) credentials.

IMPLEMENTATION:
1. Create `infrastructure/kube-prometheus-stack/README.md` following the shape of `infrastructure/traefik-gateway/README.md` and `infrastructure/openebs-localpv/README.md`: what it is, why every cluster needs it, and the one bootstrap step required before it syncs cleanly (the Grafana admin `SealedSecret` must exist in the target namespace before/alongside the Application, same pattern as `sealed-secrets` needing its keypair pre-created).
2. Generate the Grafana admin `SealedSecret`: `task sealed-secrets:seal -- monitoring grafana-admin infrastructure/kube-prometheus-stack/argocd/secret-grafana-admin.sealed.yaml admin-user=admin admin-password=<a real generated password, e.g. via 'openssl rand -base64 24'>` (confirm the exact key names the installed chart version's `grafana.admin.userKey`/`grafana.admin.passwordKey` defaults expect -- historically `admin-user`/`admin-password` -- against the pinned chart version's `values.yaml`/README before sealing, per this fleet's discipline of verifying exact field shapes rather than guessing them, applied here to Helm values instead of an API). Never commit the plaintext password anywhere -- only the sealed ciphertext file.
3. Create `infrastructure/kube-prometheus-stack/argocd/appset.yaml` as a multi-source `ApplicationSet`, using the generator the spike story confirmed (read that issue's decision before writing this), modeled on `apps/akkoma/argocd/appset.yaml`'s two-source shape and `infrastructure/traefik-gateway/argocd/appset.yaml`'s Helm-repo-chart source shape:
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: ApplicationSet
   metadata:
     name: kube-prometheus-stack
     namespace: argocd
   spec:
     generators:
     - clusters: {}   # or the spike's confirmed fallback -- do not assume this is final
     template:
       metadata:
         name: 'kube-prometheus-stack-{{name}}'   # field name per the spike's confirmed decision
       spec:
         project: default
         sources:
         - repoURL: https://prometheus-community.github.io/helm-charts
           chart: kube-prometheus-stack
           targetRevision: '<confirmed current stable version>'
           helm:
             releaseName: kube-prometheus-stack
             valuesObject:
               grafana:
                 admin:
                   existingSecret: grafana-admin
                   userKey: admin-user
                   passwordKey: admin-password
               prometheus:
                 prometheusSpec:
                   storageSpec:
                     volumeClaimTemplate:
                       spec:
                         storageClassName: local-path
                         accessModes: ["ReadWriteOnce"]
                         resources:
                           requests:
                             storage: 10Gi
         - repoURL: https://github.com/adamancini/argo-fleet.git
           targetRevision: HEAD
           path: infrastructure/kube-prometheus-stack/argocd
           directory:
             include: '*.sealed.yaml'
         destination:
           name: '{{name}}'   # field name per the spike's confirmed decision
           namespace: monitoring
         syncPolicy:
           automated:
             prune: true
             selfHeal: true
           syncOptions:
           - CreateNamespace=true
   ```
   `helm.releaseName: kube-prometheus-stack` is set explicitly (fixed, not templated per cluster) so the Grafana/Prometheus Service names are deterministic and identical across every cluster -- each cluster has its own namespace-scoped copy, so there's no naming collision, and a fixed release name is what the HTTPRoute follow-on story needs to reference a stable backend service name. Confirm the exact multi-source `sources:` syntax (Argo CD requires `sources:` plural with no top-level `source:` when multi-source is used) against `apps/akkoma/argocd/appset.yaml`'s working example before committing -- do not hand-guess the schema.
4. Push and confirm via `argocd app list`/Portal that `kube-prometheus-stack-demo1` and `kube-prometheus-stack-demo2` (or whatever names the confirmed template field produces) sync to `Healthy`, the `monitoring` namespace is created on both clusters, the Prometheus PVC binds (`kubectl get pvc -n monitoring` shows `Bound`, not `Pending`), and Grafana's login page is reachable via `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80` and accepts the sealed-secret credentials (this port-forward check is temporary verification for this story only -- a follow-on story provides real external reachability via HTTPRoute).

KEY FILES:
`infrastructure/kube-prometheus-stack/README.md` (new), `infrastructure/kube-prometheus-stack/argocd/appset.yaml` (new), `infrastructure/kube-prometheus-stack/argocd/secret-grafana-admin.sealed.yaml` (new, generated ciphertext -- not hand-written). Reference-only (not modified): `infrastructure/traefik-gateway/argocd/appset.yaml`, `infrastructure/openebs-localpv/argocd/appset.yaml`, `apps/akkoma/argocd/appset.yaml`, `apps/akkoma/env/prod/secret-app.sealed.yaml`, `AGENTS.md`, `Taskfile.yml` (for the `sealed-secrets:seal` task signature).

OUT OF SCOPE:
- Custom Grafana dashboards or datasources beyond the chart's own bundled Prometheus datasource -- confirmed out of scope by the user for this round.
- Prometheus alerting rules / Alertmanager routing config beyond chart defaults -- confirmed out of scope by the user for this round.
- Storage sizing/retention tuning beyond the one explicit `10Gi` PVC size set here to make binding observable -- if the user wants a different size later, that's a follow-up story, not a reason to leave `storageSpec` unset now (unset would reintroduce the exact binding risk this story exists to avoid).
- External reachability (HTTPRoute) -- that's a separate follow-on story; this story's own verification uses `kubectl port-forward` only, which is explicitly temporary/internal-only.
- The 5 existing infra apps' generator migration -- that's a separate follow-on story, running in parallel (both depend only on the spike story).

DIFF BUDGET:
3 new files (`infrastructure/kube-prometheus-stack/README.md`, `infrastructure/kube-prometheus-stack/argocd/appset.yaml`, `infrastructure/kube-prometheus-stack/argocd/secret-grafana-admin.sealed.yaml`), 0 files modified elsewhere. Expect roughly 80-150 LOC total (the sealed secret's ciphertext is long but is generated, not hand-written).

CONSUMES:
- AF-ogxu: this issue's own Notes/Comments -> Decision record
    spec: generator: 'clusters: {}' | 'list (fallback)'; template_field: '{{name}}' | '{{server}}' | '<other>' | 'N/A (fallback)'; confirmed_cluster_names: ['demo1','demo2'] | []
    source: the spike story's empirical finding

PRODUCES:
- `infrastructure/kube-prometheus-stack/README.md` -> what the dependency is, why every cluster needs it, bootstrap step (SealedSecret must exist)
- `infrastructure/kube-prometheus-stack/argocd/appset.yaml` -> multi-source ApplicationSet
    spec: generators: [{clusters: {}} or confirmed fallback]; sources: [helm-chart(kube-prometheus-stack, releaseName: kube-prometheus-stack), git-directory('*.sealed.yaml')]; destination.namespace: monitoring
    source: this story's own design, modeled on apps/akkoma/argocd/appset.yaml (multi-source shape) and infrastructure/traefik-gateway/argocd/appset.yaml (Helm-repo-chart source shape)
- `infrastructure/kube-prometheus-stack/argocd/secret-grafana-admin.sealed.yaml` -> SealedSecret, namespace monitoring, keys admin-user/admin-password (confirm exact key names against pinned chart version)
    schema: apiVersion: bitnami.com/v1alpha1, kind: SealedSecret (same CRD shape as apps/akkoma/env/prod/secret-app.sealed.yaml)
    source: generated via `task sealed-secrets:seal`, per AGENTS.md

TESTING:
No unit test suite exists for this repo's GitOps manifests. Verification is operational, all required (not optional) before this story is considered done:
- `kubectl get pvc -n monitoring` on both `demo1` and `demo2` shows the Prometheus PVC `Bound`, not `Pending`.
- `argocd app list` (or equivalent) shows `kube-prometheus-stack-<cluster>` `Synced`/`Healthy` on both clusters.
- `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80` then logging into `http://localhost:3000` with the sealed-secret credentials succeeds (not the chart's default `admin`/`prom-operator` credentials -- if those still work, the `existingSecret` wiring failed).
- `devops-toolkit:yaml-kubernetes-validator` used to lint the new appset.yaml before pushing; `devops-toolkit:helm-chart-developer` consulted for the Helm values shape.

Acceptance Criteria:
1. [Event] When the ApplicationSet reconciles, `kube-prometheus-stack-<cluster>` Applications are created for every cluster the confirmed generator discovers (both `demo1` and `demo2` at minimum).
2. [Ubiquitous] Prometheus, Grafana, Alertmanager, node-exporter, and kube-state-metrics are all deployed as part of the single chart install (no separate charts).
3. [Ubiquitous] Grafana's admin credentials come from `grafana.admin.existingSecret` referencing the `SealedSecret` created in this story -- the chart's own default/random admin password is never active.
4. [Ubiquitous] Prometheus's PVC sets `storageClassName` explicitly and is `Bound` on both `demo1` and `demo2`.
5. [Unwanted] The `SealedSecret`'s plaintext password shall never appear in git history, in the ApplicationSet YAML, or in any committed file.
6. [Event] On `kubectl port-forward` to the Grafana service, the user can log in with the sealed-secret credentials and Grafana displays its default dashboard home.
7. No custom dashboards, alerting rules, or non-default storage sizing beyond the one explicit PVC size are introduced (confirmed out of scope).

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory), devops-toolkit:helm-chart-developer (mandatory -- Helm values shape, chart conventions), devops-toolkit:yaml-kubernetes-validator (mandatory -- manifest validation)

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-07T15:07:23Z dep_added: blocked_by AF-ogxu
- 2026-08-07T15:07:23Z dep_added: blocks AF-j4fp
- 2026-08-07T15:07:24Z dep_added: blocks AF-7u8n
- 2026-08-07T15:33:33Z dep_removed: was_blocked_by AF-ogxu
- 2026-08-07T15:39:03Z status: open -> in_progress
- 2026-08-07T15:39:03Z auto-follows: linked to predecessor AF-ogxu
- 2026-08-07T15:39:03Z claimed by dev-AF-d3ax
- 2026-08-07T16:29:24Z status: in_progress -> in_progress
- 2026-08-07T16:29:24Z auto-follows: linked to predecessor AF-qmy9

## Links
- Parent: [[AF-d66a]]
- Blocks: [[AF-j4fp]], [[AF-7u8n]]
- Was blocked by: [[AF-ogxu]]
- Follows: [[AF-ogxu]], [[AF-qmy9]]

## Comments
