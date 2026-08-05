---
id: AF-8ik8
title: "Add openebs-localpv infrastructure layer for demo1/demo2"
status: open
priority: 1
type: task
parent: AF-q1il
created_at: 2026-08-05T14:30:55Z
created_by: ada
updated_at: 2026-08-05T14:30:55Z
content_hash: "sha256:ad0657378e717139a07a4b95633f3b53ea8811206a242353b2ca25732b104a78"
---

## Description
Description:
Add `infrastructure/openebs-localpv/` -- an Argo CD ApplicationSet that
installs OpenEBS Dynamic LocalPV Provisioner on every cluster, giving
`demo1`/`demo2` an explicit, GitOps-managed `local-path` StorageClass
instead of k3s's invisible bundled one.

Context:
This repo already has one working example of this exact pattern:
`infrastructure/sealed-secrets/` (verified by reading it directly during
story authoring -- its `argocd/appset.yaml` uses a `list` generator with
`demo1`/`demo2` elements, a git+subpath Helm source, and
`syncPolicy.automated.{prune,selfHeal}` with `CreateNamespace=true`). This
story follows the same `infrastructure/<name>/{README.md,argocd/appset.yaml}`
shape, but uses Argo CD's native Helm-repository source (`repoURL` = chart
repo URL, `chart` = chart name, `targetRevision` = pinned version) instead
of `sealed-secrets`' git+subpath source -- the idiomatic form for charts
published to a real chart repository, and what the design spec specifies
for both new infra layers in this epic.

The existing `bootstrap/infra-apps.yaml` ApplicationSet (verified by
reading it directly: a `git` directory generator watching
`infrastructure/*/argocd`, templating one child Application per matched
directory with `path: '{{path}}'` and `directory.recurse: true`) already
discovers any new `infrastructure/<name>/argocd/` directory automatically
-- this story needs no changes to that discovery mechanism.

Per the design spec: k3s's own bundled `local-path` StorageClass must be
gone before this Application can sync cleanly (it creates a StorageClass
also named `local-path` -- a naming collision if both exist). That removal
happens in AF-4wcm's Taskfile tasks (`cluster:recreate`, via
`--k3s-arg "--disable=local-storage@server:0"`) and is exercised for real
only in the epic's human-gated release-gate story -- this story only
authors and statically validates the file, it does not sync it against a
live cluster.

USER INTENT:
Anyone reading this repo's `infrastructure/` directory needs to see
storage provisioning as an explicit, version-controlled decision (chart
version pinned, StorageClass name and default-class choice spelled out in
git) rather than an invisible k3s default -- matching the real-cluster
precedent (`fleet-infra`) this repo is migrating toward, so the same
pattern transfers without translation later.

IMPLEMENTATION:
Create `infrastructure/openebs-localpv/argocd/appset.yaml`:
```yaml
# One Application per cluster, installing OpenEBS's Dynamic LocalPV
# Provisioner. Mirrors fleet-infra's real-cluster setup: the StorageClass is
# named "local-path" (matching what k3s's bundled provisioner used to
# provide, before the cluster-recreate task disables it) but is NOT the
# default class -- that choice stays explicit rather than implicit.
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: openebs-localpv
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: demo1
      - cluster: demo2
  template:
    metadata:
      name: 'openebs-localpv-{{cluster}}'
    spec:
      project: default
      source:
        repoURL: https://openebs.github.io/dynamic-localpv-provisioner
        chart: localpv-provisioner
        targetRevision: 4.5.1
        helm:
          valuesObject:
            localpv:
              basePath: /var/openebs/local
              resources:
                requests:
                  cpu: 5m
                  memory: 24Mi
                limits:
                  memory: 64Mi
            hostpathClass:
              name: local-path
              isDefaultClass: "false"
              reclaimPolicy: Delete
      destination:
        name: '{{cluster}}'
        namespace: openebs
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

Create `infrastructure/openebs-localpv/README.md`:
```markdown
# openebs-localpv — cluster-wide dependency, no promotion pipeline

Installs [OpenEBS Dynamic LocalPV Provisioner](https://github.com/openebs/dynamic-localpv-provisioner)
on every cluster in `argocd/appset.yaml`'s `list` generator (`demo1`,
`demo2`), providing a `local-path` StorageClass explicitly managed via
GitOps -- unlike k3s's own bundled `local-path-provisioner`, which installs
itself invisibly and isn't tracked by Argo CD at all.

Values mirror [fleet-infra](https://github.com/adamancini/fleet-infra)'s
real-cluster setup exactly: `hostpathClass.name: local-path`,
`isDefaultClass: "false"`. Not the default class deliberately -- the choice
of which StorageClass new PVCs use unqualified stays explicit rather than
falling back to whatever happens to be marked default.

## Prerequisite

k3s's own bundled `local-path` StorageClass must be gone first, or there's a
naming collision -- this Application creates a StorageClass named
`local-path` too. `demo1`/`demo2` get this via `task cluster:recreate`,
which disables k3s's bundled provisioner at cluster-creation time
(`--k3s-arg "--disable=local-storage@server:0"`). Syncing this Application
against a cluster that still has k3s's own `local-path` class will either
fail (Argo CD detects the existing object isn't managed by it) or silently
adopt/overwrite it, depending on sync options -- don't sync this before
recreating the cluster.
```

Validation (static only -- no cluster is touched by this story):
`ruby -ryaml -e "YAML.load_stream(File.read('infrastructure/openebs-localpv/argocd/appset.yaml'))" && echo OK`
-- expect `OK`.

KEY FILES:
- Create: infrastructure/openebs-localpv/argocd/appset.yaml
- Create: infrastructure/openebs-localpv/README.md

PRODUCES:
- infrastructure/openebs-localpv/argocd/appset.yaml -> ApplicationSet
  `openebs-localpv` (namespace `argocd`), `list` generator with elements
  `demo1`/`demo2`, templating Applications named
  `openebs-localpv-{{cluster}}` that install chart `localpv-provisioner`
  4.5.1 from `https://openebs.github.io/dynamic-localpv-provisioner` into
  namespace `openebs` on each cluster, creating a StorageClass named
  `local-path` with `isDefaultClass: "false"`.
  source: docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
  Task 3 (verbatim); discovered automatically by the existing
  `bootstrap/infra-apps.yaml` git-directory generator (verified by reading
  that file directly -- no change needed there).

TESTING:
Static validation only (YAML syntax). No cluster is touched. The
Prerequisite note in the README documents a real ordering dependency
(k3s's bundled `local-path` must be gone first) that is exercised for real
only in the epic's human-gated release-gate story, not in this story.

Acceptance Criteria:
1. [Ubiquitous] `infrastructure/openebs-localpv/argocd/appset.yaml` exists
   with content matching IMPLEMENTATION exactly, including chart version
   `4.5.1`, repo URL `https://openebs.github.io/dynamic-localpv-provisioner`,
   `hostpathClass.name: local-path`, `hostpathClass.isDefaultClass: "false"`.
2. [Ubiquitous] `infrastructure/openebs-localpv/README.md` exists and
   documents the k3s-bundled-`local-path`-must-be-gone-first prerequisite.
3. [Event] `ruby -ryaml -e "YAML.load_stream(...)"` against the appset.yaml
   exits with `OK` and no YAML parse error.
4. [Ubiquitous] The ApplicationSet's `list` generator elements are exactly
   `demo1` and `demo2` -- matching the cluster names used everywhere else
   in this epic (AF-4wcm's Terraform `var.clusters` keys, AF-pydv's
   Taskfile `<name>` argument).
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


## Links
- Parent: [[AF-q1il]]

## Comments
