---
id: AF-qujb
title: "Add gateway-api-crds infrastructure layer for demo1/demo2"
status: open
priority: 1
type: task
parent: AF-q1il
created_at: 2026-08-05T14:32:18Z
created_by: ada
updated_at: 2026-08-05T14:37:35Z
content_hash: "sha256:453fff64cc2e94460367fadbc9621733d68f7c8136739aeaf3345d5cf8e9ad4a"
blocks: [AF-cbot]
---

## Description
Description:
Add `infrastructure/gateway-api-crds/` -- an Argo CD ApplicationSet that
installs the Gateway API CRDs (`Gateway`, `HTTPRoute`, `GatewayClass`,
etc.) at the experimental channel, version `v1.5.1`, on every cluster.
Traefik's own Helm chart (AF-vwvq) does not install these CRDs itself; they
must exist before Traefik's chart can create its `Gateway` object.

Context:
Same repo pattern as AF-8ik8/AF-vwvq (`infrastructure/sealed-secrets/`'s
`list`-generator shape, verified by reading it directly), but the source
here is a plain git repo/path rather than a Helm chart repo -- the upstream
`kubernetes-sigs/gateway-api` project ships its CRDs as plain YAML under
`config/crd/experimental`, not as a Helm chart.

Version `v1.5.1` matches exactly what `fleet-infra` already uses for the
same CRDs on the real clusters (per the design spec) -- keeping the two
environments' CRD versions in lockstep avoids a real-cluster/demo-cluster
API-version drift that would make demo-tested manifests behave differently
once ported.

Ordering: this Application's resources carry
`argocd.argoproj.io/sync-wave: "-1"`, making Argo CD sync them before
wave-0 (default) Applications on the same cluster, including AF-vwvq's
`traefik-gateway`. This only controls sync order within a single Argo CD
sync operation, not creation order -- if `traefik-gateway` errors on its
first sync attempt because these CRDs aren't registered yet, Argo CD's
`selfHeal` retries it automatically once this Application succeeds. That
retry behavior is exercised for real only in the epic's human-gated
release-gate story, not in this story.

USER INTENT:
Anyone reading this repo's `infrastructure/` directory needs the CRD
dependency between `gateway-api-crds` and `traefik-gateway` to be legible
from the files themselves (the sync-wave annotation, the README's ordering
note) rather than something that only becomes apparent from an
undocumented sync failure the first time these Applications run together.
Once synced, this ApplicationSet emits one Application per cluster, and
the CRDs it installs are what makes `Gateway`/`HTTPRoute` objects
resolvable at all -- without them, a user can create an `HTTPRoute` but
the API server rejects it outright.

IMPLEMENTATION:
Create `infrastructure/gateway-api-crds/argocd/appset.yaml`:
```yaml
# One Application per cluster, installing the Gateway API CRDs (Gateway,
# HTTPRoute, GatewayClass, etc.) at the experimental channel -- the same
# version fleet-infra uses. Traefik's own chart doesn't install these; the
# traefik-gateway Application (infrastructure/traefik-gateway/) depends on
# them existing first.
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: gateway-api-crds
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: demo1
      - cluster: demo2
  template:
    metadata:
      name: 'gateway-api-crds-{{cluster}}'
      annotations:
        argocd.argoproj.io/sync-wave: "-1"
    spec:
      project: default
      source:
        repoURL: https://github.com/kubernetes-sigs/gateway-api.git
        targetRevision: v1.5.1
        path: config/crd/experimental
        directory:
          recurse: true
      destination:
        name: '{{cluster}}'
        namespace: default
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

Create `infrastructure/gateway-api-crds/README.md`:
```markdown
# gateway-api-crds — cluster-wide dependency, no promotion pipeline

