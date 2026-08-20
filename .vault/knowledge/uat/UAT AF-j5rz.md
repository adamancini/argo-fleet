---
type: uat
project: argo-fleet
status: active
epic: AF-j5rz
created: 2026-08-20
---

## UAT: arr-stack DRY ApplicationSet + generated Kargo pipelines PoC (AF-j5rz)

### Prerequisites
- Repo checked out at or after commit `bf6da6e` on `main` (`git -C /Users/ada/src/github.com/adamancini/argo-fleet log --oneline -n 1 main`).
- `argocd` CLI logged in to the shared Akuity-hosted instance (`task argocd:login` if the session has expired).
- `kargo` CLI available and authenticated against the same instance.
- `kubectl` contexts `k3d-demo1` and `k3d-demo2` configured and reachable (`k3d cluster start <name>` + re-merge kubeconfig if either was restarted recently -- k3d reassigns the API port on every restart).
- Ruby installed (stock interpreter is sufficient; no gems required).

### Test: static manifest suite is internally coherent
Do:
1. `cd /Users/ada/src/github.com/adamancini/argo-fleet`
2. `ruby e2e/observability_test.rb`

Expected:
- `RESULT: PASS -- 589 assertions, 0 failures`, exit code `0`.
- No `overseerr` references, no `oci://` substring in `appset-workloads.yaml`, no `tag:` binding of the promotion digest anywhere under `apps/arr-stack/`.

### Test: the wrapper Application and both ApplicationSets are healthy with the right shape
Do:
1. `argocd app get argocd-arr-stack`
2. `argocd appset get arr-stack-workloads`
3. `argocd appset get arr-stack-kargo`

Expected:
- `argocd-arr-stack`: `Synced` / `Healthy`, source path `apps/arr-stack/argocd`, destination `in-cluster`.
- `arr-stack-workloads`: exactly 18 generated Applications, named `arr-sonarr-dev` ... `arr-seerr-prod` (never `arr-overseerr-*`).
- `arr-stack-kargo`: exactly 6 generated Applications, named `kargo-arr-sonarr` ... `kargo-arr-seerr` (never `kargo-arr-overseerr`).

### Test: Sonarr's full vertical slice (workload + Kargo pipeline) is genuinely live-healthy
Do:
1. `argocd app get arr-sonarr-dev`
2. `kubectl --context k3d-demo1 -n arr-stack-dev get pvc`
3. `kubectl --context k3d-demo1 -n arr-stack-dev get pods`
4. `kargo get project sonarr`
5. `kargo get warehouse --project sonarr`
6. `kargo get stage --project sonarr`

Expected:
- `arr-sonarr-dev`: `Synced` / `Healthy`.
- Both `arr-sonarr-dev-config` and `arr-sonarr-dev-downloads` PVCs show `Bound` (never `Pending`).
- The Sonarr pod shows `Running`, `1/1` ready.
- Kargo `Project sonarr`: `READY: True`.
- Kargo `Warehouse sonarr`: present, `Ready=True`, has discovered at least one piece of Freight from `ghcr.io/hotio/sonarr:release`.
- Kargo `Stage`s `dev`/`staging`/`prod`: all present under project `sonarr`; a fresh environment may show `NoFreight` on stages that haven't been promoted into yet -- that is expected, not an error (look for `reason: Error` specifically, which should never appear).

### Test: the epic's central DRY claim -- a real promotion auto-updates the workload Application with zero manual edits
Do:
1. `argocd appset generate apps/arr-stack/argocd/appset-workloads.yaml -o json --grpc-web > before.json`
2. `kargo promote --project sonarr --stage dev --freight-alias <current-freight-alias>` (find the alias via `kargo get freight --project sonarr`), or hand-edit `apps/arr-stack/env/sonarr/dev/release.yaml`'s `imageTag` and push to `main` to simulate it.
3. Wait ~45 seconds (repo-server git refresh can lag a fresh push), then: `argocd appset generate apps/arr-stack/argocd/appset-workloads.yaml -o json --grpc-web > after.json`
4. `diff -u before.json after.json`
5. `kubectl --context k3d-demo1 -n arr-stack-dev get pod -o jsonpath='{.items[0].spec.containers[0].image}'`
6. `git log --oneline -n 5 origin/main -- apps/arr-stack/argocd/appset-workloads.yaml`

Expected:
- The diff in step 4 touches ONLY `arr-sonarr-dev`'s rendered digest field -- every other one of the 18 rendered Applications is byte-identical before/after.
- The pod's running image in step 5 shows the new digest (`ghcr.io/hotio/sonarr@sha256:<new digest>`).
- Step 6 shows no new commit to `appset-workloads.yaml` since its last real code change -- confirming the file was never manually touched to make the promotion take effect.

### Test: pre-existing fleet resources were never disturbed
Do:
1. `argocd app list`
2. `argocd appset list`

Expected:
- Every pre-existing Application/ApplicationSet in the fleet (`akkoma-*`, `soju-*`, the infra apps, `kube-prometheus-stack-*`, `fleet-argocd-apps`, `fleet-kargo-apps`) still shows the same `Synced`/`Healthy` status and child count it had before this epic merged.
- `bootstrap/*.yaml` is untouched: `git diff <pre-epic-base-commit> --name-only -- bootstrap/` returns no lines.
