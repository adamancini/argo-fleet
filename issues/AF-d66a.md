---
id: AF-d66a
title: "Cluster-wide observability: kube-prometheus-stack + ApplicationSet generator consistency"
status: open
priority: 1
type: epic
created_at: 2026-08-07T15:06:05Z
created_by: ada
updated_at: 2026-08-07T15:10:51Z
content_hash: "sha256:fe64742978886b3da6a08e844b9e37e06de9063d712dacdb2b64b0d692963f7a"
---

## Description
Description:
Add Prometheus + Grafana + Alertmanager (bundled as the single `kube-prometheus-stack` Helm chart) as a new cluster-wide `infrastructure/` dependency covering every current and future Argo CD workload cluster, and retrofit the 5 existing `infrastructure/*/argocd/appset.yaml` apps from a hardcoded `list` generator onto Argo CD's `clusters: {}` generator so cluster targeting is discovered automatically instead of hand-maintained.

BUSINESS CONTEXT: (brownfield feedback intake, no BUSINESS.md -- this is the "why" as stated directly by the user)
The user runs `argo-fleet`, a personal GitOps repo (Argo CD + Kargo, migrating off Flux/`fleet-infra`) currently targeting two k3d staging clusters (`demo1`, `demo2`) ahead of the real `annarchy.net`/`staging.annarchy.net` clusters. There is currently no cluster-wide monitoring: no metrics collection, no dashboards, no visibility into what's running on either cluster. The explicit ask: "add Grafana and Prometheus to our infrastructure dependencies for all clusters" -- and, in the same breath, stop hand-maintaining the cluster list every time a new workload cluster gets added, since every `infrastructure/*/argocd/appset.yaml` today hardcodes `demo1`/`demo2` in a `list` generator and a third/future cluster would require editing five files by hand plus the new one.

PROBLEM BEING SOLVED:
Current state: (1) zero observability stack on any cluster; (2) every infra dependency's cluster targeting is a hand-maintained `list` generator with `demo1`/`demo2` baked in -- adding a cluster means editing N files, easy to forget one. Target state: (1) Prometheus + Grafana + Alertmanager running on every registered workload cluster, Grafana externally reachable over HTTP via the existing Traefik Gateway API dependency; (2) every `infrastructure/*/argocd/appset.yaml` (the new kube-prometheus-stack one and the 5 pre-existing ones) uses Argo CD's `clusters: {}` ApplicationSet generator, which fans out over whatever clusters are actually registered with the Argo CD instance -- no file edits needed when `demo1`/`demo2` are joined by a third cluster or eventually replaced by the real `annarchy.net`/`staging.annarchy.net` clusters.

TARGET STATE:
- `infrastructure/kube-prometheus-stack/README.md` and `infrastructure/kube-prometheus-stack/argocd/appset.yaml` exists, deploying the `kube-prometheus-stack` chart (Prometheus Operator + Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics) to every cluster the `clusters: {}` generator discovers.
- Grafana's admin password is wired to a `SealedSecret` via `grafana.admin.existingSecret` -- never a chart-generated random password (Argo CD renders via `helm template` with no cluster access, so a chart-default random admin password would regenerate on every sync -- see AGENTS.md's Secrets section and the `sealed-secrets:seal` Taskfile command).
- Prometheus's PVC (`prometheus.prometheusSpec.storageSpec`) sets `storageClassName` explicitly to `local-path` (the StorageClass `infrastructure/openebs-localpv` creates, currently `isDefaultClass: true` per that app's current config -- but this MUST NOT be assumed permanent; verify current default-class state at implementation time) -- omitting it risks the exact "PVC never binds" failure mode this fleet has hit before with non-default StorageClasses.
- Grafana is reachable externally over plain HTTP via an `HTTPRoute` (`gateway.networking.k8s.io/v1`) with `parentRefs` pointing at the existing `traefik-gateway` Gateway (namespace `traefik`) -- the first real workload wired to that Gateway in this repo (traefik-gateway itself notes in its own README that nothing is wired to it yet).
- All 5 pre-existing infra apps (`sealed-secrets`, `traefik-gateway`, `gateway-api-crds`, `openebs-localpv`, `argo-rollouts-crds`) are migrated from `generators: [{list: {elements: [{cluster: demo1},{cluster: demo2}]}}]` to `generators: [{clusters: {}}]`, using whatever template variable the clusters generator actually exposes (confirmed by the first story in this epic, not assumed).
- `docs/infra-dependencies.md` no longer instructs "use a list generator" as the default recipe; it documents the confirmed convention (or the confirmed fallback, see Risk below).

