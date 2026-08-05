# openebs-localpv — cluster-wide dependency, no promotion pipeline

Installs [OpenEBS Dynamic LocalPV Provisioner](https://github.com/openebs/dynamic-localpv-provisioner)
on every cluster in `argocd/appset.yaml`'s `list` generator (`demo1`,
`demo2`), providing a `local-path` StorageClass explicitly managed via
GitOps -- unlike k3s's own bundled `local-path-provisioner`, which installs
itself invisibly and isn't tracked by Argo CD at all.

Values mirror [fleet-infra](https://github.com/adamancini/fleet-infra)'s
real-cluster setup: `hostpathClass.name: local-path`,
`isDefaultClass: false`. Not the default class deliberately -- the choice
of which StorageClass new PVCs use unqualified stays explicit rather than
falling back to whatever happens to be marked default.

`isDefaultClass` must stay an **unquoted boolean**. The chart gates the
`storageclass.kubernetes.io/is-default-class` annotation on
`{{- if .Values.hostpathClass.isDefaultClass }}`, and Go templates treat the
non-empty string `"false"` as true -- so writing `isDefaultClass: "false"`
does the exact opposite of what it reads like and makes `local-path` the
cluster default. Verified against chart 4.5.1 with `helm template`.

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
