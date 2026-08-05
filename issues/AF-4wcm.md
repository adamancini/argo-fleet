---
id: AF-4wcm
title: "Migrate cluster/agent registration Terraform from akp-infra into argo-fleet"
status: closed
priority: 0
type: task
labels: [walking-skeleton, accepted]
parent: AF-q1il
created_at: 2026-08-05T14:29:16Z
created_by: ada
updated_at: 2026-08-05T15:15:13Z
content_hash: "sha256:5ad8d5941a8b43e2b8fdfe50d261098bce110b96ef958b3a8dca5d66449d1fdc"
assignee: dev-AF-4wcm
closed_at: 2026-08-05T15:15:12Z
close_reason: "Accepted via pvg story accept"
---

## Description
Description:
Migrate the cluster/agent registration Terraform stack from the sibling
repo `akp-infra` (`03-clusters`) into this repo at
`terraform/clusters/`, as a verbatim file copy plus the gitignore hygiene
that keeps its state/secrets out of git. This is the walking skeleton for
the whole epic: it establishes the quality-gate pattern every later story
in this epic copies -- never commit Terraform state or credentials, always
statically validate syntax before committing, and preserve byte-for-byte
fidelity to the source when copying already-approved code.

Context:
`akp-infra/03-clusters` is real, currently-applied Terraform: its
`terraform.tfstate` almost certainly contains the real kubeconfig
client-certificate/key material for `demo1`/`demo2` as tracked resource
attributes (Terraform's `sensitive` flag only masks CLI output -- it does
not encrypt state at rest). This story ONLY copies the Terraform *code*
(the `.tf`/`.yaml`/`.example` files below) -- it does NOT touch, copy, or
read `akp-infra/03-clusters/terraform.tfstate*` or
`akp-infra/03-clusters/terraform.tfvars` (the real, filled-in vars file,
which is gitignored in `akp-infra` and stays there). No live cluster is
touched and no real credentials are read by this story. The actual
re-registration against real clusters (which does need real credentials
and does touch live state) is a separate, human-gated story
(`AF-<task7>`, "Recreate demo1/demo2..."; see this story's PRODUCES for
what that story consumes).

Per the design spec's Terraform-migration section: because both clusters
are being recreated anyway later in this epic, there is no Terraform state
to migrate -- registering fresh from the new location (once the clusters
are recreated) is simpler and safer than moving live state across repos.
This story is purely the code-copy half of that plan; the "recreate and
re-register" half is a separate, gated story.

USER INTENT:
The person running this repo needs to trust that copying Terraform code
between repos never accidentally exposes credentials or state, and that
the copy is provably identical to the already-reviewed source -- not a
transcription with subtle differences that only surface later when
`terraform apply` runs against real infrastructure. "Done" here means: the
code exists in the new location, is provably faithful to its source, is
syntactically valid, and cannot leak secrets via git.

Quality-gate patterns this walking skeleton establishes for every later
story in this epic: config registration (`variables.tf` in both the root
and `modules/cluster/` is exactly where this stack's configuration surface
-- `org_name`, `clusters`, `kargo_default_shard`, per-cluster overrides --
is declared and typed; every later story that touches this stack registers
new configuration the same way, as a typed Terraform variable, not an
undeclared magic string); and error handling (this story's own validation
steps -- `terraform fmt -check`, `terraform validate`, `diff -rq` -- are
designed to surface a transcription error or HCL mistake immediately and
loudly, rather than letting it surface later as a confusing `terraform
apply` failure against real infrastructure).

IMPLEMENTATION:
Create the following files with EXACTLY this content (verbatim copy of
the real, current content of the corresponding file in
`akp-infra/03-clusters`, already read and confirmed to exist at those
paths during planning):

File: terraform/clusters/providers.tf
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

File: terraform/clusters/variables.tf
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

File: terraform/clusters/main.tf
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

File: terraform/clusters/outputs.tf
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

File: terraform/clusters/modules/cluster/variables.tf
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

File: terraform/clusters/modules/cluster/main.tf
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

File: terraform/clusters/modules/cluster/outputs.tf
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

File: terraform/clusters/templates/kustomization.yaml
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

