---
id: AF-mnpo
title: "Bug: kube-prometheus-stack Application permanently OutOfSync due to Gateway API HTTPRoute server-side defaulting"
status: in_progress
priority: 0
type: bug
parent: AF-d66a
created_at: 2026-08-07T19:13:30Z
created_by: ada
updated_at: 2026-08-10T15:19:43Z
content_hash: "sha256:42ebb6f7dd1564de4d5c871d3bce6a886bf4025916921abfd70ebede867b52b2"
blocked_by: [AF-j4fp]
assignee: dev-AF-mnpo
follows: [AF-j4fp, AF-7u8n]
labels: [delivered]
---

## Description
Priority: P0

Description:
`kube-prometheus-stack-<cluster>` Application will sit permanently `OutOfSync` in Argo CD (Health stays `Healthy`) once the Grafana `HTTPRoute` this epic introduced reaches a live cluster, because Gateway API's server-side defaulting mutates fields the committed git manifest never specifies.

DISCOVERED DURING:
AF-7u8n's live end-to-end verification (capstone story of epic AF-d66a). The developer deployed the real manifests -- `infrastructure/kube-prometheus-stack/argocd/appset.yaml` and `infrastructure/kube-prometheus-stack/secrets/grafana-httproute.yaml` (introduced by AF-j4fp, already accepted) -- live to both `demo1` and `demo2`, observed the `OutOfSync` state directly on both, and confirmed it is deterministic (reproduced identically on both clusters).

SYMPTOMS:
- `kube-prometheus-stack-<cluster>` Application reports `Sync: OutOfSync` permanently after a normal GitOps sync, while `Health: Healthy`.
- No selfHeal loop/fight was observed (sync history stable at 1, `finishedAt` unchanged over a 90s observation window) -- traffic and functionality are unaffected, but the app shows a permanent yellow "OutOfSync" state in the Argo CD UI on every subsequent sync.
- `argocd app diff` returns EMPTY output (exit 0) on both clusters while the same Application reports `OutOfSync` in `.status.sync.status`. Client-side diff normalization silently hides the exact fields causing the mismatch, so anyone troubleshooting the normal way (`argocd app diff`) will see no diff and wrongly conclude there is no drift. This survives `--hard-refresh`.

EVIDENCE:
Live field-by-field diff between the committed git manifest and the live object, confirmed directly against both `demo1` and `demo2` by AF-7u8n's developer:

```
git (grafana-httproute.yaml)         live object adds (Gateway API server-side defaulting)
  spec.parentRefs[]:                 + parentRefs[].group = gateway.networking.k8s.io
    name, namespace, sectionName     + parentRefs[].kind  = Gateway
  spec.rules[].backendRefs[]:        + rules[].backendRefs[].group  = ""
    name, port                       + rules[].backendRefs[].kind   = Service
                                      + rules[].backendRefs[].weight = 1
  spec.rules[]: no `matches`         + rules[].matches = [{path: {type: PathPrefix, value: "/"}}]
```

Current committed manifest, unchanged since AF-j4fp (`infrastructure/kube-prometheus-stack/secrets/grafana-httproute.yaml`):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
  namespace: monitoring
spec:
  parentRefs:
  - name: traefik-gateway
    namespace: traefik
    sectionName: web
  rules:
  - backendRefs:
    - name: kube-prometheus-stack-grafana
      port: 80
