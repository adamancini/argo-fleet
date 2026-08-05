---
id: AF-vwvq
title: "Add traefik-gateway infrastructure layer for demo1/demo2"
status: in_progress
priority: 1
type: task
parent: AF-q1il
created_at: 2026-08-05T14:31:38Z
created_by: ada
updated_at: 2026-08-05T14:56:24Z
content_hash: "sha256:c842f612905aab170ace50509b529cd99cbfff64037a3b8c6ad1cbc262f7f5e0"
blocks: [AF-cbot]
assignee: dev-AF-vwvq
labels: [delivered]
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

## Links
- Parent: [[AF-q1il]]
- Blocks: [[AF-cbot]]

## Comments