File: terraform/clusters/terraform.tfvars.example
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

Modify: root `.gitignore` -- read the current file first (it currently has
`.DS_Store`, `*.swp`, `.worktrees/`, `.superpowers/`, `/.task/`,
`/.sealed-secrets-keypair/`), then append these lines (same patterns
`akp-infra` uses for the identical directory shape):
```gitignore
terraform/clusters/.terraform/
terraform/clusters/*.tfstate
terraform/clusters/*.tfstate.*
terraform/clusters/*.tfvars
!terraform/clusters/*.tfvars.example
terraform/clusters/.kubeconfigs/
```

Validation (run these before committing; this establishes the quality-gate
pattern -- gitignore hygiene checked, syntax checked, fidelity checked --
that every later story in this epic re-applies):
1. `cd terraform/clusters && terraform fmt -check -recursive` -- expect no
   output (all files already correctly formatted, verbatim copy of
   already-formatted source). If it reports unformatted files, run
   `terraform fmt -recursive` and inspect the diff -- a formatting-only
   change is fine; anything else is a transcription error and must be
   fixed before proceeding.
2. Confirm byte-identical fidelity against source:
   `diff -rq /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/main.tf terraform/clusters/main.tf`
   (repeat for `outputs.tf`, `providers.tf`, `variables.tf`,
   `modules/cluster/`, `templates/kustomization.yaml`) -- expect no output
   from any `diff` (identical files, or whitespace-only if step 1 reformatted).
3. Confirm no secrets committed: `git status` after staging must show only
   `.gitignore` and the new `terraform/clusters/**/*.tf`,
   `**/*.tfvars.example`, `**/*.yaml` files -- never `terraform.tfstate*`,
   `terraform.tfvars` (without `.example`), or anything under
   `.kubeconfigs/`.

KEY FILES:
- Create: terraform/clusters/providers.tf
- Create: terraform/clusters/variables.tf
- Create: terraform/clusters/main.tf
- Create: terraform/clusters/outputs.tf
- Create: terraform/clusters/modules/cluster/variables.tf
- Create: terraform/clusters/modules/cluster/main.tf
- Create: terraform/clusters/modules/cluster/outputs.tf
- Create: terraform/clusters/templates/kustomization.yaml
- Create: terraform/clusters/terraform.tfvars.example
- Modify: .gitignore

PRODUCES:
- terraform/clusters/ -> a Terraform stack with root module `for_each =
  var.clusters` keyed by cluster name (keys used: "demo1", "demo2"),
  invoked as `terraform apply -target='module.cluster["<name>"]'` from
  within `terraform/clusters/`. Root outputs: `argocd_cluster_ids` (map,
  name -> Argo CD cluster registration ID), `kargo_agent_ids` (map, name ->
  Kargo agent ID), `kargo_default_shard` (string or null).
  source: docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
  Task 1 "Interfaces" section (verified against the live akp-infra/03-clusters
  source files, read directly during story authoring).
- .gitignore -> appended Terraform ignore patterns for
  `terraform/clusters/.terraform/`, `*.tfstate*`, `*.tfvars` (except
  `*.tfvars.example`), `.kubeconfigs/`.

TESTING:
Static validation only -- no unit/integration test framework applies to a
Terraform code copy. Coverage requirement: every command in the
IMPLEMENTATION "Validation" list above must be run and its actual output
recorded as proof (not just claimed) before this story is marked delivered.
This story does not run `terraform init` against a real backend, does not
read real credentials, and does not touch `akp-infra/03-clusters/terraform.tfstate*`
or `akp-infra/03-clusters/terraform.tfvars` in any way.

Acceptance Criteria:
1. [Ubiquitous] All nine files listed in IMPLEMENTATION exist at the exact
   paths listed, with content byte-identical (modulo `terraform fmt`
   whitespace) to their `akp-infra/03-clusters` source.
2. [Event] `terraform fmt -check -recursive` run from `terraform/clusters/`
   produces no output (or, if it reformats, the diff is whitespace-only).
3. [Event] `diff -rq` against every corresponding source file in
   `akp-infra/03-clusters` produces no output (or whitespace-only diffs).
