---
id: AF-7u8n
title: "Verify the observability stack end-to-end across the fleet"
status: in_progress
priority: 1
type: task
labels: [capstone, delivered]
parent: AF-d66a
created_at: 2026-08-07T15:06:17Z
created_by: ada
updated_at: 2026-08-07T19:09:15Z
content_hash: "sha256:b121f4e246a6cb7d6527e8d32f7431954775e8c84bcfb088b4612f37cb38a280"
was_blocked_by: [AF-ogxu, AF-c8p4, AF-qmy9, AF-d3ax, AF-j4fp]
assignee: dev-AF-7u8n
follows: [AF-ogxu, AF-c8p4, AF-qmy9, AF-d3ax, AF-j4fp]
---

## Description
Description:
End-to-end acceptance check for the whole epic: confirm Prometheus + Grafana + Alertmanager are running and healthy on every registered workload cluster, Grafana is reachable externally with real (sealed-secret) credentials, Prometheus's storage is bound and actually collecting metrics, and all 5 migrated infra apps plus the new kube-prometheus-stack app remain healthy under the new generator convention -- as one demoable pass, not five separate spot-checks.

Context:
This is the epic's capstone: it does not introduce new code, it proves the whole epic actually delivers what was asked -- "add Grafana and Prometheus to our infrastructure dependencies for all clusters," reachable, with the generator migration applied consistently. Everything it verifies was already built by the other 5 stories in this epic; this story's only job is to run the fleet-wide check and record the result, catching anything that passed its own story's narrower verification but breaks when everything is combined (e.g., the generator migration accidentally affecting the new kube-prometheus-stack app, or the Grafana HTTPRoute breaking after a later change to one of the 5 migrated files).

USER INTENT:
The user's original ask ends with "just get the stack running and reachable" -- this story is the concrete proof that happened, across the whole fleet, not just in isolation per-story. It also re-confirms the 5 pre-existing infra apps (sealed-secrets, traefik-gateway, gateway-api-crds, openebs-localpv, argo-rollouts-crds) are still healthy after their generator migration -- the user was explicit that this migration must not silently break anything that was already working.