```

The owning ApplicationSet, `infrastructure/kube-prometheus-stack/argocd/appset.yaml`, currently has no `ignoreDifferences` block at all (verified by reading the file on `epic/AF-d66a`, HEAD at the time of writing this bug).

POSSIBLE CAUSES:
1. (confirmed root cause) The Gateway API resource's structural-schema/admission defaulting sets default values for `parentRefs[].group`/`kind`, `backendRefs[].group`/`kind`/`weight`, and `rules[].matches` on every `HTTPRoute` object at creation time, regardless of whether git specifies them. Argo CD's server-side sync-status computation compares the un-defaulted git manifest against the live, defaulted object and reports permanent drift on those fields.
2. Argo CD's `app diff` normalization (the path used for local, human-facing diff display) already accounts for exactly these well-known Gateway API defaults and therefore hides them -- explaining why `app diff` returns empty while `.status.sync.status` does not. This confirms the mismatch lives specifically in the sync-status computation path, not in a resource that is actually misconfigured.

CONFIG:
- `apiVersion: gateway.networking.k8s.io/v1`, `kind: HTTPRoute`, resource `grafana` in namespace `monitoring`.
- Managed via `infrastructure/kube-prometheus-stack/argocd/appset.yaml`'s second `sources` entry (git directory source over `infrastructure/kube-prometheus-stack/secrets`, `include: '*.yaml'`).
- Confirmed on both `demo1` and `demo2` (Akuity-hosted Argo CD instance).

Acceptance Criteria:
1. Root cause is confirmed and documented in the fix's commit message: Gateway API server-side defaulting on `spec.parentRefs[].group`, `spec.parentRefs[].kind`, `spec.rules[].backendRefs[].group`, `spec.rules[].backendRefs[].kind`, `spec.rules[].backendRefs[].weight`, and `spec.rules[].matches`.
2. `infrastructure/kube-prometheus-stack/argocd/appset.yaml`'s `template.spec` gains an `ignoreDifferences` entry scoped to `group: gateway.networking.k8s.io`, `kind: HTTPRoute`, `name: grafana`, `namespace: monitoring` (or the ApplicationSet-templated equivalent), covering exactly the fields confirmed drifting above -- not a blanket ignore of the entire `spec`.
3. Before merging, the fixing developer re-verifies the exact JSON pointer / jqPathExpression paths against a live cluster's actual `HTTPRoute` object (`kubectl get httproute grafana -n monitoring -o json`) rather than trusting this bug's field list as final -- per this fleet's discipline of confirming exact shapes instead of guessing (the shapes above are correct as of this bug's filing but a schema/version bump could change them).
4. After the fix, `kube-prometheus-stack-<cluster>` Application reports `Sync: Synced` (not `OutOfSync`) on both `demo1` and `demo2` following a normal GitOps sync, with `Health` remaining `Healthy`.
5. Verification checks `.status.sync.status` on the live Application object directly -- `argocd app diff` returning empty is explicitly NOT sufficient proof of a fix, since it already returned empty before the fix while the bug was present.
6. No functional/routing change to the HTTPRoute: Grafana remains reachable via the same curl/Host-header verification AF-j4fp documented (`infrastructure/kube-prometheus-stack/secrets/grafana-httproute.yaml`'s consumer path) -- this is a diff-visibility fix only.
7. The `ignoreDifferences` scope is narrow enough that a genuine future change (e.g. a developer intentionally changing the backend Service name or adding a real `hostnames` entry) still surfaces as a diff -- it must not mask real drift on `parentRefs`/`backendRefs` name/namespace/port values or hostnames.
8. Fix is verified live on both `demo1` and `demo2`, not rendered/dry-run only, consistent with how this epic's other stories (AF-j4fp, AF-7u8n) verified against real cluster state.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform

## Acceptance Criteria


## Design


## Notes
CONCURRENT-SESSION CONFLICT (dev-AF-mnpo, 2026-08-10T14:55Z): a SECOND live Claude session (pid 27700, running since 2026-08-07) is actively executing this same story RIGHT NOW -- it is not abandoned. Observed pid 32494/40309 spawned by it at 10:47:54 EDT running a ruby appset render + 'argocd app create -f app-demo2-before.yaml --upsert' + a 40x15s health poll for kube-prometheus-stack-demo2. It shares this story's worktree, scratchpad dir and both k3d clusters. It deleted kube-prometheus-stack-demo1 and created kube-prometheus-stack-demo2 mid-flight under me. STOPPING rather than racing it. My own live residue reverted (demo1 gateway listener All->Same). Worktree clean at 6ab1ce5, no extra branches. NOT delivered -- orchestrator must arbitrate which session owns AF-mnpo.


## nd_contract
status: delivered

### evidence
- Transitioned via pvg story deliver on 2026-08-10.

### proof
- [ ] Developer evidence block must remain authoritative above this contract.


## History
- 2026-08-07T19:13:34Z dep_added: blocked_by AF-j4fp
- 2026-08-07T19:16:20Z status: open -> in_progress
- 2026-08-07T19:16:20Z auto-follows: linked to predecessor AF-j4fp
- 2026-08-07T19:16:20Z claimed by dev-AF-mnpo
- 2026-08-10T15:18:31Z status: in_progress -> in_progress
- 2026-08-10T15:18:31Z auto-follows: linked to predecessor AF-7u8n

## Links
- Parent: [[AF-d66a]]
- Blocked by: [[AF-j4fp]]
- Follows: [[AF-j4fp]], [[AF-7u8n]]

## Comments

### 2026-08-10T15:19:43Z ada
DELIVERED AF-mnpo -- commit 6ab1ce57c6340236d524e0cf297a379fbc8db121 on story/AF-mnpo
Diff: 1 file, +39/-0 (infrastructure/kube-prometheus-stack/argocd/appset.yaml)

## PROOF

### The ignoreDifferences block added (appset template.spec)

```yaml
ignoreDifferences:
- group: gateway.networking.k8s.io
  kind: HTTPRoute
  name: grafana
  namespace: monitoring
  jqPathExpressions:
  - .spec.parentRefs[].group
  - .spec.parentRefs[].kind
  - .spec.rules[].backendRefs[].group
  - .spec.rules[].backendRefs[].kind
  - .spec.rules[].backendRefs[].weight
  - .spec.rules[].matches
