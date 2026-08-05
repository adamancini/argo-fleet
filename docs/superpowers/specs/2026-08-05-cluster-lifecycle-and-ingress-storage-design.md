# Cluster lifecycle tooling + OpenEBS LocalPV + Traefik-as-Gateway

## Context

`demo1`/`demo2` are local k3d clusters, registered as Argo CD/Kargo workload
clusters against an existing Akuity Platform instance (`ada-quickstart-argocd`
/ `ada-quickstart-kargo`), via Terraform in a separate repo (`akp-infra`,
stack `03-clusters`). k3d/k3s bundles a default `local-path` StorageClass and
a running Traefik ingress controller on every cluster — both already work,
but they're invisible to GitOps: k3s installs them via its own internal
`HelmChart` mechanism, not via anything this repo (or Argo CD) manages or
tracks.

The real clusters this whole effort is eventually migrating toward
(`annarchy.net`/`staging.annarchy.net`, managed by `fleet-infra` via Flux) get
neither for free — Talos ships nothing by default. `fleet-infra` manages both
explicitly: **OpenEBS Dynamic LocalPV Provisioner** for local storage
(`hostpathClass.name: local-path`, deliberately not the default class), and
**Traefik configured as a Gateway API controller** (not classic Ingress —
apps there use `HTTPRoute` resources with `parentRefs` pointing at a Gateway
named `traefik-gateway`).

The goal here is to bring `demo1`/`demo2` to the same explicitly-managed
state, using the same two components fleet-infra already uses, so the
pattern this repo establishes for `akkoma`/`soju` transfers cleanly when they
eventually move to the real clusters.

Getting there cleanly means disabling k3s's bundled Traefik/local-path at
cluster-creation time — which means recreating both k3d clusters. That wipes
more than initially expected: `demo1` currently runs the *entire*
`akp-platform` demo environment (all four `guestbook-*` variants across
dev/staging/prod, plus `rollouts-app`), and both clusters carry the Akuity
agent stack (`akuity-agent`, Argo CD application-controller/repo-server,
Kargo controller/promotion-controller/rollouts/webhook) in the `akuity`
namespace. Recreating the k3d cluster destroys all of that, and
re-registering it as an Argo CD/Kargo destination means re-running the
Terraform in `akp-infra/03-clusters` against the fresh kubeconfig.