IMPLEMENTATION:
1. `argocd app list` (or `mcp__argocd-akuity__list_applications` if available in the executing environment): confirm every infra `Application` -- `sealed-secrets-*`, `traefik-gateway-*`, `gateway-api-crds-*`, `openebs-localpv-*`, `argo-rollouts-crds-*`, `kube-prometheus-stack-*` -- is `Synced`/`Healthy` on both `demo1` and `demo2` (or whatever cluster set the confirmed generator discovers at verification time).
2. `kubectl get pvc -n monitoring` on both clusters: Prometheus's PVC is `Bound`.
3. Open Prometheus's own UI (`kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090`, browse `/targets`) and confirm at least the in-cluster targets (kube-state-metrics, node-exporter, Prometheus itself) show as `UP` -- this is the concrete proof that "just running" actually means collecting real metrics, not just that pods exist.
4. Run the exact `curl`/Host-header command documented in the HTTPRoute story's delivery notes against both `demo1` and `demo2`, confirm Grafana's login page returns, then log in with the sealed-secret credentials from the kube-prometheus-stack story and confirm the built-in Prometheus datasource shows data (e.g. the default "Grafana / Prometheus" or any bundled dashboard rendering real metrics, without creating any NEW dashboard -- viewing what the chart ships by default is sufficient and stays within this epic's "no custom dashboards" scope).
5. Record the full pass/fail result, with the actual commands run and their output, as this story's delivery evidence.

KEY FILES:
None modified -- this is a verification-only story. Reference: every file produced by the other stories in this epic.

OUT OF SCOPE:
- Fixing anything found broken -- if this story finds a regression, it reopens/blocks on the relevant upstream story rather than silently patching it here, so the fix gets proper story-level acceptance review.
- Any new functionality -- this story adds nothing; it only verifies.

DIFF BUDGET:
0 files changed.

CONSUMES:
- AF-ogxu: this issue's own Notes/Comments -> Decision record
    spec: generator: 'clusters: {}' | 'list (fallback)'; confirmed_cluster_names: ['demo1','demo2'] | []
    source: AF-ogxu's empirical spike finding
- AF-c8p4: infrastructure/{sealed-secrets,traefik-gateway,gateway-api-crds,openebs-localpv,argo-rollouts-crds}/argocd/appset.yaml -> migrated ApplicationSets
    spec: generators: [{clusters: {}}] (or confirmed fallback); expected status: Synced/Healthy on every discovered cluster
    source: AF-c8p4's PRODUCES
- AF-d3ax: infrastructure/kube-prometheus-stack/argocd/appset.yaml -> kube-prometheus-stack ApplicationSet + SealedSecret
    spec: expected status: Synced/Healthy; Prometheus PVC: Bound; Grafana login: sealed-secret credentials accepted
    source: AF-d3ax's PRODUCES
- AF-j4fp: infrastructure/kube-prometheus-stack/argocd/grafana-httproute.yaml -> Grafana HTTPRoute
    spec: documented curl/Host-header verification command, expected to still return Grafana's login page
    source: AF-j4fp's delivery notes (TESTING section)
- AF-qmy9: docs/infra-dependencies.md -> updated generator-convention recipe
    spec: step 1 text names the generator convention actually in use fleet-wide
    source: AF-qmy9's PRODUCES

PRODUCES:
None (verification-only; result recorded as this issue's own comment/notes, not a repo artifact).

TESTING:
This entire story IS the testing/verification pass -- see IMPLEMENTATION above. No further test plan beyond what's listed there.

Acceptance Criteria:
1. [Ubiquitous] All 6 infra Applications (5 migrated + kube-prometheus-stack) are `Synced`/`Healthy` on every cluster the confirmed generator discovers.
2. [Ubiquitous] Prometheus's PVC is `Bound` on every cluster.
3. [Event] Prometheus's `/targets` page shows in-cluster scrape targets as `UP`.
4. [Event] Grafana's documented external-reachability command still succeeds, and logging in with the sealed-secret credentials succeeds.
5. [Event] Grafana's bundled default dashboard/datasource renders real metrics data (not an empty/error panel).
6. [Unwanted] No custom dashboard, alerting rule, or storage-sizing change is introduced as part of this verification story.
7. Any regression found is recorded and linked back to the responsible upstream story, not silently fixed here.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform

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
- 2026-08-07T15:07:24Z dep_added: blocked_by AF-ogxu
- 2026-08-07T15:07:24Z dep_added: blocked_by AF-c8p4
- 2026-08-07T15:07:24Z dep_added: blocked_by AF-d3ax
- 2026-08-07T15:07:25Z dep_added: blocked_by AF-j4fp
- 2026-08-07T15:07:25Z dep_added: blocked_by AF-qmy9
- 2026-08-07T15:33:33Z dep_removed: was_blocked_by AF-ogxu
- 2026-08-07T15:57:17Z dep_removed: was_blocked_by AF-c8p4
- 2026-08-07T16:10:38Z dep_removed: was_blocked_by AF-qmy9
- 2026-08-07T16:40:18Z dep_removed: was_blocked_by AF-d3ax
- 2026-08-07T17:56:41Z dep_removed: was_blocked_by AF-j4fp
- 2026-08-07T18:01:55Z status: open -> in_progress
- 2026-08-07T18:01:55Z auto-follows: linked to predecessor AF-ogxu
- 2026-08-07T18:01:55Z auto-follows: linked to predecessor AF-c8p4
- 2026-08-07T18:01:55Z auto-follows: linked to predecessor AF-qmy9
- 2026-08-07T18:01:55Z auto-follows: linked to predecessor AF-d3ax
- 2026-08-07T18:01:55Z auto-follows: linked to predecessor AF-j4fp
- 2026-08-07T18:01:55Z claimed by dev-AF-7u8n
- 2026-08-07T19:09:14Z status: in_progress -> in_progress

## Links
- Parent: [[AF-d66a]]
- Was blocked by: [[AF-ogxu]], [[AF-c8p4]], [[AF-qmy9]], [[AF-d3ax]], [[AF-j4fp]]
- Follows: [[AF-ogxu]], [[AF-c8p4]], [[AF-qmy9]], [[AF-d3ax]], [[AF-j4fp]]

## Comments

### 2026-08-07T19:09:02Z ada
## DELIVERED: AF-7u8n -- fleet-wide end-to-end verification of the observability stack

**Verification-only story. 0 files changed** (`git status --porcelain` empty; `rev-list --count origin/epic/AF-d66a..HEAD` = 0).
**SHA all evidence was produced from:** `7da2991a5986d0b254412c002ed456dc2762e1a0` (= `origin/epic/AF-d66a` head = `origin/story/AF-7u8n`).
**Scope achieved: BOTH clusters (demo1 AND demo2) fully verified live**, sequentially, then torn down to baseline.

### Live-vs-dry-run honesty statement (read this first)

`epic/AF-d66a` has **NOT** merged to `main` (`origin/main` = `773b511`, which does not contain the epic). Confirmed against the live instance, not assumed:

```
argocd appset get <name> --grpc-web -o json | jq -c '.spec.generators'
  sealed-secrets / traefik-gateway / gateway-api-crds / openebs-localpv / argo-rollouts-crds
  => [{"list":{"elements":[{"cluster":"demo1"},{"cluster":"demo2"}], ...}}]     # PRE-migration
argocd appset get traefik-gateway  -o json | jq '.spec...valuesObject.gateway'
  => {"enabled":true,"name":"traefik-gateway"}                                  # no namespacePolicy
argocd appset get kube-prometheus-stack
  => NotFound
```

So the live instance is still running the **old `list` generator**, the Gateway fix is **not live**, and kube-prometheus-stack **does not exist** as an ApplicationSet. I did **not** fabricate a "Synced" status for the migrated generator. What is live vs. rendered is labelled per-AC below.

---

### AC RESULTS

| AC | Result | Basis |
|---|---|---|
| 1. All 6 infra Applications Synced/Healthy on every discovered cluster | **FAIL (partial) -- regression found** | 5 migrated: live Synced/Healthy + render-equivalence proof. 6th (kube-prometheus-stack): live **Healthy** but permanently **OutOfSync**. See Finding 1. |
| 2. Prometheus PVC `Bound` | **PASS** (live, both clusters) | Bound / 10Gi / local-path / RWO |
| 3. `/targets` shows in-cluster targets `UP` | **PASS** (live, both clusters) | 13/13 UP, 0 down |
| 4. Grafana reachable; documented curl returns login page; HTTPRoute `Accepted` | **PASS** (live, both clusters) | `Accepted: True` + `<title>Grafana</title>` |
| 5. Login with sealed-secret creds; bundled dashboard renders real metrics | **PASS** (live, both clusters) | 200 + 2 negative controls 401 + real data |
| 6. No custom dashboard/alerting/storage-sizing change introduced | **PASS** | 0 files changed |
| 7. Regressions recorded and linked upstream, not silently fixed | **PASS** | 3 findings below; nothing patched |

---

### AC1 -- the 5 migrated ApplicationSets

Live today (old `list` generator), all 10 Applications:

```
argocd app list --grpc-web -o json | jq ... => total=26  Synced+Healthy=26
  argo-rollouts-crds-demo1/2, gateway-api-crds-demo1/2, openebs-localpv-demo1/2,
  sealed-secrets-demo1/2, traefik-gateway-demo1/2   => all Synced/Healthy
```

Because the migration is not live, I proved it **behaviorally inert** rather than claiming a live status. Both the `origin/main` (list) and story-branch (clusters) appsets were rendered **server-side against real cluster state**:

```
argocd appset generate <appset.yaml> -o json --grpc-web
```

- All 6 appsets render **exactly 2** Applications -> `demo1`, `demo2`; `in-cluster` and `kargo` correctly excluded by the selector.
- **OLD render vs NEW render, per Application spec:** 8/10 **byte-identical**. The only delta is `traefik-gateway-demo1/2`, which differs solely by AF-j4fp's intentional `gateway.listeners.web.namespacePolicy.from: All`.
- **NEW render vs the LIVE Application specs:** same result, plus an extra `"kustomize": {}` on `argo-rollouts-crds-*`. I chased that down rather than hand-waving it: `kustomize: {}` is present in **`origin/main`'s** appset too (the migration diff touches only the generator and `{{cluster}}`->`{{name}}`), and the old-vs-new render comparison is identical -- so it is Argo's server-side normalization of an empty object on the persisted Application, **not** a migration effect.

Net: the generator migration changes nothing about what gets deployed. This corroborates AF-c8p4's byte-identical-render finding independently.

### AC1 -- kube-prometheus-stack (deployed live on both clusters)

Temporary Applications built **from the rendered output of the committed appset** (same mechanism AF-d3ax used), with the git source pinned to `story/AF-7u8n`, created via `argocd app create -f`, then deleted.

Both clusters reached: all 6 pods Running, sync operation `Succeeded -- "successfully synced (all tasks run)"`, **Health: Healthy**.
Both clusters ended at app-level **Sync: OutOfSync**, caused by exactly one resource -- `HTTPRoute/grafana`. See Finding 1.

### AC2 -- Prometheus PVC (live, both clusters)

```
kubectl --context k3d-demo{1,2} get pvc -n monitoring
  prometheus-kube-prometheus-stack-prometheus-db-...-0
  status=Bound  capacity=10Gi  sc=local-path  modes=ReadWriteOnce
```

### AC3 -- Prometheus scrape targets (live, both clusters)

```
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 19090:9090
curl -s 'localhost:19090/api/v1/query?query=count(up==1)'  => 13
curl -s 'localhost:19090/api/v1/query?query=count(up==0)'  => 0
curl -s 'localhost:19090/api/v1/targets?state=active'
```

Identical on demo1 and demo2:

```
  apiserver 1/1 UP     coredns 1/1 UP        alertmanager 2/2 UP
  grafana 1/1 UP       operator 1/1 UP       prometheus 2/2 UP
  kube-state-metrics 1/1 UP   kubelet 3/3 UP   node-exporter 1/1 UP
  non-up targets: 0
```

The three targets AC3 names explicitly (kube-state-metrics, node-exporter, Prometheus itself) are all UP.

### AC4 -- HTTPRoute Accepted + curl (the two proofs AF-j4fp deferred here)

I deliberately deployed with the Gateway **still unpatched** first, to capture the transition rather than only the end state.

**BEFORE the Gateway fix** (both clusters -- independently reproduces AF-j4fp's finding):

```
kubectl get gateway traefik-gateway -n traefik -o jsonpath='{.spec.listeners}'
  => [{"allowedRoutes":{"namespaces":{"from":"Same"}},"name":"web","port":8000,"protocol":"HTTP"}]
kubectl get httproute grafana -n monitoring -o json | jq '.status.parents[]'
  => Accepted     status=False  reason=NotAllowedByListeners
     ResolvedRefs status=True   reason=ResolvedRefs        # backend resolves fine; only attachment is blocked
curl -s -o /dev/null -w '%{http_code}' http://localhost:18080/   => 404   ("404 page not found")
```

**Applying the fix.** The Gateway object is chart-managed, so before patching I proved the substitution faithful: `helm template traefik/traefik 41.1.1` fed the **valuesObject extracted verbatim from the server-rendered Application** yields exactly
`[{"allowedRoutes":{"namespaces":{"from":"All"}},"name":"web","port":8000,"protocol":"HTTP"}]`.
I then patched only that one field, and diffed the live listener against that rendered target -> **IDENTICAL** on both clusters. So the live object is byte-for-byte what the merged appset will produce.

**AFTER the fix** (both clusters):

```
kubectl get httproute grafana -n monitoring -o json | jq '.status.parents[]'
  => Accepted     status=True  reason=Accepted        <-- the proof AF-j4fp could not obtain
     ResolvedRefs status=True  reason=ResolvedRefs

kubectl port-forward -n traefik svc/traefik-gateway-demoN 18080:80
curl -s -o /dev/null -w '%{http_code} %{redirect_url}' http://localhost:18080/
  => 302  http://localhost:18080/login
curl http://localhost:18080/login            => 200
curl -L http://localhost:18080/ | grep title => <title>Grafana</title>
curl http://localhost:18080/api/health       => {"database":"ok","version":"13.1.3"}
```

404 -> Grafana login page, attributable to exactly that one field. Also confirmed Argo does **not** self-heal the patch away (`traefik-gateway-demoN` stayed Synced/Healthy, listener stayed `All`) -- the field is absent from the chart's desired manifest, so Argo ignores it.

### AC5 -- login with sealed-secret credentials + real dashboard data (both clusters)

Credentials read from the live cluster Secret into shell variables only; **the password value was never printed, echoed, or written anywhere** (29 chars, redacted). All requests go through the Traefik Gateway route, not a direct Grafana port-forward -- so this exercises the wiring, not just the component.

```
POST /login  wrong password        => 401
POST /login  chart default 'prom-operator' => 401     # proves the SealedSecret is genuinely in effect
POST /login  sealed-secret creds   => 200  {"message":"Logged in"}
GET  /api/user (session cookie)    => {"login":"admin","isGrafanaAdmin":true}
GET  /api/datasources              => Prometheus (isDefault=true), Alertmanager
GET  /api/search?type=dash-db      => 29 bundled dashboards
```

For "bundled dashboard renders real metrics" I used the chart's own dashboard, created nothing:
took **"Node Exporter / Nodes"** (uid `7d57716318ee0dddbac5a7f451fb7753`), pulled its **first panel's PromQL verbatim** from the dashboard JSON (panel "CPU Usage"), resolved the dashboard's own template variables (`$instance`, `$cluster`, `$__rate_interval`) against live Prometheus, and executed it **through Grafana's own query path** (`POST /api/ds/query` -> Prometheus datasource):

```
demo1: status=200 error=none -> 8 series, e.g. CPU Usage = 0.01214, 0.01119, 0.01083 ...
demo2: status=200 error=none -> 8 series, e.g. CPU Usage = 0.01430, 0.01237, 0.01222 ...
```

Real, non-null, non-empty data. Note: a first attempt returned `value=null` -- because `/api/ds/query` does **not** interpolate dashboard template variables (Grafana does that client-side). Reporting that because a less careful pass could read the null as "datasource broken" or, worse, skip interpolation and call a null result a pass.

---

### FINDINGS (AC7) -- recorded, not fixed

**Finding 1 -- REGRESSION. Owner: AF-j4fp (authored the HTTPRoute). Severity: low/cosmetic but permanent.**

`kube-prometheus-stack-<cluster>` will sit **permanently `OutOfSync`** (Health `Healthy`) once the epic merges. Deterministic, reproduced identically on demo1 and demo2.

Root cause: the Gateway API API-server **defaults fields on the HTTPRoute that git does not specify**, so Argo's server-side sync-status computation sees drift forever:

```
git (grafana-httproute.yaml)        live object adds
  parentRefs: name/namespace/       + group: gateway.networking.k8s.io, kind: Gateway
              sectionName
  backendRefs: name, port           + group: "", kind: Service, weight: 1
  (no matches)                      + matches: [{path:{type:PathPrefix,value:"/"}}]
```

Sharp edge worth flagging: **`argocd app diff` returns EMPTY** (exit 0) on both clusters while the app reports OutOfSync -- client-side diff normalizes these defaults away, the server's sync-status does not. Anyone triaging this with `app diff` will conclude "no drift" and be misled. Survives `--hard-refresh`.

Impact bounded honestly: Health stays `Healthy`, traffic works, and I observed **no selfHeal loop** (sync history stable at 1, `finishedAt` unchanged, over a 90s window). The concrete cost is that AC1's "all 6 Synced" is unachievable, and the app is a permanent yellow in the UI.

Not fixed here (0-file diff budget; out-of-scope per the story). Remedy for whoever owns it: either declare the defaulted fields explicitly in `grafana-httproute.yaml`, or add `ignoreDifferences` for `gateway.networking.k8s.io/HTTPRoute` on the appset.

**Finding 2 -- PRE-EXISTING, NOT this epic. `pvg gates` fails repo-wide.**

```
pvg gates                              => FAIL (14 block, 0 warn, 0 skipped)   # this branch
pvg gates  (pristine origin/main clone) => FAIL (15 block, 0 warn, 0 skipped)  # SAME failures
pvg gates --changed origin/main         => PASS (0 warn, 0 skipped)            # whole epic's diff
pvg gates --changed origin/epic/AF-d66a => PASS (no changed files to scan)     # this story
```

Duplication debt in `Taskfile.yml`, `apps/akkoma/argocd/appset.yaml`, `apps/soju/kargo/stages.yaml`, and `docs/superpowers/plans/2026-08-05-*.md`. Verified pre-existing by cloning pristine `main` and re-running -- the epic introduces **zero** new gate findings and in fact the branch has one *fewer* block than main. Cannot be fixed under a 0-file diff budget. Raised as a DISCOVERED_BUG for Sr PM triage.

**Finding 3 -- ENVIRONMENTAL, my own doing, not a code defect.**

My first attempt deployed the full stack to **both** clusters simultaneously. The Docker VM has 7.75 GiB total; the two stacks pushed it to ~7.03 GiB at 250-365% CPU, which produced OOMKills (grafana, prometheus), assorted exit-1/exit-2 container restarts, `TLS handshake timeout` from both API servers, and a spurious sync failure (`Job/kube-prometheus-stack-admission-create is missing`). **Serializing the two deployments made all of it disappear** -- the identical config then synced `Succeeded -- all tasks run` with zero restarts. Recording it because the transient `admission-create` failure looks exactly like a real chart bug and is not one; the lesson is that this fleet's clusters fit **one** kube-prometheus-stack at a time on a 7.75 GiB host.

---

### CLEANUP -- baseline fully restored on both clusters

Decision on the Gateway fix: **reverted to `from: Same` on both clusters.** The story left this to my judgement. I reverted because the fix is not yet in `main`, and leaving live state ahead of git means the next agent's baseline check (AF-j4fp's PM review did exactly such a check and asserted `Same`) would silently read as drift. The merge re-applies it idempotently and my faithfulness diff above proves the merged values land on precisely the state I removed, so reverting costs nothing and keeps "live == main" true.

I also found and removed cleanup residue the cascade delete left behind: **10 cluster-scoped `monitoring.coreos.com` CRDs per cluster** (Argo's cascade removes namespaced resources, and the `monitoring` namespace itself is created by `CreateNamespace=true` and is not a tracked resource, so neither was pruned). Confirmed zero CRs of those types existed anywhere before deleting the CRDs.

```
FINAL BASELINE            demo1        demo2
  monitoring.coreos.com CRDs  0            0
  monitoring namespace        NotFound     NotFound
  gateway web listener        Same         Same
  httproutes anywhere         0            0
  temporary Applications      0 remaining
  fleet Applications          total=26  Synced+Healthy=26
```

`pvg verify infrastructure docs --format text` => `VERIFY: PASSED (0 files scanned, 0 issues)`, exit 0.

---

### DISCOVERED_BUG

```
DISCOVERED_BUG:
  title: Grafana HTTPRoute leaves kube-prometheus-stack Application permanently OutOfSync
  context: Gateway API server-side defaulting adds parentRefs.group/kind,
    backendRefs.group/kind/weight, and rules.matches to the live HTTPRoute; these are
    absent from infrastructure/kube-prometheus-stack/secrets/grafana-httproute.yaml, so
    Argo's server-side sync status reports OutOfSync forever while Health stays Healthy.
    Reproduced deterministically on demo1 and demo2. Aggravating factor: `argocd app diff`
    returns empty (client-side normalization), so the drift is invisible to normal triage.
    No selfHeal loop observed. Fix belongs to the HTTPRoute's owning story, not the capstone.
  affected_files: infrastructure/kube-prometheus-stack/secrets/grafana-httproute.yaml,
    infrastructure/kube-prometheus-stack/argocd/appset.yaml
  discovered_during: AF-7u8n
  responsible_upstream_story: AF-j4fp

DISCOVERED_BUG:
  title: pvg gates fails repo-wide on pre-existing duplication debt
  context: `pvg gates` returns FAIL (14 block) on this branch and FAIL (15 block) on a
    pristine origin/main clone -- identical findings, so it predates this epic entirely.
    Scoped runs pass (--changed origin/main => PASS; --changed epic => PASS), confirming
    the epic adds no new findings. Blocks any future story that runs unscoped `pvg gates`.
  affected_files: Taskfile.yml, apps/akkoma/argocd/appset.yaml, apps/soju/kargo/stages.yaml,
    docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
  discovered_during: AF-7u8n
  responsible_upstream_story: none (pre-existing repo debt)
```

---

## LEARNINGS

- **"Healthy" and "Synced" fail independently, and the capstone is where that surfaces.** Every upstream story verified its own artifact and passed; the stack genuinely works end-to-end. What only appears when you apply the real manifest to a real cluster and then *watch the Application status* is that one resource never converges. Render-time verification cannot see server-side defaulting by construction -- AF-j4fp's `helm template` proof was correct and still missed this, the same way its own LEARNINGS noted `helm template` missed the `from: Same` default. That is the same trap twice in one epic, on the same object: **client-side rendering is blind to API-server defaulting, and the only cure is applying it and reading back the live object.**
- **`argocd app diff` disagreeing with `.status.sync.status` is a real, misleading failure mode.** Empty diff, exit 0, app OutOfSync, survives `--hard-refresh`. I nearly wrote it off as stale status. Comparing the live object field-by-field against the git manifest is what actually found it. Do not trust `app diff` alone to clear a sync discrepancy.
- **Capacity is part of the test environment, and getting it wrong manufactures fake bugs.** Deploying to both clusters in parallel produced OOMKills, API timeouts, and a `Job ... is missing` sync failure that reads exactly like a chart defect. Serializing made all of it vanish. Two kube-prometheus-stacks do not fit on a 7.75 GiB Docker VM. Any future fleet-wide verification here should run cluster-by-cluster and check `docker stats` before blaming the manifest.
- **Prove the substitution before you take a shortcut.** I could not apply the Gateway fix the "real" way (the appset is git-managed by an app I must not touch), so I patched the object -- but only after `helm template`-ing the committed values and diffing the patched live listener against that render to show they were identical. That turns "I hand-patched something roughly equivalent" into a defensible proof, and it is cheap.
- **Cascade delete is not cleanup.** `argocd app delete --cascade` left 10 cluster-scoped CRDs and the `CreateNamespace=true` namespace on each cluster. Prior stories in this epic hit the same thing. A baseline claim should enumerate cluster-scoped leftovers explicitly, not just check that the namespace is gone.
- **Repo gotcha (third story to hit it):** the pvg guard blocks `cd` into the worktree, so the standard "prefix every command with `cd <worktree>`" instruction is unusable here -- everything must run via absolute paths and `git -C`. Also, zsh: `UID` is a reserved integer variable, so `UID=$(...)` on a string dies with `bad math expression`; use another name.