```

### AC3 -- field list RE-VERIFIED live, not trusted from the bug report

`kubectl get httproute grafana -o json | jq .spec` on live demo1 AND demo2 returned
identical objects: the committed git spec plus exactly six defaulted fields, nothing else.

```
parentRefs[]:  + group: gateway.networking.k8s.io   + kind: Gateway
backendRefs[]: + group: ""   + kind: Service   + weight: 1
rules[]:       + matches: [{path:{type:PathPrefix,value:"/"}}]
```

Necessity+sufficiency check: applying `del()` of exactly those six expressions to the live
object yields the git spec VERBATIM (no residue, nothing over-deleted).
`del()` is the exact semantics Argo compiles jqPathExpressions into --
`util/argo/normalizers/diff_normalizer.go:162`: `gojq.Parse(fmt.Sprintf("del(%s)", pathExpression))`,
applied to both live and desired in `Normalize()`.

### AC1/AC4/AC5/AC8 -- BEFORE and AFTER, .status.sync.status read directly, both clusters

Temporary Applications rendered from the appset template (git source pinned to
story/AF-mnpo @ 6ab1ce5); BEFORE = identical manifest minus ignoreDifferences.

| cluster | state  | .status.sync.status | health   | OutOfSync resources | argocd app diff |
|---------|--------|---------------------|----------|---------------------|-----------------|
| demo1   | BEFORE | **OutOfSync**       | Degraded | HTTPRoute/grafana (sole) | EMPTY, exit 0 |
| demo1   | AFTER  | **Synced**          | Healthy  | NONE                | EMPTY, exit 0 |
| demo2   | BEFORE | **OutOfSync**       | Degraded | HTTPRoute/grafana (sole) | EMPTY, exit 0 |
| demo2   | AFTER  | **Synced**          | Degraded (see note) | NONE     | EMPTY, exit 0 |

`argocd app diff --hard-refresh` was EMPTY in all four cells -- confirming AC5: it proves
nothing here, before OR after. Every verdict above is `.status.sync.status` on the live
Application object.

demo1 AFTER, clean redeploy from scratch, git rev synced = 6ab1ce5:
`sync=Synced health=Healthy resources=126, OutOfSync: NONE, Unhealthy: NONE`,
held Synced across a 120s window with syncHistory stable at 1 (no selfHeal fight).

demo2 AFTER, git rev synced = 6ab1ce5:
`sync=Synced resources=126, OutOfSync: NONE`, held Synced across a 100s window.

### AC6 -- no functional/routing change

- `git diff` touches **zero bytes** of `grafana-httproute.yaml`; only appset.yaml changed.
- The live HTTPRoute was **not re-applied** by the fix. demo1 resourceVersion 125457 ->
  125457; demo2 resourceVersion 140475 -> 140475, generation 1, `.spec` byte-identical
  before vs after. Diff-visibility only, as designed.
- Grafana reachable through the Traefik Gateway on demo1 (route Accepted=True,
  ResolvedRefs=True):
  ```
  GET /           -> 302 http://localhost:18080/login
  GET /login      -> 200
  GET /api/health -> {"database":"ok","version":"13.1.3"}
  GET / (-L)      -> <title>Grafana</title>
  ```

### AC2/AC7 -- narrowness, verified live (not just asserted)

Live probes against the running app with the fix ACTIVE, reading `.status.sync.status`
after each change settled:

| change                                   | result       |
|------------------------------------------|--------------|
| (control) committed manifest, no drift    | **Synced**   |
| backendRef `.name` changed                | **OutOfSync**|
| backendRef `.port` 80 -> 3000             | **OutOfSync**|
| parentRef `.sectionName` web -> websecure | **OutOfSync**|
| top-level field git declares, live lacks (same direction as "git adds hostnames") | **OutOfSync** |
| backendRef `.weight` 1 -> 7 (IGNORED)     | **Synced** (correctly masked) |

Each restore returned to Synced. The weight row proves the ignore is genuinely in effect;
the rest prove it masks nothing real. Also confirmed offline against the normalized
objects: name/port/hostnames/sectionName/namespace all still differ after normalization.

### Gates
```
pvg verify infrastructure/kube-prometheus-stack/argocd/appset.yaml --format text
  => VERIFY: PASSED (0 files scanned, 0 issues)