Rather than depend on a separate `akp-infra` repo indefinitely for this,
`akp-infra`'s `03-clusters` stack (cluster + agent registration Terraform)
migrates into `argo-fleet` itself — `akp-platform`/`akp-infra` remain as the
original quickstart reference, but `argo-fleet` becomes the actual,
evolving home for this real setup. The Argo CD/Kargo *instance* provisioning
(`akp-infra`'s `01-argocd`/`02-kargo` stacks) stays in `akp-infra` — nothing
there needs to change, and this effort isn't creating a new instance.

## Scope

**In scope:**

- Migrate `akp-infra/03-clusters` (Terraform: cluster + Argo CD/Kargo agent
  registration) into `argo-fleet/terraform/clusters/`, including a careful,
  human-verified state move (see "Terraform migration" below) so ownership
  transfers without touching the live registered resources.
- New `Taskfile.yml` tasks: `cluster:create`, `cluster:delete`,
  `cluster:recreate`, `cluster:register-agent` — k3d cluster lifecycle plus
  Argo CD/Kargo agent (re-)registration via the migrated Terraform.
- Recreate `demo1` and `demo2` with k3s's bundled Traefik and
  local-storage disabled, then re-register both.
- New `infrastructure/` pieces, mirroring `fleet-infra`: **OpenEBS Dynamic
  LocalPV Provisioner** (chart `localpv-provisioner` `4.5.1`,
  `hostpathClass.name: local-path`, not the default class), **Traefik**
  configured as a Gateway API controller (chart `traefik` `41.1.1`,
  `providers.kubernetesGateway` + `providers.kubernetesIngress` both
  enabled, `gateway.name: traefik-gateway` — matching the exact name
  `fleet-infra`'s existing `HTTPRoute` resources reference), and the
  Gateway API CRDs (`kubernetes-sigs/gateway-api` experimental channel
  `v1.5.1`, same version `fleet-infra` uses).

**Explicitly deferred (not built as part of this spec):**

- cert-manager / TLS — still no real domains. Traefik's `websecure`
  listener stays disabled; only the plain-HTTP `web` listener is enabled.
- Wiring `akkoma`/`soju` to the new Gateway (an actual `HTTPRoute` per app)
  — they still use placeholder domains and `ingress.enabled: false`. That's
  a follow-up once real domains exist, not part of this spec.
- Migrating `akp-infra`'s `01-argocd`/`02-kargo` stacks — the Argo CD/Kargo
  *instances* already exist and aren't changing; only cluster/agent
  registration (`03-clusters`) moves.
- Re-deploying the `akp-platform` demo apps (`guestbook-*`) onto the
  recreated `demo1` — that's `akp-platform`'s own bootstrap
  (`argocd app create -f bootstrap/platform-aoa.yaml`), re-run manually
  after recreation; not something this spec's tasks automate.

## Terraform migration

**Code** (straightforward copy, `akp-infra/03-clusters/` →
`argo-fleet/terraform/clusters/`): `main.tf`, `outputs.tf`, `providers.tf`,
`variables.tf`, `modules/cluster/{main.tf,outputs.tf,variables.tf}`,
`templates/kustomization.yaml`, `terraform.tfvars.example`.

**State** needs care, not just a copy-paste. `akp-infra/03-clusters` uses
purely local state (no remote backend) — `terraform.tfstate` almost
certainly contains the real kubeconfig client-certificate/key material for
`demo1`/`demo2` as tracked resource attributes (Terraform's `sensitive` flag
only masks CLI output; it does not encrypt state at rest). Since both
clusters are being recreated anyway as part of this same effort, the actual
sequence is:

1. Copy the Terraform code (above) into `argo-fleet/terraform/clusters/`.
2. Copy `terraform.tfvars` (same content as `akp-infra`'s, `org_name`,
   instance names, `kargo_default_shard`) and create the `.kubeconfigs/`
   directory — both gitignored in the new location exactly as they are in
   `akp-infra` (`.terraform/`, `*.tfstate*`, `*.tfvars` except
   `*.tfvars.example`, `.kubeconfigs/`).
3. Recreate `demo1`/`demo2` (see Taskfile section) and run
   `cluster:register-agent` for each from the **new** location. Since the
   clusters are fresh, this is a normal `terraform apply` in the new
   location — not a state import — so there's no state file to move at all.
4. Once both agents report healthy from the new location, remove
   `akp-infra/03-clusters/terraform.tfstate*` (or the whole directory) so
   it can never be applied from there again — the old state described
   clusters that no longer exist in that form.

Because the clusters are being recreated regardless, registering fresh from
the new location is simpler and safer than moving live Terraform state
across repos — there's no state file to migrate at all, just new resources
created against existing kubeconfigs. **Before deleting anything in
`akp-infra/03-clusters`**, a human should
confirm both new registrations show healthy agents (`kubectl -n akuity get
pods` on each cluster, or the Akuity Platform UI) — this is the one gate in
this whole effort that isn't just a static check.

## Taskfile: cluster lifecycle

```
task cluster:create -- <name>
task cluster:delete -- <name>
task cluster:recreate -- <name>
task cluster:register-agent -- <name>
```

- `cluster:create`: `k3d cluster create <name>` with
  `--k3s-arg "--disable=traefik@server:0"` and
  `--k3s-arg "--disable=local-storage@server:0"`. `servicelb` (k3d's
  built-in load-balancer, giving `LoadBalancer`-type Services a routable
  IP on the docker network) stays enabled — the new Traefik Application
  needs it.
- `cluster:delete`: `k3d cluster delete <name>`.
- `cluster:recreate`: delete then create, inlined directly (not a nested
  `task:` call to the two above) to avoid any ambiguity about whether
  `CLI_ARGS`/`CLI_ARGS_LIST` forwards correctly across nested task
  invocations — a category of bug already hit once in this repo's Sealed
  Secrets tasks.
- `cluster:register-agent`: `k3d kubeconfig get <name>` written to
  `terraform/clusters/.kubeconfigs/<name>.yaml` (matching the exact path
  convention `terraform.tfvars` already expects), then
  `terraform apply -target='module.cluster["<name>"]'` from
  `terraform/clusters/`.

## `infrastructure/` additions

Both use Argo CD's native Helm-repository source (`repoURL` = the chart
repo, `chart` = name, `targetRevision` = pinned version) — cleaner than
`sealed-secrets`'s git+subpath source, and the idiomatic form for charts
published to a real chart repo. `list` generator with `demo1`/`demo2`
elements, matching `infrastructure/sealed-secrets/`'s existing pattern
exactly (this repo's established convention for cluster-wide dependencies
with no Kargo pipeline).

**`infrastructure/openebs-localpv/`**: chart `localpv-provisioner` `4.5.1`
from `https://openebs.github.io/dynamic-localpv-provisioner`. Values mirror
`fleet-infra` exactly: `localpv.basePath: /var/openebs/local`,
`hostpathClass.name: local-path`, `hostpathClass.isDefaultClass: "false"`.
Not the default class deliberately — matches fleet-infra's own choice, and
once k3s's bundled `local-path` is gone (disabled at cluster-create time)
this becomes the only StorageClass named `local-path`, but staying
non-default keeps the choice explicit rather than implicit.

**`infrastructure/traefik-gateway/`**: chart `traefik` `41.1.1` from
`https://traefik.github.io/charts`. Values: `providers.kubernetesGateway.
enabled: true` + `experimentalChannel: true`, `providers.kubernetesIngress.
enabled: true` (both stay on, matching fleet-infra — Gateway API and classic
Ingress aren't mutually exclusive), `providers.kubernetesCRD.enabled: true`
(Traefik's own CRDs — Middleware, etc.), `ingressClass.enabled: true` +
`isDefaultClass: true`, `gateway.enabled: true` + `gateway.name:
traefik-gateway` (the current chart version creates the `Gateway` object
for you from these values — no hand-authored `Gateway` YAML needed; the name
is set explicitly to match what `fleet-infra`'s `HTTPRoute` resources already
reference via `parentRefs`). Only the `web` listener (plain HTTP,
port 8000, exposed as 80) is enabled; `websecure` (TLS) stays off — no
cert-manager yet. `service.type: LoadBalancer`, no fixed `loadBalancerIP`
(unlike fleet-infra's real hardware LB with a reserved IP, k3d's `servicelb`
assigns one dynamically on the docker network).

**`infrastructure/gateway-api-crds/`**: a single Application (or plain
`list`-generated pair) installing `kubernetes-sigs/gateway-api`'s
experimental-channel CRDs at `v1.5.1` — same version fleet-infra uses.
Traefik's chart doesn't install these itself.