ARCHITECTURE INTEGRATION: (no formal ARCHITECTURE.md exists for this brownfield repo; this section embeds the repo's own architecture docs as the analog, per AGENTS.md/README.md/docs/infra-dependencies.md)
- This repo's Argo CD/Kargo control plane is Akuity-hosted, not plain OSS Argo CD. Cluster/agent registration for `demo1`/`demo2` goes through the `akp` Terraform provider (`terraform/clusters/`, `akp_cluster` + `akp_kargo_agent` resources). Per the `devops-toolkit:akp-platform` skill's `references/argocd-declarative-setup.md`: "cluster/agent registration instead goes through the `akp` Terraform provider... the Akuity Agent connects outbound and no cluster credentials are stored centrally, so this [hand-authored `argocd.argoproj.io/secret-type: cluster` Secret] mechanism isn't something you author yourself here." Plain OSS Argo CD's ApplicationSet `clusters: {}` generator works by listing exactly those hand-authored cluster Secrets in the Argo CD namespace. Whether Akuity's hosted control plane creates equivalent, generator-discoverable Secrets under the hood for its Terraform-registered clusters is UNCONFIRMED -- this is the epic's central technical risk, and the reason the first story is a spike, not a migration.
- `bootstrap/infra-apps.yaml` auto-discovers every `infrastructure/*/argocd` directory via a git-directories generator. No changes to `bootstrap/` are ever required to add `infrastructure/kube-prometheus-stack/` -- AGENTS.md is explicit: "Never add app-specific config here."
- Existing infra apps use two source shapes: git-repo-with-path (`sealed-secrets`, `gateway-api-crds`, `argo-rollouts-crds` -- `repoURL` is a plain git clone URL, `path` selects a subdirectory) and Helm-repo-chart (`traefik-gateway` -- `repoURL` is a Helm chart repository, `chart`+`targetRevision` select the chart and version, no `path`). `kube-prometheus-stack` is published as a Helm-repo chart (`repoURL: https://prometheus-community.github.io/helm-charts`, `chart: kube-prometheus-stack`), so `traefik-gateway/argocd/appset.yaml` is the closer template to copy, not `sealed-secrets`.
- Secrets convention (AGENTS.md, non-negotiable): never rely on Helm `lookup` for "generate once" secrets -- Argo CD renders charts via `helm template` with no cluster access, so any chart-generated value regenerates every sync. Use the chart's `existingSecret` field, create the real Secret as a `SealedSecret` via `task sealed-secrets:seal -- <namespace> <name> <output-path> <key>=<value> [...]`, and reference it by name. Never put secret material in a plain values file.
- Sealed Secrets keypair is deliberately shared across every cluster in this fleet (`CLUSTERS` = `k3d-demo1 k3d-demo2` in the Taskfile's `sealed-secrets:*` tasks) -- one sealed ciphertext decrypts on either cluster, so a single `SealedSecret` manifest (see `apps/akkoma/env/prod/secret-app.sealed.yaml` for the exact CRD shape: `apiVersion: bitnami.com/v1alpha1`, `kind: SealedSecret`, `spec.encryptedData`, `spec.template.metadata`) can be synced to both `demo1` and `demo2` without re-sealing per cluster.
- Existing multi-source Application precedent for "Helm chart + hand-authored manifest living in this repo": `apps/akkoma/argocd/appset.yaml` uses two `sources` entries -- one Helm-repo/OCI chart source, one git-repo source with `directory: {include: '*.sealed.yaml'}` pointing at this repo's own path, so a `SealedSecret` file committed alongside the appset syncs as a second resource in the same Application. `kube-prometheus-stack`'s Grafana admin secret needs the same two-source shape.

DESIGN REQUIREMENTS: (no formal DESIGN.md; UI/UX-relevant repo conventions embedded here)
- Grafana must be reachable the same way other UIs in this fleet are (or will be) exposed: an `HTTPRoute` against the `traefik-gateway` Gateway, not port-forward-only. The exact shape (`apiVersion: gateway.networking.k8s.io/v1`, `kind: HTTPRoute`, `spec.parentRefs: [{name: traefik-gateway, namespace: traefik}]`, `spec.rules[].backendRefs`) is confirmed against `fleet-infra`'s existing routes (e.g. `infrastructure/core-config/homarr-route.yaml`), the pattern `traefik-gateway`'s own README says future `HTTPRoute`s here should reference.
- No real domain exists yet for anything in this fleet (`akkoma`/`soju` still use placeholder `*.example.com` domains, `cert-manager` is explicitly deferred fleet-wide until real domains exist -- see `docs/infra-dependencies.md`'s "Candidates already identified but deferred" and `infrastructure/traefik-gateway/README.md`'s "What's NOT enabled yet"). Grafana's `HTTPRoute` therefore uses the same placeholder-domain convention, plain HTTP only (`websecure`/TLS listener stays off, matching every other route in this fleet) -- consistent with existing practice, not a new gap this epic introduces.
- Out of scope for this round, confirmed directly with the user: no custom Grafana dashboards, no Prometheus alerting rules, no retention/storage sizing tuning beyond a small, explicit default. The goal is a running, reachable stack -- not a tuned one.

RISK (read before starting story 1):
The single biggest unknown is whether Argo CD's ApplicationSet `clusters: {}` generator actually returns `demo1`/`demo2` on this Akuity-hosted instance -- see ARCHITECTURE INTEGRATION above. If the spike (story 1) finds it does NOT work as OSS Argo CD would, the fallback is: stay on the `list` generator, but stop hand-maintaining it -- generate the `elements:` list from a single source of truth (e.g. a small script reading cluster names out of `terraform/clusters/terraform.tfvars` or its output, run as a pre-commit/Taskfile step, or a `git` generator over `terraform/clusters/.kubeconfigs/*.yaml` filenames) rather than reverting to purely hand-edited YAML. Story 1's acceptance criteria require documenting which path is taken and updating stories 2 and 3 accordingly -- this epic does not silently block if the ideal path fails.

Acceptance Criteria:
1. The `clusters: {}` generator's actual behavior against this Akuity-hosted instance is confirmed and documented (works with standard OSS template fields, works with different fields, or does not work at all) before any of the 5 existing infra apps are touched.
2. All 5 existing `infrastructure/*/argocd/appset.yaml` files use the confirmed generator approach (either `clusters: {}` or the documented fallback) instead of a hardcoded `list` generator, with identical treatment applied to all 5 -- not five bespoke edits.
3. `infrastructure/kube-prometheus-stack/README.md` and `infrastructure/kube-prometheus-stack/argocd/appset.yaml` exists, deploys Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics via the single `kube-prometheus-stack` chart, to every cluster the confirmed generator approach discovers.
4. Grafana's admin credentials come from a `SealedSecret` referenced via `grafana.admin.existingSecret` -- never a chart-generated default.
5. Prometheus's PVC explicitly sets `storageClassName` and binds successfully (not left to implicit/default StorageClass resolution).
6. Grafana is reachable externally over HTTP via an `HTTPRoute` against the `traefik-gateway` Gateway from outside the cluster (not port-forward-only), on both `demo1` and `demo2`.
7. `docs/infra-dependencies.md` reflects the generator convention actually adopted (whichever path story 1 confirms), replacing its current "use a list generator" instruction.
8. No dashboards, alerting rules, or storage-sizing tuning beyond a small explicit default are introduced -- confirmed explicitly out of scope by the user for this round.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (always -- especially `references/gitops-app-patterns.md` and `references/argocd-declarative-setup.md`), devops-toolkit:helm-chart-developer, devops-toolkit:yaml-kubernetes-validator

## Acceptance Criteria


## Design


## Notes


## History


## Links


## Comments
