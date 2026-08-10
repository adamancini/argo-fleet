---
type: uat
project: argo-fleet
epic: AF-d66a
status: active
created: 2026-08-10
---

# UAT: Cluster-wide observability (kube-prometheus-stack + ApplicationSet generator consistency)

Epic AF-d66a. Merged to `main` at commit `0fffaaa`. This script verifies the epic delivers what was asked: "add Grafana and Prometheus to our infrastructure dependencies for all clusters," reachable, with cluster targeting no longer hand-maintained per file.

## Prerequisites
- `kubectl` contexts `k3d-demo1` and `k3d-demo2` configured and reachable.
- `argocd` CLI logged in to the Akuity-hosted instance:
  ```bash
  source /Users/ada/src/github.com/adamancini/argo-fleet/.envrc
  HOSTNAME=$(terraform -chdir=/Users/ada/src/github.com/adamancini/argo-fleet/terraform/clusters output -raw argocd_hostname)
  argocd login "$HOSTNAME" --username admin --password "$TF_VAR_admin_password" --grpc-web
  ```
  (Never `cat`/echo `.envrc` or the password variable -- source/use them programmatically only.)
- `main` has been synced by Argo CD (the ApplicationSets are auto-discovered via `bootstrap/infra-apps.yaml`; no manual apply needed once merged).

### Test: static manifest correctness (no cluster needed)
Do:
1. `ruby /Users/ada/src/github.com/adamancini/argo-fleet/e2e/observability_test.rb`

Expected:
- Output ends with `RESULT: PASS -- 150 assertions, 0 failures` (or a higher assertion count if the suite has grown since).
- If this fails, stop -- do not proceed to live checks against a manifest set known to be internally inconsistent.

### Test: all 6 infra Applications healthy on both clusters, generator migration intact
Do:
1. `argocd app list --grpc-web -o wide`

Expected:
- 12 Applications total: `sealed-secrets-{demo1,demo2}`, `traefik-gateway-{demo1,demo2}`, `gateway-api-crds-{demo1,demo2}`, `openebs-localpv-{demo1,demo2}`, `argo-rollouts-crds-{demo1,demo2}`, `kube-prometheus-stack-{demo1,demo2}`.
- Every one of the 5 pre-existing apps is `Synced`/`Healthy`.
- `kube-prometheus-stack-demo1`/`-demo2` are `Healthy`; `Synced` is expected (the AF-mnpo `ignoreDifferences` fix should keep it out of permanent `OutOfSync`) -- if either shows `OutOfSync`, check `kubectl get httproute grafana -n monitoring -o json | jq .status.parents` before assuming a regression, since `argocd app diff` alone will NOT reveal Gateway API drift (see the debug note on Gateway API server-side defaulting in this vault).
2. `argocd cluster list --grpc-web` and confirm no `Application` targets `in-cluster` or `kargo` for any of the 6 infra apps above.

### Test: Prometheus is actually collecting metrics, on both clusters
Do:
1. `kubectl --context k3d-demo1 get pvc -n monitoring`
2. `kubectl --context k3d-demo1 port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &`
3. Open `http://localhost:9090/targets` in a browser (or `curl -s 'localhost:9090/api/v1/query?query=count(up==1)'`)
4. Repeat steps 1-3 against `k3d-demo2`.

Expected:
- PVC `STATUS=Bound`, `STORAGECLASS=local-path`, on both clusters.
- `/targets` shows all scrape targets `UP` (at minimum: `kube-state-metrics`, `node-exporter`, `prometheus` itself), `0` down, on both clusters.

### Test: Grafana is reachable externally via the Traefik Gateway, on both clusters
Do:
1. `kubectl --context k3d-demo1 port-forward -n traefik svc/traefik-gateway-demo1 18080:80 &`
2. `curl -s -o /dev/null -w '%{http_code}\n' http://localhost:18080/` (expect a redirect to `/login`)
3. `curl -s http://localhost:18080/login | grep -o '<title>[^<]*</title>'`
4. Repeat against `k3d-demo2` on its own `traefik-gateway-demo2` Service and a different local port.

Expected:
- Step 2 returns `302` redirecting to `/login`.
- Step 3 returns `<title>Grafana</title>`.
- If you instead get a plain `404 page not found` on a fresh cluster state, check `kubectl get gateway traefik-gateway -n traefik -o jsonpath='{.spec.listeners}'` for `allowedRoutes.namespaces.from: All` -- `Same` means the namespacePolicy fix did not land (see the convention note on cross-namespace Gateway API routes in this vault).

### Test: Grafana login uses the real sealed-secret credentials, not chart defaults
Do:
1. Retrieve the real password (never print it to a shared terminal/log):
   ```bash
   kubectl --context k3d-demo1 -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d
   ```
2. Log in to Grafana (via the port-forwarded URL from the previous test) with username `admin` and the retrieved password.
3. As a negative control, try logging in with the chart's default password `prom-operator` instead.

Expected:
- Step 2's real sealed-secret password logs in successfully (HTTP 200 / redirected to the Grafana home dashboard).
- Step 3's chart-default password is rejected (401) -- confirms the `existingSecret` wiring is actually active, not silently falling back to a chart-generated default.

### Test: Grafana's bundled dashboards render real data (no custom dashboards were added -- confirm the chart's own ship with it)
Do:
1. In the logged-in Grafana UI, open Dashboards -> search, and open the bundled **"Node Exporter / Nodes"** dashboard.
2. Select the cluster/instance from its template-variable dropdowns if prompted.

Expected:
- CPU/memory/disk panels render non-empty, non-error time series (not a "No data" panel).
- No custom/user-created dashboards exist beyond what the chart ships (confirms the epic's explicit "no custom dashboards" scope boundary held).

### Test: adding a hypothetical 3rd cluster requires zero appset file edits (documentation check, not a live action)
Do:
1. `grep -A8 'generators:' /Users/ada/src/github.com/adamancini/argo-fleet/infrastructure/sealed-secrets/argocd/appset.yaml`
2. Read `/Users/ada/src/github.com/adamancini/argo-fleet/docs/infra-dependencies.md`, "Adding a cluster-wide infra dependency" step 1.

Expected:
- The generator block uses `clusters:` with a `NotIn [in-cluster, kargo]` selector -- no hardcoded `demo1`/`demo2` list generator anywhere.
- The doc names the `clusters` generator and the exact selector key (`akuity.io/argo-cd-cluster-name`), not "use a list generator."
