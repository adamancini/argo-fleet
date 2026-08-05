# Cluster Lifecycle Tooling + OpenEBS LocalPV + Traefik-as-Gateway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Task 7 is different in kind from every other task in this plan.** Tasks 1-6 only create files and run read-only/static validation — nothing they do touches a live cluster or the real Terraform state in `akp-infra`. Task 7 recreates real, currently-registered k3d clusters and destroys everything running on them. **Do not dispatch Task 7 to an autonomous implementer the same way as Tasks 1-6.** It must be run by a human, one step at a time, with the two explicit confirmation gates it describes. If you are an agent executing this plan and you reach Task 7, stop and hand it back rather than running its commands yourself.

**Goal:** Bring `demo1`/`demo2` to explicit, GitOps-managed parity with `fleet-infra`'s real-cluster setup (OpenEBS Dynamic LocalPV + Traefik-as-Gateway-API-controller instead of k3s's invisible bundled defaults), and migrate the Terraform that registers these clusters as Argo CD/Kargo destinations out of the separate `akp-infra` repo and into `argo-fleet` itself.

**Architecture:** Terraform code moves by file copy (no state migration needed, since the clusters get recreated anyway); new Taskfile tasks wrap the k3d + Terraform commands for repeatable cluster lifecycle management; two new `infrastructure/*/argocd/appset.yaml` pieces follow the existing `sealed-secrets` `list`-generator pattern but use Argo CD's native Helm-repository source instead of a git+subpath source.

**Tech Stack:** Terraform (`akuity/akp` provider), k3d, Argo CD, Helm charts (`localpv-provisioner`, `traefik`), Gateway API CRDs, Task (`go-task`).

## Global Constraints

