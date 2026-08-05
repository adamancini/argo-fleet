---
id: AF-q1il
title: "Cluster Lifecycle Tooling, OpenEBS LocalPV & Traefik Gateway for demo1/demo2"
status: open
priority: 1
type: epic
created_at: 2026-08-05T14:27:26Z
created_by: ada
updated_at: 2026-08-05T14:27:26Z
content_hash: "sha256:2577e7fc7dbf1eacccff6a39aacc6fdef18c5404a542dbbf49b5091f288521e1"
---

## Description
Description:
Bring the k3d clusters `demo1`/`demo2` to explicit, GitOps-managed parity with
`fleet-infra`'s real-cluster setup (OpenEBS Dynamic LocalPV instead of k3s's
invisible bundled `local-path-provisioner`, Traefik configured as a Gateway
API controller instead of k3s's invisible bundled Traefik), and migrate the
Terraform that registers these clusters as Argo CD/Kargo destinations out of
the separate `akp-infra` repo into `argo-fleet` itself, so this repo no
longer depends on `akp-infra` for day-2 cluster lifecycle operations.

BUSINESS CONTEXT:
This is a brownfield backlog derived directly from an already-approved
technical design and implementation plan (produced via
`superpowers:brainstorming` + `superpowers:writing-plans`, not a
Discovery & Framing cycle). There is no BUSINESS.md/DESIGN.md/
ARCHITECTURE.md for this project; the design spec and plan documents below
ARE the source of truth and are already committed to the repo:
- Design spec: docs/superpowers/specs/2026-08-05-cluster-lifecycle-and-ingress-storage-design.md
- Implementation plan: docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md

`argo-fleet` is a personal GitOps repo migrating services off Flux
(`fleet-infra`) onto Argo CD + Kargo, one app at a time, using `demo1`/
`demo2` (k3d clusters registered against a hosted Akuity Platform instance,
`quickstart-argocd`/`quickstart-kargo`) as a staging ground before the
eventual move to the real `annarchy.net`/`staging.annarchy.net` clusters.
Today, `demo1`/`demo2` get their `local-path` StorageClass and Traefik
ingress controller "for free" from k3s's own internal `HelmChart`
mechanism -- invisible to GitOps, untracked by Argo CD. The real clusters
this repo is migrating toward get neither for free (Talos ships nothing by
default); `fleet-infra` manages both explicitly via OpenEBS Dynamic LocalPV
and Traefik-as-Gateway-API-controller. The goal is to bring `demo1`/`demo2`
to that same explicitly-managed state using the same two components, so the
pattern this repo establishes for its tenant apps (`akkoma`/`soju`)
transfers cleanly when they eventually move to the real clusters.

Doing this cleanly requires disabling k3s's bundled Traefik/local-path at
cluster-creation time, which means recreating both k3d clusters. That is a
destructive act with real consequences: `demo1` currently runs the entire
`akp-platform` demo environment (all four `guestbook-*` variants across
dev/staging/prod, plus `rollouts-app`), and both clusters carry the Akuity
agent stack (Argo CD application-controller/repo-server, Kargo
controller/promotion-controller/rollouts/webhook) in the `akuity` namespace.
Recreating the k3d cluster destroys all of it. Rather than depend on the
separate `akp-infra` repo indefinitely for cluster/agent registration, that
Terraform (`akp-infra/03-clusters`) migrates into `argo-fleet` itself --
`akp-platform`/`akp-infra` remain as the original quickstart reference, but
`argo-fleet` becomes the actual, evolving home for this setup. The Argo
CD/Kargo *instance* provisioning (`akp-infra`'s `01-argocd`/`02-kargo`
stacks) is explicitly OUT of scope and does not change.

PROBLEM BEING SOLVED:
Current state: `demo1`/`demo2`'s storage and ingress are invisible to
GitOps (k3s's own internal mechanism, not tracked by Argo CD), and the
Terraform that registers these clusters as Argo CD/Kargo destinations lives
in a separate repo (`akp-infra`) this repo has no control over.
Target state: `demo1`/`demo2` have an explicit, Argo CD-managed
`local-path` StorageClass (OpenEBS Dynamic LocalPV, chart
`localpv-provisioner` 4.5.1, NOT the default class) and an explicit,
Argo CD-managed Traefik deployment configured as a Gateway API controller
(chart `traefik` 41.1.1, `Gateway` object named exactly `traefik-gateway`
so it matches what `fleet-infra`'s existing `HTTPRoute` resources already
reference via `parentRefs`), plus the Gateway API CRDs (experimental
channel v1.5.1) both charts depend on. The cluster+agent registration
Terraform lives in `argo-fleet/terraform/clusters/`, invoked via four new
`Taskfile.yml` tasks (`cluster:create`, `cluster:delete`,
`cluster:recreate`, `cluster:register-agent`), with `akp-infra/03-clusters`'
old state retired once the new registration is confirmed healthy.

TARGET STATE (observable, concrete):
1. `argo-fleet/terraform/clusters/` contains a working Terraform stack
   (byte-identical to its `akp-infra/03-clusters` source except for
   whitespace-only `terraform fmt` differences) that registers k3d clusters
   as Argo CD/Kargo destinations against the existing hosted
   `quickstart-argocd`/`quickstart-kargo` instances.
2. `task cluster:create|delete|recreate|register-agent -- <name>` all exist
   and work as documented.
3. `infrastructure/openebs-localpv/`, `infrastructure/traefik-gateway/`,
   `infrastructure/gateway-api-crds/` exist, following the exact
   `list`-generator ApplicationSet pattern already established by
   `infrastructure/sealed-secrets/`, and are statically valid (YAML
   syntax, pinned chart versions confirmed to exist in their real chart
   repos).
4. `demo1`/`demo2` are recreated with k3s's bundled Traefik/local-path
   disabled, re-registered from the new Terraform location, and their
   Argo CD/Kargo agents report healthy.
5. `akp-infra/03-clusters`' old Terraform state is retired (renamed, not
   deleted) only after the above is confirmed -- this repo never depends on
   it again.

