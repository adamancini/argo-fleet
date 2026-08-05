---
id: AF-vwvq
title: "Add traefik-gateway infrastructure layer for demo1/demo2"
status: closed
priority: 1
type: task
parent: AF-q1il
created_at: 2026-08-05T14:31:38Z
created_by: ada
updated_at: 2026-08-05T16:08:14Z
content_hash: "sha256:c21fda057ae04db37b26b8a14483c7d2a4bca194631fd9589d2d9d5bf7ec4b34"
assignee: dev-AF-vwvq
labels: [accepted]
closed_at: 2026-08-05T16:08:13Z
close_reason: "Accepted via pvg story accept"
---

## Description
Description:
Add `infrastructure/traefik-gateway/` -- an Argo CD ApplicationSet that
installs Traefik on every cluster, configured as a Gateway API controller
(not classic Ingress-only), giving `demo1`/`demo2` an explicit,
GitOps-managed ingress path instead of k3s's invisible bundled Traefik.

Context:
Same repo pattern as AF-8ik8 (`infrastructure/sealed-secrets/`'s
`list`-generator shape, verified by reading it directly), using Argo CD's
native Helm-repository source. Traefik's chart, when given the
`gateway.*` values below, creates the `Gateway` object itself -- no
hand-authored `Gateway` YAML anywhere in this repo. Its name is pinned to
`traefik-gateway` explicitly because `fleet-infra`'s existing `HTTPRoute`
resources already reference that exact name via `parentRefs` -- matching
it here means the pattern this repo establishes transfers without
translation when `akkoma`/`soju` eventually move to the real clusters
(wiring their own `HTTPRoute` resources to this Gateway is explicitly out
of scope for this epic -- see the epic's DESIGN REQUIREMENTS).

Classic Ingress support (`providers.kubernetesIngress`) and Traefik's own
CRD provider (`providers.kubernetesCRD`, for `Middleware` etc.) both stay
enabled too -- Gateway API and Ingress aren't mutually exclusive, and
disabling either isn't part of this design.

Only the `web` (plain HTTP) listener is enabled; `websecure` (TLS) stays
off -- no cert-manager, no real domains yet (explicitly deferred, see the
epic body). `service.type: LoadBalancer` with no fixed `loadBalancerIP` --
unlike `fleet-infra`'s real hardware LB with a reserved IP, k3d's
`servicelb` (which stays enabled in AF-4wcm's `cluster:create`/
`cluster:recreate` -- it is NOT one of the two things disabled at
cluster-creation time) assigns an IP dynamically on the docker network.

USER INTENT:
Anyone reading this repo's `infrastructure/` directory needs the ingress
path to be an explicit, version-controlled decision with a stable,
predictable Gateway name -- so that when a real app's `HTTPRoute` is
eventually written (a follow-up, not this story), it can reference
`traefik-gateway` with confidence that name will still be correct, exactly
as `fleet-infra` already relies on it being. Once synced, this
ApplicationSet emits one Application per cluster, and Traefik routes any
HTTP request matching a future `HTTPRoute`'s rules to the backend Service
it names -- the mechanism a user can build on once real domains exist.

IMPLEMENTATION:
Create `infrastructure/traefik-gateway/argocd/appset.yaml`:
```yaml
# One Application per cluster, installing Traefik configured as a Gateway
# API controller (not classic Ingress-only) -- mirrors fleet-infra's
# real-cluster setup, including the exact Gateway name ("traefik-gateway")
# its HTTPRoute resources already reference via parentRefs.
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: traefik-gateway
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: demo1
      - cluster: demo2
  template:
    metadata:
      name: 'traefik-gateway-{{cluster}}'
    spec:
      project: default
      source:
        repoURL: https://traefik.github.io/charts
        chart: traefik
        targetRevision: 41.1.1
        helm:
          valuesObject:
            ingressClass:
              enabled: true
              isDefaultClass: true
            providers:
              kubernetesCRD:
                enabled: true
              kubernetesIngress:
                enabled: true
              kubernetesGateway:
                enabled: true
                experimentalChannel: true
            gateway:
              enabled: true
              name: traefik-gateway
            service:
              enabled: true
              type: LoadBalancer
      destination:
        name: '{{cluster}}'
        namespace: traefik
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

Create `infrastructure/traefik-gateway/README.md`:
```markdown
# traefik-gateway — cluster-wide dependency, no promotion pipeline

Installs [Traefik](https://traefik.io/) on every cluster in
`argocd/appset.yaml`'s `list` generator (`demo1`, `demo2`), configured as a
**Gateway API** controller -- not classic Ingress-only -- mirroring
[fleet-infra](https://github.com/adamancini/fleet-infra)'s real-cluster
setup. Classic Ingress support (`providers.kubernetesIngress`) and
Traefik's own CRD provider (`providers.kubernetesCRD`, for `Middleware`
etc.) both stay enabled too -- Gateway API and Ingress aren't mutually
exclusive.

The chart creates the `Gateway` object itself from the `gateway.*` values --
no hand-authored `Gateway` YAML in this repo. Its name is pinned to
`traefik-gateway` explicitly, matching the exact name `fleet-infra`'s
`HTTPRoute` resources already reference via `parentRefs`, so a future
app's `HTTPRoute` here can use the identical reference shape.

## What's NOT enabled yet

- The `websecure` (TLS) listener -- stays off. No cert-manager, no real
  domains yet (see the design spec in `docs/superpowers/`).
- Any actual `HTTPRoute` for `akkoma`/`soju` -- they still use placeholder
  domains and `ingress.enabled: false`. Wiring them to this Gateway is a
  follow-up once real domains exist, not part of this layer.

## Prerequisite

Same as `openebs-localpv`: k3s's own bundled Traefik must be gone first
(`task cluster:recreate` disables it via
`--k3s-arg "--disable=traefik@server:0"`), or this Application's
`IngressClass`/`Gateway` objects collide with k3s's own.
```

Validation (static only -- no cluster is touched by this story):
`ruby -ryaml -e "YAML.load_stream(File.read('infrastructure/traefik-gateway/argocd/appset.yaml'))" && echo OK`
-- expect `OK`.

KEY FILES:
- Create: infrastructure/traefik-gateway/argocd/appset.yaml
- Create: infrastructure/traefik-gateway/README.md

PRODUCES:
- infrastructure/traefik-gateway/argocd/appset.yaml -> ApplicationSet
  `traefik-gateway` (namespace `argocd`), `list` generator with elements
  `demo1`/`demo2`, templating Applications named
  `traefik-gateway-{{cluster}}` that install chart `traefik` 41.1.1 from
  `https://traefik.github.io/charts` into namespace `traefik` on each
  cluster, creating a `Gateway` object named exactly `traefik-gateway` (a
  future app's `HTTPRoute` references it via
  `parentRefs: [{name: traefik-gateway, namespace: traefik}]` -- not
  consumed by any story in this epic; wiring is explicitly deferred).
  source: docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
  Task 4 (verbatim); discovered automatically by the existing
  `bootstrap/infra-apps.yaml` git-directory generator (verified by reading
  that file directly -- no change needed there).

TESTING:
Static validation only (YAML syntax). No cluster is touched. The two
Prerequisite/ordering notes in the README (k3s Traefik must be gone;
CRD-before-Gateway-object ordering, handled by AF-qujb's
`gateway-api-crds` sync-wave) are exercised for real only in the epic's
human-gated release-gate story, not in this story.

CONSUMES:
None as a hard dependency -- this story is not `blocked_by` AF-qujb
because Argo CD's `selfHeal` resolves the ordering automatically at sync
time (see the sync-wave note above), so the two stories may be authored
and merged in either order. The runtime relationship (CRDs must exist
before this chart's `Gateway` object reconciles) is documented here and in
AF-qujb's PRODUCES block for traceability, not enforced as a backlog
dependency edge.

Acceptance Criteria:
1. [Ubiquitous] `infrastructure/traefik-gateway/argocd/appset.yaml` exists
   with content matching IMPLEMENTATION exactly, including chart version
   `41.1.1`, repo URL `https://traefik.github.io/charts`, `gateway.name:
   traefik-gateway`, `providers.kubernetesGateway.experimentalChannel:
   true`, `providers.kubernetesIngress.enabled: true`,
   `providers.kubernetesCRD.enabled: true`.
2. [Ubiquitous] `infrastructure/traefik-gateway/README.md` exists and
   documents both the k3s-Traefik-must-be-gone-first prerequisite and the
   "websecure stays off" deferred-scope note.
3. [Event] `ruby -ryaml -e "YAML.load_stream(...)"` against the appset.yaml
   exits with `OK` and no YAML parse error.
4. [Ubiquitous] `gateway.name` is the literal string `traefik-gateway` --
   not a template variable, not a per-cluster suffix -- matching
   `fleet-infra`'s existing `HTTPRoute` `parentRefs` exactly.
5. [Unwanted] The `websecure` (TLS) listener shall not be enabled anywhere
   in this story's values -- only the `web` (HTTP) listener is configured.
6. [Unwanted] This story shall not sync, apply, or otherwise mutate any
   live Argo CD instance or k3d cluster -- verification is limited to
   static YAML parsing.

MANDATORY SKILLS TO REVIEW:
`devops-toolkit:yaml-kubernetes-validator` -- this story authors an Argo CD
ApplicationSet manifest; load the skill and apply its YAML/Kubernetes
manifest review guidance before finalizing.

# One Application per cluster, installing Traefik configured as a Gateway
# API controller (not classic Ingress-only) -- mirrors fleet-infra's
# real-cluster setup, including the exact Gateway name ("traefik-gateway")
# its HTTPRoute resources already reference via parentRefs.
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: traefik-gateway
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: demo1
      - cluster: demo2
  template:
    metadata:
      name: 'traefik-gateway-{{cluster}}'
    spec:
      project: default
      source:
        repoURL: https://traefik.github.io/charts
        chart: traefik
        targetRevision: 41.1.1
        helm:
          valuesObject:
            ingressClass:
              enabled: true
              isDefaultClass: true
            providers:
              kubernetesCRD:
                enabled: true
              kubernetesIngress:
                enabled: true
              kubernetesGateway:
                enabled: true
                experimentalChannel: true
            gateway:
              enabled: true
              name: traefik-gateway
            service:
              enabled: true
              type: LoadBalancer
      destination:
        name: '{{cluster}}'
        namespace: traefik
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

Create `infrastructure/traefik-gateway/README.md`:
```markdown
# traefik-gateway — cluster-wide dependency, no promotion pipeline

Installs [Traefik](https://traefik.io/) on every cluster in
`argocd/appset.yaml`'s `list` generator (`demo1`, `demo2`), configured as a
**Gateway API** controller -- not classic Ingress-only -- mirroring
[fleet-infra](https://github.com/adamancini/fleet-infra)'s real-cluster
setup. Classic Ingress support (`providers.kubernetesIngress`) and
Traefik's own CRD provider (`providers.kubernetesCRD`, for `Middleware`
etc.) both stay enabled too -- Gateway API and Ingress aren't mutually
exclusive.

The chart creates the `Gateway` object itself from the `gateway.*` values --
no hand-authored `Gateway` YAML in this repo. Its name is pinned to
`traefik-gateway` explicitly, matching the exact name `fleet-infra`'s
`HTTPRoute` resources already reference via `parentRefs`, so a future
app's `HTTPRoute` here can use the identical reference shape.

## What's NOT enabled yet

- The `websecure` (TLS) listener -- stays off. No cert-manager, no real
  domains yet (see the design spec in `docs/superpowers/`).
- Any actual `HTTPRoute` for `akkoma`/`soju` -- they still use placeholder
  domains and `ingress.enabled: false`. Wiring them to this Gateway is a
  follow-up once real domains exist, not part of this layer.

## Prerequisite

Same as `openebs-localpv`: k3s's own bundled Traefik must be gone first
(`task cluster:recreate` disables it via
`--k3s-arg "--disable=traefik@server:0"`), or this Application's
`IngressClass`/`Gateway` objects collide with k3s's own.
```

Validation (static only -- no cluster is touched by this story):
`ruby -ryaml -e "YAML.load_stream(File.read('infrastructure/traefik-gateway/argocd/appset.yaml'))" && echo OK`
-- expect `OK`.

KEY FILES:
- Create: infrastructure/traefik-gateway/argocd/appset.yaml
- Create: infrastructure/traefik-gateway/README.md

PRODUCES:
- infrastructure/traefik-gateway/argocd/appset.yaml -> ApplicationSet
  `traefik-gateway` (namespace `argocd`), `list` generator with elements
  `demo1`/`demo2`, templating Applications named
  `traefik-gateway-{{cluster}}` that install chart `traefik` 41.1.1 from
  `https://traefik.github.io/charts` into namespace `traefik` on each
  cluster, creating a `Gateway` object named exactly `traefik-gateway` (a
  future app's `HTTPRoute` references it via
  `parentRefs: [{name: traefik-gateway, namespace: traefik}]` -- not
  consumed by any story in this epic; wiring is explicitly deferred).
  source: docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
  Task 4 (verbatim); discovered automatically by the existing
  `bootstrap/infra-apps.yaml` git-directory generator (verified by reading
  that file directly -- no change needed there).

TESTING:
Static validation only (YAML syntax). No cluster is touched. The two
Prerequisite/ordering notes in the README (k3s Traefik must be gone;
CRD-before-Gateway-object ordering, handled by AF-qujb's
`gateway-api-crds` sync-wave) are exercised for real only in the epic's
human-gated release-gate story, not in this story.

CONSUMES:
None as a hard dependency -- this story is not `blocked_by` AF-qujb
because Argo CD's `selfHeal` resolves the ordering automatically at sync
time (see the sync-wave note above), so the two stories may be authored
and merged in either order. The runtime relationship (CRDs must exist
before this chart's `Gateway` object reconciles) is documented here and in
AF-qujb's PRODUCES block for traceability, not enforced as a backlog
dependency edge.

Acceptance Criteria:
1. [Ubiquitous] `infrastructure/traefik-gateway/argocd/appset.yaml` exists
   with content matching IMPLEMENTATION exactly, including chart version
   `41.1.1`, repo URL `https://traefik.github.io/charts`, `gateway.name:
   traefik-gateway`, `providers.kubernetesGateway.experimentalChannel:
   true`, `providers.kubernetesIngress.enabled: true`,
   `providers.kubernetesCRD.enabled: true`.
2. [Ubiquitous] `infrastructure/traefik-gateway/README.md` exists and
   documents both the k3s-Traefik-must-be-gone-first prerequisite and the
   "websecure stays off" deferred-scope note.
3. [Event] `ruby -ryaml -e "YAML.load_stream(...)"` against the appset.yaml
   exits with `OK` and no YAML parse error.
4. [Ubiquitous] `gateway.name` is the literal string `traefik-gateway` --
   not a template variable, not a per-cluster suffix -- matching
   `fleet-infra`'s existing `HTTPRoute` `parentRefs` exactly.
5. [Unwanted] The `websecure` (TLS) listener shall not be enabled anywhere
   in this story's values -- only the `web` (HTTP) listener is configured.
6. [Unwanted] This story shall not sync, apply, or otherwise mutate any
   live Argo CD instance or k3d cluster -- verification is limited to
   static YAML parsing.

MANDATORY SKILLS TO REVIEW:
`devops-toolkit:yaml-kubernetes-validator` -- this story authors an Argo CD
ApplicationSet manifest; load the skill and apply its YAML/Kubernetes
manifest review guidance before finalizing.

# One Application per cluster, installing Traefik configured as a Gateway
# API controller (not classic Ingress-only) -- mirrors fleet-infra's
# real-cluster setup, including the exact Gateway name ("traefik-gateway")
# its HTTPRoute resources already reference via parentRefs.
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: traefik-gateway
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: demo1
      - cluster: demo2
  template:
    metadata:
      name: 'traefik-gateway-{{cluster}}'
    spec:
      project: default
      source:
        repoURL: https://traefik.github.io/charts
        chart: traefik
        targetRevision: 41.1.1
        helm:
          valuesObject:
            ingressClass:
              enabled: true
              isDefaultClass: true
            providers:
              kubernetesCRD:
                enabled: true
              kubernetesIngress:
                enabled: true
              kubernetesGateway:
                enabled: true
                experimentalChannel: true
            gateway:
              enabled: true
              name: traefik-gateway
            service:
              enabled: true
              type: LoadBalancer
      destination:
        name: '{{cluster}}'
        namespace: traefik
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

Create `infrastructure/traefik-gateway/README.md`:
```markdown
# traefik-gateway — cluster-wide dependency, no promotion pipeline

Installs [Traefik](https://traefik.io/) on every cluster in
`argocd/appset.yaml`'s `list` generator (`demo1`, `demo2`), configured as a
**Gateway API** controller -- not classic Ingress-only -- mirroring
[fleet-infra](https://github.com/adamancini/fleet-infra)'s real-cluster
setup. Classic Ingress support (`providers.kubernetesIngress`) and
Traefik's own CRD provider (`providers.kubernetesCRD`, for `Middleware`
etc.) both stay enabled too -- Gateway API and Ingress aren't mutually
exclusive.

The chart creates the `Gateway` object itself from the `gateway.*` values --
no hand-authored `Gateway` YAML in this repo. Its name is pinned to
`traefik-gateway` explicitly, matching the exact name `fleet-infra`'s
`HTTPRoute` resources already reference via `parentRefs`, so a future
app's `HTTPRoute` here can use the identical reference shape.

## What's NOT enabled yet

- The `websecure` (TLS) listener -- stays off. No cert-manager, no real
  domains yet (see the design spec in `docs/superpowers/`).
- Any actual `HTTPRoute` for `akkoma`/`soju` -- they still use placeholder
  domains and `ingress.enabled: false`. Wiring them to this Gateway is a
  follow-up once real domains exist, not part of this layer.

## Prerequisite

Same as `openebs-localpv`: k3s's own bundled Traefik must be gone first
(`task cluster:recreate` disables it via
`--k3s-arg "--disable=traefik@server:0"`), or this Application's
`IngressClass`/`Gateway` objects collide with k3s's own.
```

Validation (static only -- no cluster is touched by this story):
`ruby -ryaml -e "YAML.load_stream(File.read('infrastructure/traefik-gateway/argocd/appset.yaml'))" && echo OK`
-- expect `OK`.

KEY FILES:
- Create: infrastructure/traefik-gateway/argocd/appset.yaml
- Create: infrastructure/traefik-gateway/README.md

PRODUCES:
- infrastructure/traefik-gateway/argocd/appset.yaml -> ApplicationSet
  `traefik-gateway` (namespace `argocd`), `list` generator with elements
  `demo1`/`demo2`, templating Applications named
  `traefik-gateway-{{cluster}}` that install chart `traefik` 41.1.1 from
  `https://traefik.github.io/charts` into namespace `traefik` on each
  cluster, creating a `Gateway` object named exactly `traefik-gateway` (a
  future app's `HTTPRoute` references it via
  `parentRefs: [{name: traefik-gateway, namespace: traefik}]` -- not
  consumed by any story in this epic; wiring is explicitly deferred).
  source: docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
  Task 4 (verbatim); discovered automatically by the existing
  `bootstrap/infra-apps.yaml` git-directory generator (verified by reading
  that file directly -- no change needed there).

TESTING:
Static validation only (YAML syntax). No cluster is touched. The two
Prerequisite/ordering notes in the README (k3s Traefik must be gone;
CRD-before-Gateway-object ordering, handled by AF-<gateway-api-crds
story's> sync-wave) are exercised for real only in the epic's human-gated
release-gate story, not in this story.

Acceptance Criteria:
1. [Ubiquitous] `infrastructure/traefik-gateway/argocd/appset.yaml` exists
   with content matching IMPLEMENTATION exactly, including chart version
   `41.1.1`, repo URL `https://traefik.github.io/charts`, `gateway.name:
   traefik-gateway`, `providers.kubernetesGateway.experimentalChannel:
   true`, `providers.kubernetesIngress.enabled: true`,
   `providers.kubernetesCRD.enabled: true`.
2. [Ubiquitous] `infrastructure/traefik-gateway/README.md` exists and
   documents both the k3s-Traefik-must-be-gone-first prerequisite and the
   "websecure stays off" deferred-scope note.
3. [Event] `ruby -ryaml -e "YAML.load_stream(...)"` against the appset.yaml
   exits with `OK` and no YAML parse error.
4. [Ubiquitous] `gateway.name` is the literal string `traefik-gateway` --
   not a template variable, not a per-cluster suffix -- matching
   `fleet-infra`'s existing `HTTPRoute` `parentRefs` exactly.
5. [Unwanted] The `websecure` (TLS) listener shall not be enabled anywhere
   in this story's values -- only the `web` (HTTP) listener is configured.
6. [Unwanted] This story shall not sync, apply, or otherwise mutate any
   live Argo CD instance or k3d cluster -- verification is limited to
   static YAML parsing.

MANDATORY SKILLS TO REVIEW:
`devops-toolkit:yaml-kubernetes-validator` -- this story authors an Argo CD
ApplicationSet manifest; load the skill and apply its YAML/Kubernetes
manifest review guidance before finalizing.

## Acceptance Criteria


## Design


## Notes


## nd_contract
status: accepted

### evidence
- PM closeout applied via pvg story accept on 2026-08-05.

### proof
- [x] Story closed after accepted label was applied.


## nd_contract
status: delivered

### evidence
- Transitioned via pvg story deliver on 2026-08-05.

### proof
- [ ] Developer evidence block must remain authoritative above this contract.


## History
- 2026-08-05T14:33:40Z dep_added: blocks AF-cbot
- 2026-08-05T14:49:15Z status: open -> in_progress
- 2026-08-05T14:49:15Z claimed by dev-AF-vwvq
- 2026-08-05T14:56:24Z status: in_progress -> in_progress
- 2026-08-05T16:08:13Z status: in_progress -> closed
- 2026-08-05T16:08:13Z dep_removed: no_longer_blocks AF-cbot

## Links
- Parent: [[AF-q1il]]

## Comments

### 2026-08-05T14:57:25Z ada
DELIVERED: AF-vwvq -- Add traefik-gateway infrastructure layer for demo1/demo2

Commit SHA: 80a8ff51bd3726529a0eb7b13e894dc1f8e01c06
Branch: story/AF-vwvq (pushed to origin, cbaa106..80a8ff5)
Files: infrastructure/traefik-gateway/argocd/appset.yaml (+52), infrastructure/traefik-gateway/README.md (+31)
Working tree clean at the SHA above -- all results below produced from the committed tree.

PROOF:

1. AC3 -- the story's exact validation command
   $ ruby -ryaml -e "YAML.load_stream(File.read('infrastructure/traefik-gateway/argocd/appset.yaml'))" && echo OK
   OK
   exit=0

2. AC1 -- byte-exact match against the story's IMPLEMENTATION blocks
   Extracted both fenced blocks straight out of `pvg issues show AF-vwvq --json` and diffed:
   $ diff -u spec-appset.yaml infrastructure/traefik-gateway/argocd/appset.yaml   -> IDENTICAL (0 lines of diff)
   $ diff -u spec-readme.md   infrastructure/traefik-gateway/README.md            -> IDENTICAL (0 lines of diff)

3. Structural assertions on the parsed document -- 31/31 PASS, 0 FAIL
   apiVersion=argoproj.io/v1alpha1, kind=ApplicationSet, metadata.name=traefik-gateway,
   metadata.namespace=argocd, generator elements=[{cluster: demo1},{cluster: demo2}],
   template name=traefik-gateway-{{cluster}}, repoURL=https://traefik.github.io/charts,
   chart=traefik, targetRevision="41.1.1" (parses as String, not a float),
   ingressClass.enabled/isDefaultClass=true, providers.kubernetesCRD.enabled=true,
   providers.kubernetesIngress.enabled=true, providers.kubernetesGateway.enabled=true,
   providers.kubernetesGateway.experimentalChannel=true, gateway.enabled=true,
   gateway.name="traefik-gateway", service.enabled=true, service.type=LoadBalancer,
   destination.name={{cluster}}, destination.namespace=traefik,
   syncPolicy prune/selfHeal=true, syncOptions=[CreateNamespace=true].
   Hygiene: no tabs, no trailing whitespace, ends with newline, exactly 1 document.

4. AC4 -- gateway.name is a literal, verified two ways
   Static: value is "traefik-gateway", contains no "{{" template delimiters -> PASS
   Rendered (see 6): the Gateway object's metadata.name is literally "traefik-gateway" -> PASS

5. AC5 -- no websecure TLS listener
   grep -iF websecure over appset.yaml -> 0 hits (PASS)
   Rendered Gateway listeners: web/HTTP:8000 only. No HTTPS-protocol listener,
   no listener named websecure -> PASS
   grep loadBalancerIP -> 0 hits (dynamic k3d servicelb IP, as designed) -> PASS

6. Chart cross-check + static render (no cluster touched -- see AC6)
   $ helm repo update traefik && helm search repo traefik/traefik --versions | head -3
   NAME             CHART VERSION  APP VERSION  DESCRIPTION
   traefik/traefik  41.1.1         v3.7.9       A Traefik based Kubernetes ingress controller
   traefik/traefik  41.1.0         v3.7.9       A Traefik based Kubernetes ingress controller
   -> pinned 41.1.1 exists and is the current latest.

   Every values key was validated against the real chart schema by extracting the
   appset's valuesObject and rendering it locally:
   $ helm template traefik-gateway traefik/traefik --version 41.1.1 -n traefik -f <valuesObject>
   exit=0, 8 documents. (The chart ships values.schema.json with additionalProperties:false
   in these blocks, so a mistyped key would have failed the render -- it did not.)

   Rendered kinds: ClusterRole x1, ClusterRoleBinding x1, Deployment x1, Gateway x1,
                   GatewayClass x1, IngressClass x1, Service x1, ServiceAccount x1
   Gateway:        name="traefik-gateway" ns="traefik" listeners=[web/HTTP:8000]
   GatewayClass:   traefik
   IngressClass:   traefik-gateway (is-default-class=true)
   Service:        type=LoadBalancer, loadBalancerIP unset (nil)
   Traefik container args proving all three providers wired:
     --providers.kubernetescrd
     --providers.kubernetesingress
     --providers.kubernetesgateway
     --providers.kubernetesgateway.experimentalchannel=true

7. Wiring evidence
   bootstrap/infra-apps.yaml's git generator globs `infrastructure/*/argocd` and templates
   `infra-{{path[1]}}`. The new path infrastructure/traefik-gateway/argocd matches that glob,
   so Argo CD emits Application `infra-traefik-gateway` with no change to that file
   (read directly to confirm; file untouched by this commit).

8. Regression -- every YAML in the repo still parses
   25/25 files OK, 0 FAIL (apps/*, bootstrap/*, infrastructure/*, Taskfile.yml).

9. pvg verify
   $ pvg verify infrastructure/traefik-gateway/argocd/appset.yaml infrastructure/traefik-gateway/README.md --format text
   VERIFY: PASSED (0 files scanned, 0 issues)   exit=0
   (0 scanned: the scanner targets source files, not YAML/Markdown.)

10. AC6 -- nothing live was mutated
    Commands run in total: ruby YAML parsing, diff, grep, git, helm repo update/search
    (local repo cache), helm template (local render). No kubectl, no argocd CLI, no k3d,
    no kubeconfig read. Zero contact with any Argo CD instance or cluster.

AC VERIFICATION TABLE
| AC | Requirement | Result | Evidence |
|----|-------------|--------|----------|
| 1 | appset.yaml matches IMPLEMENTATION exactly (41.1.1, repoURL, gateway.name, experimentalChannel, kubernetesIngress, kubernetesCRD) | PASS | Proof 2 (byte-identical diff) + Proof 3 (31/31 field assertions) |
| 2 | README documents k3s-Traefik-first prerequisite AND websecure-stays-off deferred scope | PASS | Proof 2 (byte-identical) + content grep: both sections present, 6/6 markers PASS |
| 3 | ruby YAML.load_stream exits OK, no parse error | PASS | Proof 1 (exit=0, "OK") |
| 4 | gateway.name is literal "traefik-gateway", not templated/suffixed | PASS | Proof 4 (static + rendered Gateway object) |
| 5 | websecure TLS listener not enabled; only web (HTTP) configured | PASS | Proof 5 (0 grep hits; rendered listeners = web/HTTP:8000 only) |
| 6 | No live Argo CD / k3d mutation; static verification only | PASS | Proof 10 (full command inventory) |

Errors/warnings encountered: none. No test failures, no build warnings, no deprecation
notices. No DISCOVERED_BUG to report.

OBSERVATION (not a defect, no AC impact, flagged for the future TLS story):
The rendered LoadBalancer Service publishes both web:80 and websecure:443, because the
chart's own default `ports.websecure.expose.default: true` creates the Traefik *entrypoint*
(:8443) independently of Gateway API. AC5 is scoped to the Gateway *listener*, and the
rendered Gateway has only the web/HTTP listener -- the chart's `gateway.listeners.websecure`
block is commented out by default and this story adds nothing that enables it. So the
delivered state is correct as specified. The practical consequence is that port 443 will be
allocated on the k3d LB but nothing will serve TLS on it until cert-manager and real domains
arrive. Whoever picks up the TLS story should decide then whether to set
`ports.websecure.expose.default: false` in the interim. I did not deviate from the spec.

LEARNINGS:
- `helm template` against the pinned chart version is a cheap, cluster-free way to turn a
  "static YAML syntax check" story into real proof. Traefik's chart ships values.schema.json
  with `additionalProperties: false`, so the render doubles as a typo check on every values
  key -- a misspelled `experimentalChannel` would have failed loudly instead of silently
  becoming a no-op in a live sync. Worth doing for every Helm-source ApplicationSet story.
- "Listener" is Gateway API vocabulary and does NOT mean "Traefik entrypoint". Reading AC5
  loosely would have led me to add `ports.websecure.expose.default: false` and break AC1's
  exact-match requirement. Rendering the chart resolved the ambiguity with evidence rather
  than a judgment call.
- The story body arrived triplicated (the IMPLEMENTATION/PRODUCES/AC sections repeat three
  times, with the third copy still carrying an unresolved `AF-<gateway-api-crds story's>`
  placeholder where the first two say `AF-qujb`). Harmless here since all three copies agree
  on the file contents, but extracting the spec programmatically with a regex over the JSON
  body and diffing beat re-typing it by hand -- and is what made a byte-exact AC1 claim
  possible. Sr PM may want to look at the duplication.
- This repo's Ruby is 2.6, so `Array#tally` is unavailable. Minor, but it cost one failed
  verification run; use `Hash.new(0)` counters in throwaway Ruby here.
- `pvg verify --format=text` is rejected; the flag takes a space (`--format text`).