- Chart versions, pinned exactly: `localpv-provisioner` `4.5.1` from `https://openebs.github.io/dynamic-localpv-provisioner`; `traefik` `41.1.1` from `https://traefik.github.io/charts`. Gateway API CRDs at `v1.5.1` (experimental channel), matching the version `fleet-infra` already uses.
- `hostpathClass.name: local-path`, `hostpathClass.isDefaultClass: "false"` for OpenEBS — matches `fleet-infra` exactly. Not the default class.
- Traefik: `providers.kubernetesGateway.enabled: true` + `experimentalChannel: true`, `providers.kubernetesIngress.enabled: true`, `providers.kubernetesCRD.enabled: true`, `ingressClass.isDefaultClass: true`, `gateway.enabled: true`, `gateway.name: traefik-gateway` (exact name — `fleet-infra`'s `HTTPRoute` resources already reference this via `parentRefs`). Only the `web` (HTTP) listener enabled; `websecure` (TLS) stays off — no cert-manager yet.
- `akp-infra`'s `01-argocd`/`02-kargo` stacks are NOT migrated — only `03-clusters`. Nothing in those two stacks changes.
- No task in this plan except Task 7 runs a command that mutates a real k3d cluster, applies real Terraform against live state, or touches `akp-infra/03-clusters`' existing state files. Tasks 1-6 produce and statically validate files only.
- `demo1` currently runs the entire `akp-platform` demo environment (all `guestbook-*` variants across dev/staging/prod, plus `rollouts-app`) and both clusters run the Akuity agent stack in the `akuity` namespace — Task 7 destroys all of this on both clusters, by design, per the approved spec.

---

## File Structure

```text
argo-fleet/
├── .gitignore                        # modified: add Terraform ignores
├── Taskfile.yml                      # modified: add cluster:* tasks
├── terraform/
│   └── clusters/
│       ├── main.tf
│       ├── outputs.tf
│       ├── providers.tf
│       ├── variables.tf
│       ├── terraform.tfvars.example
│       ├── modules/
│       │   └── cluster/
│       │       ├── main.tf
│       │       ├── outputs.tf
│       │       └── variables.tf
│       └── templates/
│           └── kustomization.yaml
└── infrastructure/
    ├── openebs-localpv/
    │   ├── README.md
    │   └── argocd/appset.yaml
    ├── traefik-gateway/
    │   ├── README.md
    │   └── argocd/appset.yaml
    └── gateway-api-crds/
        ├── README.md
        └── argocd/appset.yaml
```

---

### Task 1: Migrate Terraform code from akp-infra

**Files:**
- Modify: `/Users/ada/src/github.com/adamancini/argo-fleet/.gitignore`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/terraform/clusters/main.tf`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/terraform/clusters/outputs.tf`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/terraform/clusters/providers.tf`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/terraform/clusters/variables.tf`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/terraform/clusters/terraform.tfvars.example`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/terraform/clusters/modules/cluster/main.tf`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/terraform/clusters/modules/cluster/outputs.tf`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/terraform/clusters/modules/cluster/variables.tf`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/terraform/clusters/templates/kustomization.yaml`

**Interfaces:**
- Produces: a `terraform/clusters/` stack, invoked from later tasks' Taskfile commands as `cd terraform/clusters && terraform apply -target='module.cluster["<name>"]'`. The module's `for_each = var.clusters` keys (`demo1`, `demo2`) are the exact strings the Taskfile's `cluster:*` tasks pass as `<name>`.

This is a verbatim copy — every file's content below is the real, current content of the corresponding file in `akp-infra/03-clusters`, read directly during planning.

- [ ] **Step 1: Write `terraform/clusters/providers.tf`**

```hcl
terraform {
  required_version = ">= 1.5"

  required_providers {
    akp = {
      source  = "akuity/akp"
      version = "~> 0.10"
    }
  }
}

# Authentication is via environment variables — never put credentials in files:
#   export AKUITY_API_KEY_ID=...
#   export AKUITY_API_KEY_SECRET=...
provider "akp" {
  org_name = var.org_name
}
```

- [ ] **Step 2: Write `terraform/clusters/variables.tf`**

```hcl
variable "org_name" {
  description = "Akuity Platform organization name"
  type        = string
}

variable "argocd_instance_name" {
  description = "Name of the Argo CD instance created by stack 01-argocd (looked up by name — no remote state needed)"
  type        = string
  default     = "quickstart-argocd"
}

variable "kargo_instance_name" {
  description = "Name of the Kargo instance created by stack 02-kargo (looked up by name — no remote state needed)"
  type        = string
  default     = "quickstart-kargo"
}

variable "clusters" {
  description = <<-EOT
    Workload clusters to register, keyed by cluster name.

    Per cluster:
      kubeconfig_path      — path to a kubeconfig file for the cluster (required).
                             Must use embedded client certificates; see the note
                             in modules/cluster/main.tf about exec-plugin
                             kubeconfigs (EKS/GKE/AKS).
      kubeconfig_context   — context to use; defaults to the file's
                             current-context, then the first context.
      size                 — Akuity agent size (default "small").
      labels               — Argo CD cluster labels. GOTCHA: register the
                             cluster with no fleet/addon labels first, confirm
                             the agent is healthy, THEN add labels that trigger
                             ApplicationSet generators (two-phase registration —
                             otherwise apps race a half-installed agent).
      tune_agent_resources — apply templates/kustomization.yaml to shrink agent
                             CPU requests. Recommended for small/local clusters
                             (k3d, kind, minikube) where default requests can
                             leave agent pods Pending.
  EOT
  type = map(object({
    kubeconfig_path      = string
    kubeconfig_context   = optional(string)
    size                 = optional(string, "small")
    labels               = optional(map(string), {})
    tune_agent_resources = optional(bool, false)
    # Kargo agent name; defaults to the cluster name. Override when adopting
    # an existing agent that was registered under a different name.
    kargo_agent_name = optional(string)
    # Set false to leave a pre-existing Kargo agent unmanaged (adoption
    # escape hatch — see docs/importing-existing.md).
    manage_kargo_agent = optional(bool, true)
    # Cluster registered outside Terraform and imported: skip the
    # agent-install kubeconfig and health gating so no update RPC is issued
    # (see docs/importing-existing.md).
    adopted = optional(bool, false)
  }))
}

variable "kargo_default_shard" {
  description = <<-EOT
    Optional: name of the cluster (a key of var.clusters) whose Kargo agent
    becomes the default shard — i.e. where Kargo runs promotion processes when
    a Stage doesn't specify a shard. Leave null to skip.
  EOT
  type        = string
  default     = null
}
```

- [ ] **Step 3: Write `terraform/clusters/main.tf`**

```hcl
# ── Look up the control-plane instances from stacks 01 and 02 ──────────────────
# Stacks are wired together by instance NAME via provider data sources, not
# terraform_remote_state — each stack stays independently applyable.

data "akp_instance" "argocd" {
  name = var.argocd_instance_name
}

data "akp_kargo_instance" "kargo" {
  name = var.kargo_instance_name
}

# ── Workload clusters ──────────────────────────────────────────────────────────
# One module instance per cluster. Each registration installs TWO agents into
# the cluster (namespace "akuity"):
#   - the Argo CD agent — pulls desired state from the hosted Argo CD instance
#     and applies it in-cluster (no inbound access to your cluster needed)
#   - the Kargo agent   — watches Warehouses/Stages and executes promotions,
#     linked back to Argo CD so promotions can trigger syncs

module "cluster" {
  for_each = var.clusters
  source   = "./modules/cluster"

  name                 = each.key
  kubeconfig_path      = each.value.kubeconfig_path
  kubeconfig_context   = each.value.kubeconfig_context
  size                 = each.value.size
  labels               = each.value.labels
  tune_agent_resources = each.value.tune_agent_resources
  kargo_agent_name     = each.value.kargo_agent_name
  manage_kargo_agent   = each.value.manage_kargo_agent
  adopted              = each.value.adopted
  kustomization_path   = "${path.module}/templates/kustomization.yaml"

  argocd_instance_id = data.akp_instance.argocd.id
  kargo_instance_id  = data.akp_kargo_instance.kargo.id
}

# ── Kargo default shard (optional) ─────────────────────────────────────────────
# Lives here rather than in 02-kargo because it must point at a registered
# workload-cluster agent, which only exists after this stack applies.

resource "akp_kargo_default_shard_agent" "default" {
  count = var.kargo_default_shard == null ? 0 : 1

  kargo_instance_id = data.akp_kargo_instance.kargo.id
  agent_id          = module.cluster[var.kargo_default_shard].kargo_agent_id

  depends_on = [module.cluster]
}
```

- [ ] **Step 4: Write `terraform/clusters/outputs.tf`**

```hcl
output "argocd_cluster_ids" {
  description = "Argo CD cluster registration IDs, keyed by cluster name"
  value       = { for name, mod in module.cluster : name => mod.argocd_cluster_id }
}

output "kargo_agent_ids" {
  description = "Kargo agent IDs, keyed by cluster name"
  value       = { for name, mod in module.cluster : name => mod.kargo_agent_id }
}

output "kargo_default_shard" {
  description = "Cluster whose Kargo agent is the default shard (null if not set)"
  value       = var.kargo_default_shard
}
```

- [ ] **Step 5: Write `terraform/clusters/modules/cluster/variables.tf`**

```hcl
variable "name" {
  description = "Cluster name as it will appear in Argo CD and Kargo"
  type        = string
}

variable "kubeconfig_path" {
  description = "Path to a kubeconfig file with embedded client certificates for this cluster"
  type        = string
}

variable "kubeconfig_context" {
  description = "Kubeconfig context to use. Defaults to the file's current-context, then the first context."
  type        = string
  default     = null
}

variable "size" {
  description = "Akuity agent size (small, medium, large)"
  type        = string
  default     = "small"
}

variable "labels" {
  description = "Argo CD cluster labels. Add ApplicationSet-triggering labels (e.g. fleet=true) only after the agent is healthy — see two-phase registration note in main.tf."
  type        = map(string)
  default     = {}
}

variable "tune_agent_resources" {
  description = "Apply the kustomization patch that shrinks agent CPU requests — recommended for small/local clusters (k3d, kind, minikube)"
  type        = bool
  default     = false
}

variable "adopted" {
  description = "This cluster was registered outside Terraform and imported. Skips the agent-install kubeconfig and health gating so adoption requires no update RPC (works around provider update bugs on imported clusters — see docs/importing-existing.md)."
  type        = bool
  default     = false
}

variable "manage_kargo_agent" {
  description = "Manage this cluster's Kargo agent with Terraform. Set false to adopt a cluster whose agent already exists outside Terraform (see docs/importing-existing.md)."
  type        = bool
  default     = true
}

variable "kargo_agent_name" {
  description = "Name for the Kargo agent. Defaults to the cluster name; override when adopting an existing agent registered under a different name."
  type        = string
  default     = null
}

variable "kustomization_path" {
  description = "Path to the kustomization.yaml applied to agent manifests when tune_agent_resources is true"
  type        = string
}

variable "argocd_instance_id" {
  description = "ID of the Akuity Argo CD instance to register this cluster with"
  type        = string
}

variable "kargo_instance_id" {
  description = "ID of the Akuity Kargo instance to register this cluster's Kargo agent with"
  type        = string
}
```

- [ ] **Step 6: Write `terraform/clusters/modules/cluster/main.tf`**

```hcl
terraform {
  required_providers {
    akp = {
      source  = "akuity/akp"
      version = "~> 0.10"
    }
  }
}

# ── Kubeconfig parsing ─────────────────────────────────────────────────────────
# The Akuity provider installs agents into the cluster itself, so it needs
# working credentials at plan/apply time.
#
# ASSUMPTION / GOTCHA: this module reads embedded client certificates
# (client-certificate-data / client-key-data) from the kubeconfig. That covers
# k3d, kind, minikube, k3s, and most on-prem distros. Managed-cloud kubeconfigs
# (EKS/GKE/AKS) usually use an exec plugin (aws/gke-gcloud-auth-plugin/kubelogin)
# instead — those have no cert data to extract. For such clusters, export a
# kubeconfig with static credentials (e.g. a service-account token) or extend
# this module to pass `token` in kube_config.

locals {
  kubeconfig = yamldecode(file(var.kubeconfig_path))

  # Resolve which context to use, in order of preference:
  #   1. explicit var.kubeconfig_context
  #   2. the file's current-context
  #   3. the first context in the file
  context_name = coalesce(
    var.kubeconfig_context,
    try(local.kubeconfig["current-context"], null),
    local.kubeconfig.contexts[0].name,
  )
  context = [for c in local.kubeconfig.contexts : c if c.name == local.context_name][0]
  cluster = [for c in local.kubeconfig.clusters : c if c.name == local.context.context.cluster][0]
  user    = [for u in local.kubeconfig.users : u if u.name == local.context.context.user][0]

  # GOTCHA: k3d (and other Docker-based clusters) bind the API server to
  # 0.0.0.0, which is not routable from the host running Terraform. Rewrite to
  # 127.0.0.1 so the provider can reach it. Harmless for real clusters, whose
  # server addresses never contain 0.0.0.0.
  host = replace(local.cluster.cluster.server, "0.0.0.0", "127.0.0.1")

  kube_config = {
    host                   = local.host
    cluster_ca_certificate = base64decode(local.cluster.cluster["certificate-authority-data"])
    client_certificate     = base64decode(local.user.user["client-certificate-data"])
    client_key             = base64decode(local.user.user["client-key-data"])
  }
}

# ── Argo CD cluster registration ───────────────────────────────────────────────
# Registers the cluster with the Argo CD instance. The provider uses the
# supplied kubeconfig to install the Akuity agent into the "akuity" namespace;
# from then on the agent dials OUT to the control plane — no inbound access,
# no long-lived kubeconfig on the platform.

resource "akp_cluster" "this" {
  instance_id = var.argocd_instance_id
  name        = var.name
  namespace   = "akuity"

  # GOTCHA (two-phase fleet registration): keep this empty on first apply.
  # Labels like fleet=true typically feed ApplicationSet generators; if you
  # label the cluster before its agent is healthy, apps start syncing into a
  # half-installed agent. Apply once, verify the agent is healthy, then add
  # labels in a second apply. See docs/day-2.md.
  labels = var.labels

  spec = {
    # Explicit rather than defaulted: namespace_scoped forces REPLACEMENT when
    # it differs, and the platform stores `false` — leaving it unset makes
    # `terraform import` of an existing registration plan a destroy/recreate.
    # description/project: the platform normalizes unset strings to "", so
    # explicit "" keeps imported resources at zero diff.
    namespace_scoped = false
    description      = ""

    data = {
      size    = var.size
      project = ""

      # GOTCHA: on small/local clusters (k3d, kind, minikube) the default agent
      # CPU requests can exceed what's schedulable and leave pods Pending. The
      # kustomization patch shrinks argocd-application-controller and
      # argocd-repo-server requests so the agent fits.
      kustomization = var.tune_agent_resources ? file(var.kustomization_path) : null
    }
  }

  # Adopted clusters: no kube_config and no health gate, so the plan exactly
  # matches imported state and no update RPC is issued.
  kube_config = var.adopted ? null : local.kube_config

  # GOTCHA: ensure_healthy makes the apply BLOCK until the agent reports
  # healthy on the platform — so a successful apply means a live agent, and
  # stack ordering (03 after 01/02) is genuinely sequential. If the apply hangs
  # here, the agent pods are the first place to look:
  #   kubectl -n akuity get pods
  ensure_healthy = var.adopted ? false : true
}

# ── Kargo agent registration ───────────────────────────────────────────────────
# Self-hosted Kargo agent (akuity_managed = false): it runs inside this
# cluster and executes promotion steps locally. remote_argocd links Kargo
# promotions to Argo CD syncs — after Kargo writes a promotion to Git, it can
# observe/trigger the corresponding Argo CD Application on this instance.

resource "akp_kargo_agent" "this" {
  # manage_kargo_agent = false skips this resource — for adopting a cluster
  # whose Kargo agent already exists but cannot be imported (see the known
  # provider issue in docs/importing-existing.md: the agent read resolves the
  # wrong workspace and fails with PermissionDenied).
  count = var.manage_kargo_agent ? 1 : 0

  instance_id                 = var.kargo_instance_id
  workspace                   = "default"
  name                        = coalesce(var.kargo_agent_name, var.name)
  namespace                   = "akuity"
  reapply_manifests_on_update = true

  spec = {
    description = "Workload cluster: ${var.name}"
    data = {
      size           = var.size
      akuity_managed = false
      remote_argocd  = var.argocd_instance_id
    }
  }

  kube_config = local.kube_config

  # Install the Kargo agent only after the Argo CD agent is in and healthy —
  # both land in the same "akuity" namespace.
  depends_on = [akp_cluster.this]
}
```

- [ ] **Step 7: Write `terraform/clusters/modules/cluster/outputs.tf`**

```hcl
output "argocd_cluster_id" {
  description = "Argo CD cluster registration ID"
  value       = akp_cluster.this.id
}

output "kargo_agent_id" {
  description = "Kargo agent ID — used by the root stack to set the default shard. Null when manage_kargo_agent = false."
  value       = try(akp_kargo_agent.this[0].id, null)
}
```

- [ ] **Step 8: Write `terraform/clusters/templates/kustomization.yaml`**

```yaml
# Reduces CPU requests for the Akuity agent components so they schedule
# comfortably on small/local clusters (k3d, kind, minikube). Applied to agent
# manifests when a cluster sets tune_agent_resources = true.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
patches:
  - target:
      group: apps
      version: v1
      kind: Deployment
      name: argocd-application-controller
      namespace: akuity
    patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: argocd-application-controller
        namespace: akuity
      spec:
        template:
          spec:
            containers:
              - name: syncer
                resources:
                  requests:
                    cpu: 50m
              - name: argocd-application-controller
                resources:
                  requests:
                    cpu: 100m
  - target:
      group: apps
      version: v1
      kind: Deployment
      name: argocd-repo-server
      namespace: akuity
    patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: argocd-repo-server
        namespace: akuity
      spec:
        template:
          spec:
            replicas: 1
            containers:
              - name: argocd-repo-server
                resources:
                  requests:
                    cpu: 50m
```

- [ ] **Step 9: Write `terraform/clusters/terraform.tfvars.example`**

```hcl
# Copy to terraform.tfvars and fill in your values.
# terraform.tfvars is gitignored — never commit it.

org_name = "example-org"

# Must match the instances created by akp-infra's 01-argocd and 02-kargo
# stacks (looked up by name).
argocd_instance_name = "quickstart-argocd"
kargo_instance_name  = "quickstart-kargo"

# Workload clusters to register. Kubeconfigs stay on your machine and are
# gitignored (keep them under .kubeconfigs/ if you copy them into this repo).
clusters = {
  demo1 = {
    kubeconfig_path      = ".kubeconfigs/demo1.yaml"
    tune_agent_resources = true # recommended for k3d/kind/minikube
  }
  # demo2 = {
  #   kubeconfig_path    = ".kubeconfigs/demo2.yaml"
  #   kubeconfig_context = "k3d-demo2"   # optional; defaults to current-context
  #   size               = "small"
  #   # GOTCHA: add fleet/addon labels only AFTER the first apply succeeds and
  #   # the agent shows healthy — two-phase registration (see docs/day-2.md).
  #   # labels           = { fleet = "true" }
  # }
}

# Optional: which cluster's Kargo agent runs promotions by default.
kargo_default_shard = "demo1"
```

- [ ] **Step 10: Add Terraform ignores to the root `.gitignore`**

Read the current file first, then add these lines (same patterns `akp-infra` uses):

```gitignore
terraform/clusters/.terraform/
terraform/clusters/*.tfstate
terraform/clusters/*.tfstate.*
terraform/clusters/*.tfvars
!terraform/clusters/*.tfvars.example
terraform/clusters/.kubeconfigs/
```

- [ ] **Step 11: Validate HCL syntax**

Run: `cd /Users/ada/src/github.com/adamancini/argo-fleet/terraform/clusters && terraform fmt -check -recursive`
Expected: no output (all files already correctly formatted — this is a verbatim copy of already-formatted source). If it reports unformatted files, run `terraform fmt -recursive` and inspect the diff before proceeding — a formatting-only change is fine, anything else means a transcription error.

- [ ] **Step 12: Commit**

```bash
cd /Users/ada/src/github.com/adamancini/argo-fleet
git add .gitignore terraform/
git commit -m "Migrate cluster/agent registration Terraform from akp-infra"
```

---

### Task 2: Taskfile cluster lifecycle tasks

**Files:**
- Modify: `/Users/ada/src/github.com/adamancini/argo-fleet/Taskfile.yml`

**Interfaces:**
- Consumes: `terraform/clusters/` from Task 1 (the `cluster:register-agent` task's `terraform apply` call).
- Produces: `task cluster:create -- <name>`, `task cluster:delete -- <name>`, `task cluster:recreate -- <name>`, `task cluster:register-agent -- <name>` — the exact commands Task 7 (live execution) runs.

- [ ] **Step 1: Read the current `Taskfile.yml`**

It currently has one `vars:` block and the three `sealed-secrets:*` tasks. Note the existing `CLUSTERS: k3d-demo1 k3d-demo2` var — that's the full kubectl context names, used by the sealed-secrets tasks. The new tasks below take a **bare** cluster name (`demo1`, not `k3d-demo1`) as their argument, since that's what `k3d cluster create/delete` and Terraform's `var.clusters` map both expect natively — don't conflate the two forms.

- [ ] **Step 2: Add the `TERRAFORM_CLUSTERS_DIR` var**

Add this to the existing `vars:` block (alongside `KEYPAIR_DIR` etc.):

```yaml
  TERRAFORM_CLUSTERS_DIR: '{{.ROOT_DIR}}/terraform/clusters'
```

- [ ] **Step 3: Add `cluster:create`**

```yaml
  cluster:create:
    desc: 'Create a k3d cluster for use as an Akuity workload cluster, with the bundled Traefik and local-path-provisioner disabled. Usage: task cluster:create -- <name>'
    cmds:
      - |
        k3d cluster create {{index .CLI_ARGS_LIST 0}} \
          --k3s-arg "--disable=traefik@server:0" \
          --k3s-arg "--disable=local-storage@server:0"
```

- [ ] **Step 4: Add `cluster:delete`**

```yaml
  cluster:delete:
    desc: 'Delete a k3d cluster. Usage: task cluster:delete -- <name>'
    cmds:
      - k3d cluster delete {{index .CLI_ARGS_LIST 0}}
```

- [ ] **Step 5: Add `cluster:recreate`**

Delete then create, with both k3d commands inlined directly rather than calling the two tasks above via nested `task:` calls — `CLI_ARGS_LIST` forwarding across nested task invocations hasn't been exercised anywhere in this repo, and getting `CLI_ARGS`/`CLI_ARGS_LIST` handling wrong already caused a real bug once (see the `sealed-secrets:seal` fix history in this repo's git log). Inlining avoids relying on that forwarding at all.

```yaml
  cluster:recreate:
    desc: 'Delete and recreate a k3d cluster cleanly (no bundled Traefik/local-path). Usage: task cluster:recreate -- <name>'
    cmds:
      - k3d cluster delete {{index .CLI_ARGS_LIST 0}} 2>/dev/null || true
      - |
        k3d cluster create {{index .CLI_ARGS_LIST 0}} \
          --k3s-arg "--disable=traefik@server:0" \
          --k3s-arg "--disable=local-storage@server:0"
```

- [ ] **Step 6: Add `cluster:register-agent`**

```yaml
  cluster:register-agent:
    desc: 'Export a cluster kubeconfig and apply its Argo CD/Kargo agent registration via Terraform. Usage: task cluster:register-agent -- <name>'
    cmds:
      - k3d kubeconfig get {{index .CLI_ARGS_LIST 0}} > {{.TERRAFORM_CLUSTERS_DIR}}/.kubeconfigs/{{index .CLI_ARGS_LIST 0}}.yaml
      - cd {{.TERRAFORM_CLUSTERS_DIR}} && terraform apply -target='module.cluster["{{index .CLI_ARGS_LIST 0}}"]'
```

- [ ] **Step 7: Validate YAML syntax**

Run: `ruby -ryaml -e "YAML.load_stream(File.read('/Users/ada/src/github.com/adamancini/argo-fleet/Taskfile.yml'))" && echo OK`
Expected: `OK`

- [ ] **Step 8: Verify `task --list` shows all seven tasks**

Run: `cd /Users/ada/src/github.com/adamancini/argo-fleet && task --list`
Expected: output includes the three existing `sealed-secrets:*` tasks plus `cluster:create`, `cluster:delete`, `cluster:recreate`, `cluster:register-agent`, each with its `desc:` text.

- [ ] **Step 9: Commit**

```bash
git add Taskfile.yml
git commit -m "Add cluster lifecycle Taskfile tasks: create, delete, recreate, register-agent"
```

---

### Task 3: `infrastructure/openebs-localpv`

**Files:**
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/infrastructure/openebs-localpv/argocd/appset.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/infrastructure/openebs-localpv/README.md`

**Interfaces:**
- Consumes: `infra-apps.yaml`'s discovery of `infrastructure/*/argocd` (already exists, from the prior plan's Task 3).
- Produces: a `local-path` StorageClass (`rancher.io`... no — `openebs.io`-backed, name `local-path`, not default) on `demo1`/`demo2`, once Task 7 recreates the clusters without k3s's own `local-path` and this Application syncs.

- [ ] **Step 1: Write `infrastructure/openebs-localpv/argocd/appset.yaml`**

```yaml
# One Application per cluster, installing OpenEBS's Dynamic LocalPV
# Provisioner. Mirrors fleet-infra's real-cluster setup: the StorageClass is
# named "local-path" (matching what k3s's bundled provisioner used to
# provide, before Task 7 disables it) but is NOT the default class -- that
# choice stays explicit rather than implicit.
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

- [ ] **Step 2: Write `infrastructure/openebs-localpv/README.md`**

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

- [ ] **Step 3: Validate YAML syntax**

Run: `ruby -ryaml -e "YAML.load_stream(File.read('/Users/ada/src/github.com/adamancini/argo-fleet/infrastructure/openebs-localpv/argocd/appset.yaml'))" && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add infrastructure/openebs-localpv/
git commit -m "Add openebs-localpv infra layer for demo1/demo2"
```

---

### Task 4: `infrastructure/traefik-gateway`

**Files:**
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/infrastructure/traefik-gateway/argocd/appset.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/infrastructure/traefik-gateway/README.md`

**Interfaces:**
- Consumes: `infra-apps.yaml`'s discovery of `infrastructure/*/argocd`.
- Produces: a `traefik-gateway` `Gateway` resource (in the `traefik` namespace on each cluster) that a later app's `HTTPRoute` can reference via `parentRefs: - name: traefik-gateway namespace: traefik` — the exact reference shape already used by `fleet-infra`'s `soju` route. Not consumed by any task in this plan (akkoma/soju's own `HTTPRoute` wiring is explicitly deferred).

- [ ] **Step 1: Write `infrastructure/traefik-gateway/argocd/appset.yaml`**

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

- [ ] **Step 2: Write `infrastructure/traefik-gateway/README.md`**

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
  domains yet (see the design spec in `docs/superpowers/specs/`).
- Any actual `HTTPRoute` for `akkoma`/`soju` -- they still use placeholder
  domains and `ingress.enabled: false`. Wiring them to this Gateway is a
  follow-up once real domains exist, not part of this layer.

## Prerequisite

Same as `openebs-localpv`: k3s's own bundled Traefik must be gone first
(`task cluster:recreate` disables it via
`--k3s-arg "--disable=traefik@server:0"`), or this Application's
`IngressClass`/`Gateway` objects collide with k3s's own.
```

- [ ] **Step 3: Validate YAML syntax**

Run: `ruby -ryaml -e "YAML.load_stream(File.read('/Users/ada/src/github.com/adamancini/argo-fleet/infrastructure/traefik-gateway/argocd/appset.yaml'))" && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add infrastructure/traefik-gateway/
git commit -m "Add traefik-gateway infra layer for demo1/demo2"
```

---

### Task 5: `infrastructure/gateway-api-crds`

**Files:**
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/infrastructure/gateway-api-crds/argocd/appset.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/infrastructure/gateway-api-crds/README.md`

**Interfaces:**
- Consumes: `infra-apps.yaml`'s discovery of `infrastructure/*/argocd`.
- Produces: the `Gateway`/`HTTPRoute`/`GatewayClass` CRDs that Task 4's `traefik-gateway` Application needs to exist before Traefik can create its `Gateway` object. No explicit ordering is declared between the two Applications in this plan — see the note in this task's README about sync-wave ordering being a Task 7 concern, not a file-authoring one.

- [ ] **Step 1: Write `infrastructure/gateway-api-crds/argocd/appset.yaml`**

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

- [ ] **Step 2: Write `infrastructure/gateway-api-crds/README.md`**

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
needed, just a one-time delay on the very first sync after Task 7.
```

- [ ] **Step 3: Validate YAML syntax**

Run: `ruby -ryaml -e "YAML.load_stream(File.read('/Users/ada/src/github.com/adamancini/argo-fleet/infrastructure/gateway-api-crds/argocd/appset.yaml'))" && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add infrastructure/gateway-api-crds/
git commit -m "Add gateway-api-crds infra layer for demo1/demo2"
```

---

### Task 6: Full static verification (no live cluster mutation)

**Files:** none created; this task only validates Tasks 1-5.

- [ ] **Step 1: YAML-syntax-validate every new/modified YAML file**

Run:
```bash
cd /Users/ada/src/github.com/adamancini/argo-fleet
for f in infrastructure/openebs-localpv/argocd/appset.yaml \
         infrastructure/traefik-gateway/argocd/appset.yaml \
         infrastructure/gateway-api-crds/argocd/appset.yaml \
         Taskfile.yml; do
  ruby -ryaml -e "YAML.load_stream(File.read('$f'))" && echo "OK $f" || echo "FAIL $f"
done
```
Expected: `OK` for all four.

- [ ] **Step 2: Validate the migrated Terraform (`terraform validate`, not `plan` — no state touched)**

Run:
```bash
cd /Users/ada/src/github.com/adamancini/argo-fleet/terraform/clusters
terraform init -backend=false
terraform validate
```
Expected: `Success! The configuration is valid.` `-backend=false` and no `terraform.tfvars` present at this point means this only checks HCL correctness and provider schema compatibility — it does not read or write any state, and does not require real credentials.

- [ ] **Step 3: Confirm the migrated Terraform is byte-identical to its source**

Run:
```bash
diff -rq /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/main.tf terraform/clusters/main.tf
diff -rq /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/outputs.tf terraform/clusters/outputs.tf
diff -rq /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/providers.tf terraform/clusters/providers.tf
diff -rq /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/variables.tf terraform/clusters/variables.tf
diff -rq /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/modules/cluster terraform/clusters/modules/cluster
diff -rq /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/templates/kustomization.yaml terraform/clusters/templates/kustomization.yaml
```
Expected: no output from any `diff` (identical files). If Task 1's Step 11 ran `terraform fmt -recursive` and it reformatted anything, this step will show whitespace-only differences — acceptable; anything beyond whitespace means a transcription error and must be fixed before continuing.

- [ ] **Step 4: Cross-check chart versions against the real chart repos**

Run:
```bash
helm search repo openebs-localpv/localpv-provisioner --version 4.5.1
helm search repo traefik/traefik --version 41.1.1
```
(Both repos were already added locally during planning; if this errors with "no repositories configured," run `helm repo add openebs-localpv https://openebs.github.io/dynamic-localpv-provisioner && helm repo add traefik https://traefik.github.io/charts && helm repo update` first.)
Expected: each command prints exactly one matching row — confirms the pinned versions in `infrastructure/openebs-localpv/argocd/appset.yaml` and `infrastructure/traefik-gateway/argocd/appset.yaml` are real, currently-published chart versions, not typos.

- [ ] **Step 5: Confirm no task so far touched a live cluster or real Terraform state**

Run: `git log --oneline`
Expected: commit messages match Tasks 1-5 only (Terraform migration, cluster Taskfile tasks, three infra layers) — nothing about creating/deleting/recreating a k3d cluster, applying Terraform against real state, or touching `akp-infra`. This confirms the Global Constraint (no live mutation except in Task 7) was honored.

---

### Task 7: Live execution — recreate demo1/demo2 and re-register (HUMAN-RUN, NOT AUTOMATED)

**This task is not implemented by writing files. It is a sequence of commands a human runs themselves, one at a time, with two explicit stop-and-verify gates. If you are an autonomous agent executing this plan task-by-task, stop here and report back instead of running these commands.**

**Files:** none. This task only runs commands against real infrastructure.

Everything below assumes Tasks 1-6 are complete, committed, and pushed.

- [ ] **Step 1: Confirm you're prepared to lose what's currently on demo1/demo2**

`demo1` currently runs: the entire `akp-platform` demo environment (`guestbook-helm`, `guestbook-helm-rendered`, `guestbook-kustomize`, `guestbook-rendered` — each with dev/staging/prod namespaces) plus `rollouts-app` (dev/staging). `demo2` runs `rollouts-app` (prod). Both run the Akuity agent stack in the `akuity` namespace. Recreating the k3d cluster destroys all of it. Re-deploying `akp-platform`'s demo apps afterward is `argocd app create -f bootstrap/platform-aoa.yaml` from that repo, run manually — not something this plan automates.

Do not proceed past this step without having actually decided this is acceptable right now.

- [ ] **Step 2: Recreate demo1**

```bash
cd /Users/ada/src/github.com/adamancini/argo-fleet
task cluster:recreate -- demo1
```

- [ ] **Step 3: Re-register demo1**

```bash
task cluster:register-agent -- demo1
```

This blocks until the Argo CD agent reports healthy (the Terraform module's `ensure_healthy = true`) or times out. If it times out, check `kubectl --context k3d-demo1 -n akuity get pods` before retrying — per the migrated module's own comment, agent pods stuck `Pending` on a small cluster usually means `tune_agent_resources` isn't taking effect; confirm `terraform/clusters/terraform.tfvars` has `tune_agent_resources = true` for `demo1` (copy the value from `akp-infra/03-clusters/terraform.tfvars` if `terraform/clusters/terraform.tfvars` doesn't exist yet — it's gitignored, so Task 1 never created it).

- [ ] **Step 4: Repeat for demo2**

```bash
task cluster:recreate -- demo2
task cluster:register-agent -- demo2
```

- [ ] **Step 5: STOP — verify both agents are healthy before touching anything in akp-infra**

```bash
kubectl --context k3d-demo1 -n akuity get pods
kubectl --context k3d-demo2 -n akuity get pods
```

Expected: `akuity-agent`, `argocd-application-controller`, `argocd-repo-server`, `kargo-controller-*`, `kargo-promotion-controller-*`, `kargo-webhook` all `Running` on both. Do not proceed to Step 6 until this is true on both clusters — this is the human-verification gate the design spec requires before the old registration is touched.

- [ ] **Step 6: STOP — confirm zero Terraform drift, then retire the old state**

From the **new** location, confirm nothing unexpected is pending:

```bash
cd /Users/ada/src/github.com/adamancini/argo-fleet/terraform/clusters
terraform plan
```

Expected: `No changes.` (both clusters were just freshly applied in Steps 3/4, so this should be a no-op). Only once this is confirmed, retire the old registration so `akp-infra/03-clusters` can never be applied against these clusters again:

```bash
mv /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/terraform.tfstate \
   /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/terraform.tfstate.superseded-by-argo-fleet
mv /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/terraform.tfstate.backup \
   /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/terraform.tfstate.backup.superseded-by-argo-fleet
```

(Renaming rather than deleting — the old state remains on disk as a record, just no longer a filename Terraform will pick up automatically.)

- [ ] **Step 7: Sync the new infra layers**

Once `demo1`/`demo2` are registered and `bootstrap/infra-apps.yaml` (already deployed from the prior plan) has discovered `infrastructure/gateway-api-crds/`, `infrastructure/openebs-localpv/`, and `infrastructure/traefik-gateway/`, confirm all three Applications go `Synced`/`Healthy` per cluster via the Argo CD UI or `argocd app list`. Per Task 5's README, `traefik-gateway` may show one failed sync attempt before `gateway-api-crds` lands — `selfHeal` retries it automatically; only investigate further if it's still failing after both are `Synced`.

- [ ] **Step 8: Re-deploy akp-platform's demo apps (if you want demo1's guestbook apps back)**

```bash
argocd app create -f /Users/ada/src/github.com/adamancini/akp-platform/bootstrap/platform-aoa.yaml
```

This is `akp-platform`'s own bootstrap, unrelated to anything in this plan — included here only because Step 1 named it as the thing destroyed.