ARCHITECTURE INTEGRATION (from the design spec/plan -- embedded, not
referenced):
- Terraform provider: `akuity/akp` (`~> 0.10`), authenticated via
  `AKUITY_API_KEY_ID`/`AKUITY_API_KEY_SECRET` environment variables (never
  in files). Stacks are wired together by instance NAME via provider data
  sources (`akp_instance`, `akp_kargo_instance`), not
  `terraform_remote_state` -- each stack stays independently applyable.
- Registration installs TWO agents per cluster into the `akuity` namespace:
  the Argo CD agent (`akp_cluster` resource, `ensure_healthy = true` blocks
  apply until the agent reports healthy) and the Kargo agent
  (`akp_kargo_agent` resource, `akuity_managed = false`, self-hosted,
  linked back to Argo CD via `remote_argocd`).
- k3d clusters bind their API server to `0.0.0.0` (rewritten to `127.0.0.1`
  in the Terraform module) and their kubeconfigs embed client
  certificates the module reads directly (no exec-plugin support needed
  for k3d).
- `infrastructure/*/argocd` directories are auto-discovered by the
  existing `bootstrap/infra-apps.yaml` ApplicationSet (git-directory
  generator, already deployed) -- new infra layers need no changes to that
  discovery mechanism, only a new `infrastructure/<name>/argocd/appset.yaml`
  following the `sealed-secrets` pattern (Argo CD native Helm-repository
  source instead of `sealed-secrets`' git+subpath source).
- Chart versions are pinned exactly and must match `fleet-infra`'s choices:
  `localpv-provisioner` 4.5.1 from `https://openebs.github.io/dynamic-localpv-provisioner`;
  `traefik` 41.1.1 from `https://traefik.github.io/charts`; Gateway API
  CRDs experimental channel `v1.5.1` from `kubernetes-sigs/gateway-api`.

DESIGN REQUIREMENTS (from the design spec -- embedded, not referenced):
- OpenEBS: `hostpathClass.name: local-path`, `isDefaultClass: "false"` --
  deliberately not the default class, matching `fleet-infra`'s own choice,
  keeping the StorageClass choice explicit rather than implicit even though
  it becomes the only StorageClass named `local-path` once k3s's bundled
  one is gone.
- Traefik: `providers.kubernetesGateway.enabled: true` +
  `experimentalChannel: true`, `providers.kubernetesIngress.enabled: true`,
  `providers.kubernetesCRD.enabled: true`, `ingressClass.isDefaultClass:
  true`, `gateway.enabled: true`, `gateway.name: traefik-gateway` (exact
  name match to `fleet-infra`'s existing `HTTPRoute` `parentRefs`). Only
  the plain-HTTP `web` listener is enabled; `websecure` (TLS) stays off --
  no cert-manager, no real domains yet.
- Explicitly OUT OF SCOPE for this epic (do not build): cert-manager/TLS;
  wiring `akkoma`/`soju` to the new Gateway with real `HTTPRoute`
  resources (they keep placeholder domains and `ingress.enabled: false`);
  migrating `akp-infra`'s `01-argocd`/`02-kargo` stacks (unchanged);
  re-deploying `akp-platform`'s demo apps onto the recreated `demo1` (that
  is `akp-platform`'s own manual bootstrap, `argocd app create -f
  bootstrap/platform-aoa.yaml`, and is explicitly not automated by any
  story in this epic).

Acceptance Criteria:
1. `argo-fleet/terraform/clusters/` exists, is a verbatim copy (modulo
   `terraform fmt` whitespace) of `akp-infra/03-clusters`, and passes
   `terraform validate` with `-backend=false`.
2. `task --list` shows `cluster:create`, `cluster:delete`,
   `cluster:recreate`, `cluster:register-agent`, each matching the design
   spec's Taskfile section exactly.
3. `infrastructure/openebs-localpv/argocd/appset.yaml`,
   `infrastructure/traefik-gateway/argocd/appset.yaml`,
   `infrastructure/gateway-api-crds/argocd/appset.yaml` all exist, are
   valid YAML, and pin the exact chart/CRD versions named above.
4. All of the above is statically verified (YAML/HCL syntax, byte-identical
   diff against source, real-chart-version cross-check) with zero live
   cluster or Terraform-state mutation, and that verification is a single
   auditable story separate from the file-authoring stories.
5. `demo1`/`demo2` are recreated without k3s's bundled Traefik/local-path,
   re-registered from the new Terraform location, and both Argo CD/Kargo
   agents are confirmed healthy by a human before `akp-infra/03-clusters`'
   old state is retired -- this step is gated, human-executed, and
   structurally distinct from every other story in this epic (it is never
   claimed or run by an autonomous Developer/PM-Acceptor pair).

MANDATORY SKILLS TO REVIEW:
None identified at the epic level (see child stories for per-story skill
annotations).

## Acceptance Criteria


## Design


## Notes


## History


## Links


## Comments