4. [Ubiquitous] Root `.gitignore` gains the six Terraform ignore lines
   listed in IMPLEMENTATION, verified present via `grep -F` after the edit.
5. [Unwanted] This story shall not read, copy, modify, or commit
   `akp-infra/03-clusters/terraform.tfstate`,
   `akp-infra/03-clusters/terraform.tfstate.backup`, or
   `akp-infra/03-clusters/terraform.tfvars` (the real, filled-in vars file)
   under any circumstance.
6. [Unwanted] `git status` after staging this story's changes shall show
   no file matching `*.tfstate*`, a bare `*.tfvars` (non-`.example`), or
   anything under `.kubeconfigs/` -- byte-identical secrets-committed check
   confirmed via `git status` and `git diff --stat` output recorded as
   proof.
7. [Event] `cd terraform/clusters && terraform init -backend=false &&
   terraform validate` (run without a `terraform.tfvars` present) succeeds
   with "Success! The configuration is valid." -- confirms HCL correctness
   without touching any state or requiring real credentials.

MANDATORY SKILLS TO REVIEW:
None identified (Terraform file copy + static validation; no
project-specific skill covers Terraform/HCL in this repo).

# Authentication is via environment variables — never put credentials in files:
#   export AKUITY_API_KEY_ID=...
#   export AKUITY_API_KEY_SECRET=...
provider "akp" {
  org_name = var.org_name
}
```

File: terraform/clusters/variables.tf
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

File: terraform/clusters/main.tf
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

File: terraform/clusters/outputs.tf
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

File: terraform/clusters/modules/cluster/variables.tf
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

File: terraform/clusters/modules/cluster/main.tf
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

File: terraform/clusters/modules/cluster/outputs.tf
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

File: terraform/clusters/templates/kustomization.yaml
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

File: terraform/clusters/terraform.tfvars.example
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

Modify: root `.gitignore` -- read the current file first (it currently has
`.DS_Store`, `*.swp`, `.worktrees/`, `.superpowers/`, `/.task/`,
`/.sealed-secrets-keypair/`), then append these lines (same patterns
`akp-infra` uses for the identical directory shape):
```gitignore
terraform/clusters/.terraform/
terraform/clusters/*.tfstate
terraform/clusters/*.tfstate.*
terraform/clusters/*.tfvars
!terraform/clusters/*.tfvars.example
terraform/clusters/.kubeconfigs/
```

Validation (run these before committing; this establishes the quality-gate
pattern -- gitignore hygiene checked, syntax checked, fidelity checked --
that every later story in this epic re-applies):
1. `cd terraform/clusters && terraform fmt -check -recursive` -- expect no
   output (all files already correctly formatted, verbatim copy of
   already-formatted source). If it reports unformatted files, run
   `terraform fmt -recursive` and inspect the diff -- a formatting-only
   change is fine; anything else is a transcription error and must be
   fixed before proceeding.
2. Confirm byte-identical fidelity against source:
   `diff -rq /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/main.tf terraform/clusters/main.tf`
   (repeat for `outputs.tf`, `providers.tf`, `variables.tf`,
   `modules/cluster/`, `templates/kustomization.yaml`) -- expect no output
   from any `diff` (identical files, or whitespace-only if step 1 reformatted).
3. Confirm no secrets committed: `git status` after staging must show only
   `.gitignore` and the new `terraform/clusters/**/*.tf`,
   `**/*.tfvars.example`, `**/*.yaml` files -- never `terraform.tfstate*`,
   `terraform.tfvars` (without `.example`), or anything under
   `.kubeconfigs/`.

KEY FILES:
- Create: terraform/clusters/providers.tf
- Create: terraform/clusters/variables.tf
- Create: terraform/clusters/main.tf
- Create: terraform/clusters/outputs.tf
- Create: terraform/clusters/modules/cluster/variables.tf
- Create: terraform/clusters/modules/cluster/main.tf
- Create: terraform/clusters/modules/cluster/outputs.tf
- Create: terraform/clusters/templates/kustomization.yaml
- Create: terraform/clusters/terraform.tfvars.example
- Modify: .gitignore

PRODUCES:
- terraform/clusters/ -> a Terraform stack with root module `for_each =
  var.clusters` keyed by cluster name (keys used: "demo1", "demo2"),
  invoked as `terraform apply -target='module.cluster["<name>"]'` from
  within `terraform/clusters/`. Root outputs: `argocd_cluster_ids` (map,
  name -> Argo CD cluster registration ID), `kargo_agent_ids` (map, name ->
  Kargo agent ID), `kargo_default_shard` (string or null).
  source: docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
  Task 1 "Interfaces" section (verified against the live akp-infra/03-clusters
  source files, read directly during story authoring).
- .gitignore -> appended Terraform ignore patterns for
  `terraform/clusters/.terraform/`, `*.tfstate*`, `*.tfvars` (except
  `*.tfvars.example`), `.kubeconfigs/`.

TESTING:
Static validation only -- no unit/integration test framework applies to a
Terraform code copy. Coverage requirement: every command in the
IMPLEMENTATION "Validation" list above must be run and its actual output
recorded as proof (not just claimed) before this story is marked delivered.
This story does not run `terraform init` against a real backend, does not
read real credentials, and does not touch `akp-infra/03-clusters/terraform.tfstate*`
or `akp-infra/03-clusters/terraform.tfvars` in any way.

Acceptance Criteria:
1. [Ubiquitous] All nine files listed in IMPLEMENTATION exist at the exact
   paths listed, with content byte-identical (modulo `terraform fmt`
   whitespace) to their `akp-infra/03-clusters` source.
2. [Event] `terraform fmt -check -recursive` run from `terraform/clusters/`
   produces no output (or, if it reformats, the diff is whitespace-only).
3. [Event] `diff -rq` against every corresponding source file in
   `akp-infra/03-clusters` produces no output (or whitespace-only diffs).
4. [Ubiquitous] Root `.gitignore` gains the six Terraform ignore lines
   listed in IMPLEMENTATION, verified present via `grep -F` after the edit.
5. [Unwanted] This story shall not read, copy, modify, or commit
   `akp-infra/03-clusters/terraform.tfstate`,
   `akp-infra/03-clusters/terraform.tfstate.backup`, or
   `akp-infra/03-clusters/terraform.tfvars` (the real, filled-in vars file)
   under any circumstance.
6. [Unwanted] `git status` after staging this story's changes shall show
   no file matching `*.tfstate*`, a bare `*.tfvars` (non-`.example`), or
   anything under `.kubeconfigs/` -- byte-identical secrets-committed check
   confirmed via `git status` and `git diff --stat` output recorded as
   proof.
7. [Event] `cd terraform/clusters && terraform init -backend=false &&
   terraform validate` (run without a `terraform.tfvars` present) succeeds
   with "Success! The configuration is valid." -- confirms HCL correctness
   without touching any state or requiring real credentials.

MANDATORY SKILLS TO REVIEW:
None identified (Terraform file copy + static validation; no
project-specific skill covers Terraform/HCL in this repo).

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
- 2026-08-05T14:30:16Z dep_added: blocks AF-pydv
- 2026-08-05T14:33:39Z dep_added: blocks AF-cbot
- 2026-08-05T14:49:02Z status: open -> in_progress
- 2026-08-05T14:49:02Z claimed by dev-AF-4wcm
- 2026-08-05T14:57:17Z status: in_progress -> in_progress
- 2026-08-05T15:15:12Z status: in_progress -> closed
- 2026-08-05T15:15:12Z dep_removed: no_longer_blocks AF-pydv
- 2026-08-05T15:15:12Z dep_removed: no_longer_blocks AF-cbot

## Links
- Parent: [[AF-q1il]]

## Comments

### 2026-08-05T14:58:02Z ada
DELIVERED: AF-4wcm -- Migrate cluster/agent registration Terraform from akp-infra

Commit SHA: 5ae238cc223f0356f3b371b3c5fc2fa98f6d72b4 (branch story/AF-4wcm, pushed)
Files: 10 changed, 447 insertions(+), 0 deletions(-) -- 9 new + .gitignore

PROOF:

All validation re-run in a CLEAN ROOM extracted from the committed SHA via
`git archive 5ae238c terraform/clusters | tar -x`, so every result below is
bound to the delivered commit, not to a dirty working tree.

Commands run (all real, outputs verbatim):

1. `terraform fmt -check -recursive` (from terraform/clusters/, Terraform v1.15.8)
   -> no output, exit 0. Zero files needed reformatting; no reformat was required,
      so no whitespace drift was introduced.

2. `diff -rq` vs /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/
   main.tf                       IDENTICAL
   outputs.tf                    IDENTICAL
   providers.tf                  IDENTICAL
   variables.tf                  IDENTICAL
   terraform.tfvars.example      IDENTICAL
   templates/kustomization.yaml  IDENTICAL
   modules/cluster/ (recursive)  IDENTICAL
   -> no diff output for any path. Byte-identical, not merely whitespace-equal.

3. `terraform init -backend=false && terraform validate` (no terraform.tfvars present)
   -> init: "Terraform has been successfully initialized!" (akuity/akp v0.14.0)
   -> validate: "Success! The configuration is valid."
   Init artifacts (.terraform/, .terraform.lock.hcl) were removed before commit --
   neither is in the story's nine-file list.

4. Gitignore hygiene -- verified two ways, not just by grep:
   a. `grep -Fqx` -- all six lines PRESENT verbatim.
   b. FUNCTIONAL test with decoy files + `git check-ignore -q`:
      terraform.tfstate            IGNORED
      terraform.tfstate.backup     IGNORED
      terraform.tfvars             IGNORED
      .kubeconfigs/demo1.yaml      IGNORED
      .terraform/junk              IGNORED
      terraform.tfvars.example     TRACKED (correct -- negation works)
      All decoys deleted afterward; `git status -uno` clean post-commit.

5. Secrets scan of the staged diff (regex for PRIVATE KEY blocks,
   client-key-data:, client-certificate-data:, apiKey, password)
   -> "no secret material in staged diff".

6. YAML syntax, templates/kustomization.yaml (ruby -ryaml; pyyaml absent on this host)
   -> valid YAML; apiVersion=kustomize.config.k8s.io/v1beta1 kind=Kustomization
      patches=2; both embedded patch strings independently parse as valid YAML.

7. `pvg verify <10 paths> --format text`
   -> VERIFY: PASSED (0 files scanned, 0 issues), exit 0.
   Reported honestly: 0 files scanned -- pvg verify does not scan .tf/.yaml/
   .gitignore, so it is vacuous for this story. It is NOT evidence of quality
   here; items 1-6 are.

AC verification table:

| AC | Requirement | Result | Evidence |
|----|-------------|--------|----------|
| 1 | All 9 files exist at exact paths, byte-identical to source | PASS | Existence+line-count check (17/67/51/14/66/136/9/51/28 lines); `find terraform -type f \| wc -l` = 9 exactly (no strays); diff -rq identical |
| 2 | `terraform fmt -check -recursive` no output | PASS | No output, exit 0 (cmd 1) |
| 3 | `diff -rq` vs every source file, no output | PASS | 7 paths, all IDENTICAL (cmd 2) |
| 4 | .gitignore gains the six lines, verified via grep -F | PASS | grep -Fqx all PRESENT, plus functional check-ignore test (cmd 4) |
| 5 | Never read/copy/modify/commit tfstate, tfstate.backup, or real tfvars | PASS | Files copied by explicit per-file `cp` enumeration -- never `cp -r` of the directory. Contents of tfstate/tfstate.backup/tfvars never opened. Only a directory `ls -la` listed their names. None staged (cmd 3 table below) |
| 6 | git status after staging shows no *.tfstate*, bare *.tfvars, or .kubeconfigs/ | PASS | Staged set is exactly .gitignore + the 9 story files; git diff --stat --cached shows 10 files / 447 insertions; zero forbidden paths |
| 7 | `terraform init -backend=false && terraform validate` succeeds | PASS | "Success! The configuration is valid." (cmd 3) |

DISCREPANCY FOUND -- PM please adjudicate (1 line, comment-only, no functional impact):

The story's embedded text for `terraform.tfvars.example` does NOT match the real
akp-infra source it claims to be a verbatim copy of. I extracted all nine embedded
code blocks from the story body and diffed them against the source; 8 of 9 matched
exactly. The ninth:

  story body says:  # Must match the instances created by akp-infra's 01-argocd and 02-kargo
                    # stacks (looked up by name).
  actual source:    # Must match the instances created by 01-argocd and 02-kargo (looked up by name).

I shipped the SOURCE version, because AC1 ("byte-identical ... to their
akp-infra/03-clusters source") and AC3 ("diff -rq ... produces no output") are the
binding, machine-checkable fidelity requirements, and the story's own stated intent
is a copy "provably identical to the already-reviewed source -- not a transcription
with subtle differences". Shipping the story-body wording would have failed AC3 with
a non-whitespace diff. Note the story-body wording is arguably the better comment now
that the file lives in a different repo (01-argocd/02-kargo are not local here). If
the PM prefers that wording, it is a one-line follow-up -- but it should then be made
in akp-infra first, or ACs 1/3 relaxed, so the two repos do not silently drift.

OBSERVATION (not a blocker, no action taken -- out of scope):
akp-infra/03-clusters ships a `.terraform.lock.hcl` pinning akuity/akp v0.13.0. It is
not in this story's nine-file list, so I did not copy it. Consequently a fresh
`terraform init` here resolved v0.14.0 (the `~> 0.10` constraint floats). Validation
passes on 0.14.0, so nothing is broken today, but this stack is currently unpinned
while its source repo is pinned. Worth a follow-up story to copy or regenerate the
lock file before anyone runs `terraform apply` against real infrastructure.

LEARNINGS:
- Story-embedded "verbatim copy" text should not be trusted as the source of truth.
  Mechanically extracting every embedded block and diffing it against the real source
  caught a real drift in 1 of 9 files that eyeballing would likely have missed. Worth
  doing on every copy-migration story in this epic.
- Copy by explicit per-file `cp` enumeration, never `cp -r` of a directory, when the
  source dir contains state/secrets. The source 03-clusters holds terraform.tfstate,
  .tfstate.backup, real terraform.tfvars, and .kubeconfigs/ -- one `cp -r` would have
  leaked all four. Enumeration makes AC5 compliance structural rather than careful.
- Asserting gitignore lines are present (grep) is weaker than asserting they WORK.
  Creating decoy tfstate/tfvars/kubeconfig files and running `git check-ignore`
  actually tests the outcome, including that the `!*.tfvars.example` negation is
  correctly ordered after the `*.tfvars` rule. Recommend later epic stories reuse this.
- `terraform init` leaves .terraform/ and .terraform.lock.hcl behind. .terraform/ is
  gitignored, but the lock file is not -- clean it up before staging or it silently
  joins the commit as an untracked-then-added stray.
- Two tooling gotchas on this host: `pvg verify` takes `--format text` (space), not
  `--format=text`; and python3 has no pyyaml, so use `ruby -ryaml` for YAML checks.
  Also note pvg verify scans no .tf/.yaml files at all, so it is vacuous on
  Terraform-only stories -- do not present it as meaningful evidence.

### 2026-08-05T15:15:05Z ada
REVIEW: Independently re-verified in a pinned worktree at commit 5ae238c. terraform fmt -check -recursive clean; diff -rq identical against akp-infra/03-clusters for all 9 files including terraform.tfvars.example; terraform init -backend=false && terraform validate -> Success; .gitignore has the 6 Terraform lines and git ls-tree confirms no tfstate/tfvars/.kubeconfigs/lock-file committed; pvg verify PASSED (0 files, correctly noted as vacuous for .tf/.yaml); pvg gates PASS (0 warn, 0 skip). ADJUDICATION on flagged discrepancy: shipping the akp-infra source wording (dropping 'akp-infra's' from the 01-argocd/02-kargo comment) over the story's prose was the right call -- AC1 and AC3 are explicit, binding, machine-checkable byte-identity requirements, and the deviation is a comment-only, zero-functional-impact line. Developer disclosed it transparently for adjudication instead of silently picking a side, which is the correct behavior. Unpinned provider (.terraform.lock.hcl correctly excluded per file list) is legitimately out of scope for this story and forwarded as a follow-up. ACCEPTED.
