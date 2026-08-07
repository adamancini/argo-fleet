# kube-prometheus-stack — cluster-wide dependency, no promotion pipeline

Installs [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
on every workload cluster. One chart, one Application per cluster — the
whole observability bundle ships together:

| Component | Where it comes from |
|---|---|
| Prometheus Operator | parent chart (`Deployment`) |
| Prometheus | parent chart (`Prometheus` CR) |
| Alertmanager | parent chart (`Alertmanager` CR) |
| Grafana | bundled `grafana` subchart |
| node-exporter | bundled `prometheus-node-exporter` subchart |
| kube-state-metrics | bundled `kube-state-metrics` subchart |

Like everything else under `infrastructure/`, this is a singleton that must
exist identically everywhere, so it has no Kargo `dev → staging → prod`
pipeline — the chart version is pinned directly in `argocd/appset.yaml` and
bumped by hand (or by Renovate).

## Cluster discovery

Unlike the older infra appsets (`traefik-gateway`, `openebs-localpv`, which
use a hand-maintained `list` generator), this uses a **`clusters`
generator**, so a cluster registered later gets the stack with no edit here.

The selector is **not optional**:

```yaml
selector:
  matchExpressions:
  - key: akuity.io/argo-cd-cluster-name
    operator: NotIn
    values: [in-cluster, kargo]
```

A bare `clusters: {}` also matches the Akuity-hosted control plane
(`in-cluster`, which is namespace-scoped to `argocd` alone) and the `kargo`
cluster. Neither should run a monitoring stack.

Destinations use `destination.name: '{{name}}'`. Never `{{server}}` — on an
Akuity-hosted instance that resolves to an internal proxy URL
(`http://cluster-demo1:8001`), not a reachable API endpoint.

## Bootstrap step: the Grafana admin SealedSecret

**Required before (or alongside) the Application syncs**, in the same spirit
as `sealed-secrets` needing its shared keypair pre-created.

`secrets/secret-grafana-admin.sealed.yaml` holds the Grafana admin
credentials, and `argocd/appset.yaml` points the chart at it via
`grafana.admin.existingSecret: grafana-admin`. The ApplicationSet is
multi-source: the Helm chart plus this repo's `secrets/` path, so the
SealedSecret is delivered by the same Application that installs Grafana.

This is load-bearing, not defensive. Left unset, the bundled `grafana`
subchart falls back to its `grafana.password` helper:

```gotemplate
{{- $secret := (lookup "v1" "Secret" ... ) }}
{{- if $secret }}{{- index $secret "data" "admin-password" }}
{{- else }}{{- (randAlphaNum 40) | b64enc | quote }}{{- end }}
```

Argo CD renders charts with `helm template` and no cluster access, so that
`lookup` **always** misses and a fresh 40-character password is generated on
every single sync — see AGENTS.md "Secrets". With `admin.existingSecret`
set, the subchart skips creating its own admin Secret entirely and wires
`GF_SECURITY_ADMIN_USER`/`GF_SECURITY_ADMIN_PASSWORD` straight at
`grafana-admin`.

To re-seal (rotated password, or after `sealed-secrets:rotate-keypair`):

```bash
task sealed-secrets:seal -- monitoring grafana-admin \
  infrastructure/kube-prometheus-stack/secrets/secret-grafana-admin.sealed.yaml \
  admin-user=admin admin-password="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9')"
```

To read the current password back out of a live cluster:

```bash
kubectl --context k3d-demo1 -n monitoring get secret grafana-admin \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

### Why `secrets/` and not `argocd/`

`bootstrap/infra-apps.yaml` discovers `infrastructure/*/argocd` and syncs
each matched directory **wholesale** (`directory.recurse: true`, auto-prune)
to the `in-cluster` destination. A SealedSecret sitting in `argocd/` would
therefore be applied to the Akuity control plane, which is namespace-scoped
to `argocd` and has no `bitnami.com/v1alpha1` CRD registered at all.
Anything cluster-bound has to live outside that glob — the same separation
`apps/akkoma` uses (ApplicationSet in `argocd/`, SealedSecrets in
`env/<stage>/`).

## Storage

`prometheus.prometheusSpec.storageSpec.volumeClaimTemplate` sets
`storageClassName: local-path` **explicitly**, even though
`openebs-localpv` currently marks that class default on every cluster.
Relying on the default is how this fleet previously left a PVC
`Pending` forever the moment the default moved. `local-path` uses
`WaitForFirstConsumer`, so the PVC stays `Pending` until the Prometheus pod
is scheduled — that is normal, not the failure mode above.

Size is a flat `10Gi`; retention is left at chart default.

## `ServerSideApply=true` is required

Six of the prometheus-operator CRDs (`prometheuses`, `alertmanagers`,
`alertmanagerconfigs`, `prometheusagents`, `scrapeconfigs`, `thanosrulers`)
are larger than the 262144-byte ceiling Kubernetes puts on the
`kubectl.kubernetes.io/last-applied-configuration` annotation that
client-side apply writes. Without this sync option the sync fails with:

```
CustomResourceDefinition ... is invalid: metadata.annotations: Too long:
  may not be more than 262144 bytes
```

and then, as a knock-on, the `Prometheus`/`Alertmanager` CRs fail with
`no matches for kind "Prometheus" ... ensure CRDs are installed first`.
Server-side apply doesn't write that annotation. This was observed on this
instance, not assumed — see the story's delivery notes.

## Release name

`helm.releaseName` is pinned to `kube-prometheus-stack` rather than
templated per cluster, so Service names (`kube-prometheus-stack-grafana`,
`kube-prometheus-stack-prometheus`, …) are identical on every cluster. The
follow-up that exposes Grafana through the Traefik `Gateway` depends on
that.

## What's NOT configured

- No custom dashboards or datasources beyond the chart's own bundled
  Prometheus datasource and default dashboards.
- No custom alerting rules or Alertmanager routing beyond chart defaults.
- No external reachability — no `HTTPRoute` yet. Reach Grafana with
  `kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80`
  until that lands.
