# AGENTS.md

Guidance for agents working in this repo.

## What this repo is

GitOps repo for personal services managed by Argo CD + Kargo, migrating off
Flux (`fleet-infra`) one app at a time. Currently targets `demo1`/`demo2`
(the same Akuity-hosted Argo CD/Kargo instance used by `akp-platform`) as a
staging ground before the eventual move to the real `annarchy.net`/
`staging.annarchy.net` clusters.

## Layout

- `bootstrap/` — the one manifest applied by hand
  (`bootstrap/fleet-platform-aoa.yaml`); everything else is discovered
  automatically from `infrastructure/*/argocd` and `apps/*/{argocd,kargo}`.
  **Never add app-specific config here.**
- `infrastructure/` — cluster-wide dependencies with no promotion pipeline
  (currently: Sealed Secrets, Traefik gateway, Gateway API CRDs,
  openebs-localpv).
- `apps/` — tenant apps, each with a full Kargo `dev → staging → prod`
  pipeline (`akkoma`, `soju`). See [`docs/onboarding.md`](docs/onboarding.md)
  before adding a new one — the naming convention there
  (directory/AppProject/Kargo Project/namespace all sharing one name) is
  load-bearing, not a suggestion.
- `terraform/clusters/` — provisions the k3d clusters and their Argo CD/Kargo
  agent registration.
- `Taskfile.yml` — all repeatable operational commands (`task --list`).

## Kargo pipelines (`apps/*/kargo/`)

When working on any Kargo resource (Warehouse, Stage, Promotion, Task,
verification steps, freight/promotion semantics, etc.), use these before
guessing at API shape or behavior:

- **`devops-toolkit:akp-platform` skill** — Akuity Platform / Kargo
  conventions internalized from prior work; check this first.
- **Kargo source** at `~/src/github.com/akuity/kargo` — authoritative for
  CRD field behavior, promotion step/task semantics, and verification
  step implementations not covered by the skill.
- **CRD reference docs** at https://doc.crds.dev/github.com/akuity/kargo —
  quick field-level lookup without cloning/grepping the source.

Every pipeline follows the same task chain (see `docs/onboarding.md` for the
external-OCI-chart pattern akkoma/soju use):
`git-clone → yaml-update (bump chartVersion) → git-commit → git-push →
argocd-update`. Before opening a PR that touches a pipeline:

- [ ] `kargo/project.yaml` carries `argocd.argoproj.io/sync-wave: "-1"`.
- [ ] Every synced Application carries
      `kargo.akuity.io/authorized-stage: <project>:<stage>`.
- [ ] The Warehouse doesn't create a promote-loop (don't subscribe to `main`
      via git if promotions also commit to `main`).
- [ ] New Kargo project → new git write credentials for it.

## Argo CD config (`apps/*/argocd/`, `infrastructure/*/argocd/`)

When working on any Argo CD resource (Application, AppProject,
ApplicationSet, repository/repo-creds registration, RBAC, resource
exclusion, etc.), use these before guessing at API shape or behavior:

- **`devops-toolkit:akp-platform` skill** — see
  `references/gitops-app-patterns.md` for this repo's app-of-apps/
  ApplicationSet conventions and `references/argocd-declarative-setup.md`
  for Argo CD's own primitives (repositories, `argocd-rbac-cm`,
  per-project `AppProject.spec.roles`, resource exclusion/inclusion) —
  including what diverges on an Akuity-hosted instance (cluster
  registration, instance-level RBAC) versus plain OSS Argo CD.
- **Argo CD source** at `~/src/github.com/argoproj/argo-cd` — authoritative
  for CRD field behavior and config wiring not covered by the skill
  (e.g. `util/settings/settings.go`, `docs/operator-manual/rbac.md`,
  `docs/user-guide/projects.md`).
- **Declarative setup docs** at
  https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/
  — quick field-level lookup without cloning/grepping the source.

Don't conflate Argo CD's own repository-credential Secrets (used by the
Repo Server to *pull* manifests) with Kargo's separate `repo-credentials`
(used by a promotion's `git-clone`/`git-push` steps to *write* commits
back) — see the skill's gotcha note; registering one does nothing for the
other.

## Secrets

Never rely on Helm `lookup` for "generate once" secrets — Argo CD renders
charts via `helm template` with no cluster access, so values regenerate on
every sync. Use the chart's `existingSecret`/`externalSecret` field, create
the real Secret with `task sealed-secrets:seal -- <namespace> <name>
<output-path> <key>=<value> [...]`, and reference it by name from
`env/<stage>/release.yaml`. Never put secret material directly in
`release.yaml` (committed in plaintext).

Local credentials (Akuity API keys, `TF_VAR_admin_password`) live in
`.envrc`, which is gitignored.

## Taskfile commands

- `sealed-secrets:generate-keypair` / `rotate-keypair` / `seal` — shared
  Sealed Secrets keypair lifecycle across every cluster in `CLUSTERS`
  (`k3d-demo1 k3d-demo2`).
- `cluster:create` / `cluster:delete` / `cluster:recreate` — k3d cluster
  lifecycle (Traefik + local-path-provisioner disabled; Argo CD/Kargo owns
  ingress and storage instead).
- `cluster:register-agent` — exports a cluster's kubeconfig and applies its
  Argo CD/Kargo agent registration via `terraform/clusters`.
- `argocd:login` / `kargo:login` — authenticate the CLIs against this
  stack's instance; both require `TF_VAR_admin_password` set and
  `terraform apply` already run in `terraform/clusters`.

## Worktrees

Branch work happens in `.worktrees/<branch-name>` (gitignored) per the
standard worktree convention — don't create/switch branches directly in the
repo root.