Installs the [Gateway API](https://gateway-api.sigs.k8s.io/) CRDs
(`Gateway`, `HTTPRoute`, `GatewayClass`, etc.) at the experimental channel,
version `v1.5.1` -- the same version
[fleet-infra](https://github.com/adamancini/fleet-infra) uses. Traefik's own
Helm chart doesn't install these CRDs itself; `traefik-gateway`
(`infrastructure/traefik-gateway/`) needs them present before it can create
its `Gateway` object.

## Ordering

`argocd.argoproj.io/sync-wave: "-1"` makes Argo CD sync this Application's
resources before wave-0 (default) Applications on the same cluster,
including `traefik-gateway` -- so the CRDs land first. This only controls
sync order within a single Argo CD sync operation; it doesn't block
`traefik-gateway` from being *created* first, only from *syncing
successfully* first. If `traefik-gateway` errors on its first sync attempt
because the CRDs aren't registered yet, Argo CD's `selfHeal` will retry it
automatically once this Application succeeds -- no manual intervention
needed, just a one-time delay on the very first sync after the epic's
release-gate story recreates the clusters.
```

Validation (static only -- no cluster is touched by this story):
`ruby -ryaml -e "YAML.load_stream(File.read('infrastructure/gateway-api-crds/argocd/appset.yaml'))" && echo OK`
-- expect `OK`.

KEY FILES:
- Create: infrastructure/gateway-api-crds/argocd/appset.yaml
- Create: infrastructure/gateway-api-crds/README.md

PRODUCES:
- infrastructure/gateway-api-crds/argocd/appset.yaml -> ApplicationSet
  `gateway-api-crds` (namespace `argocd`), `list` generator with elements
  `demo1`/`demo2`, templating Applications named
  `gateway-api-crds-{{cluster}}` (sync-wave `-1`) that install the
  `Gateway`/`HTTPRoute`/`GatewayClass` CRDs from
  `https://github.com/kubernetes-sigs/gateway-api.git` at `v1.5.1`,
  path `config/crd/experimental`, into namespace `default` on each
  cluster. Consumed by AF-vwvq's `traefik-gateway` Application, which
  needs these CRDs registered before its chart's `Gateway` object can
  reconcile.
  source: docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
  Task 5 (verbatim); discovered automatically by the existing
  `bootstrap/infra-apps.yaml` git-directory generator (verified by reading
  that file directly -- no change needed there).

CONSUMES:
None -- this story has no upstream dependency within this backlog. It
consumes only pre-existing repo state (`bootstrap/infra-apps.yaml`'s
discovery mechanism), verified directly by reading that file during story
authoring, not produced by any story in this epic.

TESTING:
Static validation only (YAML syntax). No cluster is touched. The
sync-wave/selfHeal retry ordering documented in the README is exercised
for real only in the epic's human-gated release-gate story, not in this
story.

Acceptance Criteria:
1. [Ubiquitous] `infrastructure/gateway-api-crds/argocd/appset.yaml` exists
   with content matching IMPLEMENTATION exactly, including
   `targetRevision: v1.5.1`, `path: config/crd/experimental`, and the
   `argocd.argoproj.io/sync-wave: "-1"` annotation on the template metadata.
2. [Ubiquitous] `infrastructure/gateway-api-crds/README.md` exists and
   documents the sync-wave ordering and expected one-time selfHeal retry.
3. [Event] `ruby -ryaml -e "YAML.load_stream(...)"` against the appset.yaml
   exits with `OK` and no YAML parse error.
4. [Ubiquitous] `spec.source.targetRevision` is exactly `v1.5.1`, matching
   the version `fleet-infra` already uses (per the epic body's
   ARCHITECTURE INTEGRATION section) -- not a newer or older tag.
5. [Unwanted] This story shall not sync, apply, or otherwise mutate any
   live Argo CD instance or k3d cluster -- verification is limited to
   static YAML parsing.

MANDATORY SKILLS TO REVIEW:
`devops-toolkit:yaml-kubernetes-validator` -- this story authors an Argo CD
ApplicationSet manifest; load the skill and apply its YAML/Kubernetes
manifest review guidance before finalizing.

# One Application per cluster, installing the Gateway API CRDs (Gateway,
# HTTPRoute, GatewayClass, etc.) at the experimental channel -- the same
# version fleet-infra uses. Traefik's own chart doesn't install these; the
# traefik-gateway Application (infrastructure/traefik-gateway/) depends on
# them existing first.
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: gateway-api-crds
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: demo1
      - cluster: demo2
  template:
    metadata:
      name: 'gateway-api-crds-{{cluster}}'
      annotations:
        argocd.argoproj.io/sync-wave: "-1"
    spec:
      project: default
      source:
        repoURL: https://github.com/kubernetes-sigs/gateway-api.git
        targetRevision: v1.5.1
        path: config/crd/experimental
        directory:
          recurse: true
      destination:
        name: '{{cluster}}'
        namespace: default
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

Create `infrastructure/gateway-api-crds/README.md`:
```markdown
# gateway-api-crds — cluster-wide dependency, no promotion pipeline

Installs the [Gateway API](https://gateway-api.sigs.k8s.io/) CRDs
(`Gateway`, `HTTPRoute`, `GatewayClass`, etc.) at the experimental channel,
version `v1.5.1` -- the same version
[fleet-infra](https://github.com/adamancini/fleet-infra) uses. Traefik's own
Helm chart doesn't install these CRDs itself; `traefik-gateway`
(`infrastructure/traefik-gateway/`) needs them present before it can create
its `Gateway` object.

## Ordering

`argocd.argoproj.io/sync-wave: "-1"` makes Argo CD sync this Application's
resources before wave-0 (default) Applications on the same cluster,
including `traefik-gateway` -- so the CRDs land first. This only controls
sync order within a single Argo CD sync operation; it doesn't block
`traefik-gateway` from being *created* first, only from *syncing
successfully* first. If `traefik-gateway` errors on its first sync attempt
because the CRDs aren't registered yet, Argo CD's `selfHeal` will retry it
automatically once this Application succeeds -- no manual intervention
needed, just a one-time delay on the very first sync after the epic's
release-gate story recreates the clusters.
```

Validation (static only -- no cluster is touched by this story):
`ruby -ryaml -e "YAML.load_stream(File.read('infrastructure/gateway-api-crds/argocd/appset.yaml'))" && echo OK`
-- expect `OK`.

KEY FILES:
- Create: infrastructure/gateway-api-crds/argocd/appset.yaml
- Create: infrastructure/gateway-api-crds/README.md

PRODUCES:
- infrastructure/gateway-api-crds/argocd/appset.yaml -> ApplicationSet
  `gateway-api-crds` (namespace `argocd`), `list` generator with elements
  `demo1`/`demo2`, templating Applications named
  `gateway-api-crds-{{cluster}}` (sync-wave `-1`) that install the
  `Gateway`/`HTTPRoute`/`GatewayClass` CRDs from
  `https://github.com/kubernetes-sigs/gateway-api.git` at `v1.5.1`,
  path `config/crd/experimental`, into namespace `default` on each
  cluster. Consumed by AF-vwvq's `traefik-gateway` Application, which
  needs these CRDs registered before its chart's `Gateway` object can
  reconcile.
  source: docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
  Task 5 (verbatim); discovered automatically by the existing
  `bootstrap/infra-apps.yaml` git-directory generator (verified by reading
  that file directly -- no change needed there).

CONSUMES:
None -- this story has no upstream dependency within this backlog. It
consumes only pre-existing repo state (`bootstrap/infra-apps.yaml`'s
discovery mechanism), verified directly by reading that file during story
authoring, not produced by any story in this epic.

TESTING:
Static validation only (YAML syntax). No cluster is touched. The
sync-wave/selfHeal retry ordering documented in the README is exercised
for real only in the epic's human-gated release-gate story, not in this
story.

Acceptance Criteria:
1. [Ubiquitous] `infrastructure/gateway-api-crds/argocd/appset.yaml` exists
   with content matching IMPLEMENTATION exactly, including
   `targetRevision: v1.5.1`, `path: config/crd/experimental`, and the
   `argocd.argoproj.io/sync-wave: "-1"` annotation on the template metadata.
2. [Ubiquitous] `infrastructure/gateway-api-crds/README.md` exists and
   documents the sync-wave ordering and expected one-time selfHeal retry.
3. [Event] `ruby -ryaml -e "YAML.load_stream(...)"` against the appset.yaml
   exits with `OK` and no YAML parse error.
4. [Ubiquitous] `spec.source.targetRevision` is exactly `v1.5.1`, matching
   the version `fleet-infra` already uses (per the epic body's
   ARCHITECTURE INTEGRATION section) -- not a newer or older tag.
5. [Unwanted] This story shall not sync, apply, or otherwise mutate any
   live Argo CD instance or k3d cluster -- verification is limited to
   static YAML parsing.

MANDATORY SKILLS TO REVIEW:
`devops-toolkit:yaml-kubernetes-validator` -- this story authors an Argo CD
ApplicationSet manifest; load the skill and apply its YAML/Kubernetes
manifest review guidance before finalizing.

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-05T14:33:41Z dep_added: blocks AF-cbot

## Links
- Parent: [[AF-q1il]]
- Blocks: [[AF-cbot]]

## Comments