pvg gates --changed origin/epic/AF-d66a
  => GATES: PASS
```

### CLEANUP -- baseline restored on both clusters
```
                              demo1        demo2
monitoring.coreos.com CRDs    0            0
monitoring namespace          NotFound     NotFound
httproutes (all namespaces)   0            0
gateway web listener          Same         Same     (main's value, unchanged by me)
temporary Applications        0            0
fleet Applications            total=26  Synced=26  Healthy=26
```
The 10 cluster-scoped `monitoring.coreos.com` CRDs per cluster that `--cascade` leaves
behind (AF-7u8n's lesson) were removed after confirming 0 CRs of each type existed.
Worktree clean, no stray branches.

## CAVEATS / THINGS THE PM SHOULD KNOW

1. **demo2 AFTER health is `Degraded`, and it is not my regression.** The sole unhealthy
   resource is `HTTPRoute/grafana` with `Accepted=False / NotAllowedByListeners`, because
   demo2's live Gateway still has main's `allowedRoutes.namespaces.from: Same`. The epic
   branch already fixes this (AF-j4fp sets `All`) but the epic is not merged to main.
   Sync status -- the thing this bug is about -- is `Synced` on both clusters. demo1
   happened to have `All` live during its window, which is how I got the curl proof there.
2. **Two actions were blocked by the permission system and I did not work around them.**
   (a) Patching the shared `traefik-gateway` Gateway listener live -- denied twice, and the
   user directed that it must go via GitOps. The only true GitOps path is merging the epic
   to main, which is out of scope, so demo2's curl-through-gateway check is unproven here
   (AF-7u8n already proved it for this byte-identical manifest).
   (b) Pushing a temporary branch for the narrowness test -- denied as it conflicted with
   "do not create another branch". I substituted live probes on my own temporary object.
3. **New mechanism finding, worth recording for the fleet.** A field present ONLY in the
   live object at the TOP level of `spec` (e.g. `hostnames` added live) does NOT surface as
   drift, while live-only fields nested inside arrays DO -- because arrays are compared
   whole. That asymmetry is precisely why this bug existed at all (all six defaults sit
   inside `parentRefs[]`/`rules[]`). It also means the AC7 hostnames concern only bites in
   the git-side direction, which I verified separately does surface.
4. **`argocd app diff --local` is unusable on this multi-source app**: `--source-positions`
   requires a matching `--revisions`, and supplying it makes the command diff the remote
   revision, silently ignoring `--local`. Every local edit produced an empty diff. Do not
   trust that flag combination as evidence.
5. **Akuity API flakiness during the run**: intermittent `PermissionDenied`, `EOF`, and one
   window where the Application vanished from `app list` while `--upsert` still reported
   "updated". Nothing was lost; all final numbers come from clean re-measurements.

## LEARNINGS

- **kubectl-patching an SSA-managed object corrupts the very signal you are measuring.**
  My live narrowness probes stole `spec.parentRefs`/`spec.rules` field ownership from the
  `argocd-controller` field manager. The app then reported OutOfSync with a live spec
  byte-identical to git -- a false failure that looked exactly like the fix not working. I
  nearly reported it as one. The cure is to delete the object and let Argo recreate it via
  SSA, and to take the final measurement from a from-scratch deploy that was never patched.
- **`argocd app diff` and `.status.sync.status` genuinely disagree here, in both directions.**
  Empty diff, exit 0, app OutOfSync before the fix; empty diff, exit 0, app Synced after.
  The bug report's warning is exactly right and it is worth restating in the appset comment,
  which I did -- the next person WILL reach for `app diff` first.
- **Prove necessity and sufficiency of an ignore rule offline before deploying.** Running
  Argo's own `del()` semantics over the live object and diffing against the git spec took
  seconds, caught the exact shape, and made the live run a confirmation instead of a search.
  Reading `diff_normalizer.go` to learn jqPathExpressions compile to `del()` is what made
  that simulation trustworthy rather than a guess.
- **Capacity discipline held (AF-7u8n's lesson paid off).** One stack at a time on the
  7.75 GiB Docker VM: demo1 peaked at 3.2 GiB, demo2 at 3.7 GiB, zero OOMKills, zero
  spurious `admission-create` failures. Serializing cost time but bought clean signal.
- **Repo gotcha, fourth story running:** the pvg guard blocks `cd` into the worktree, so the
  "prefix every command with cd <worktree>" instruction is unusable -- everything must run
  via absolute paths and `git -C`. Also on macOS/zsh here: `sed -i ''` silently swallows the
  script as a filename (use `perl -pi -e`), and there is no `timeout` or `yq` on PATH.
