# argo-fleet Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the `argo-fleet` repo with a Sealed Secrets infra layer on `demo1`/`demo2` and full Kargo/Argo CD promotion pipelines for `akkoma` and `soju`, sourcing their published OCI Helm charts directly rather than vendoring them.

**Architecture:** Two ApplicationSet discovery roots (`infrastructure/*/argocd` for cluster-wide singletons, `apps/*/{argocd,kargo}` for Kargo-piped tenants), following the same bootstrap-discovers-everything convention as `akp-platform`. Each app's Argo CD Application is multi-source: one source is the OCI chart at a Kargo-bumped version, the other is a git path to that stage's SealedSecret. Verified empirically against the live Kargo control plane during planning: `chart.semverConstraint` (not `constraint`) is the correct field for OCI chart subscriptions, and both `oci://ghcr.io/adamancini/charts/akkoma` (0.4.6) and `oci://ghcr.io/adamancini/charts/soju` (0.1.7) are real, discoverable charts.

**Tech Stack:** Argo CD (Akuity-hosted), Kargo, Helm, Sealed Secrets (Bitnami chart), Task (`go-task`), `kubeseal`.

## Global Constraints

- Target clusters: `demo1` (dev, staging), `demo2` (prod) — the same Akuity-hosted Argo CD/Kargo instance already used by `akp-platform`. Registered Argo CD destination names: `demo1`, `demo2`.
- Sealed Secrets uses **one shared RSA keypair across both clusters**, brought in via the standard Bitnami "bring your own key" mechanism (pre-create a labeled `kubernetes.io/tls` Secret before the controller starts) — not independently generated per cluster.
- cert-manager, the `annarchy.net`/`staging.annarchy.net` migration, and non-default storage backends (CNPG, external Postgres, S3) are **out of scope** — do not create tasks for them.
- Domains are placeholders: `akkoma-dev.example.com` / `akkoma-staging.example.com` / `akkoma.example.com`, and `soju-dev.example.com` / `soju-staging.example.com` / `soju.example.com`.
- `ingress.enabled` stays `false` for both apps at every stage — no ingress controller/class has been confirmed on `demo1`/`demo2`, and there's no real domain to route yet.
- No task in this plan runs `task sealed-secrets:generate-keypair`, `helm install`, `kargo apply` against the real `akkoma`/`soju` projects, or `argocd app create` against the live clusters. Those are live-cluster mutations the user triggers themselves after reviewing the generated files (see the "Manual steps" section at the end of this plan).

---

## File Structure

```text
argo-fleet/
├── .gitignore
├── README.md
├── Taskfile.yml
├── bootstrap/
│   ├── platform-aoa.yaml
│   ├── infra-apps.yaml
│   ├── argocd-apps.yaml
│   └── kargo-apps.yaml
├── infrastructure/
│   └── sealed-secrets/
│       ├── README.md
│       └── argocd/
│           └── appset.yaml
├── apps/
│   ├── akkoma/
│   │   ├── README.md
│   │   ├── argocd/
│   │   │   ├── appproject.yaml
│   │   │   └── appset.yaml
│   │   ├── kargo/
│   │   │   ├── project.yaml
│   │   │   ├── warehouse.yaml
│   │   │   ├── stages.yaml
│   │   │   └── tasks.yaml
│   │   └── env/
│   │       ├── dev/release.yaml
│   │       ├── staging/release.yaml
│   │       └── prod/release.yaml
│   └── soju/
│       └── (same shape as akkoma)
└── docs/
    ├── onboarding.md
    └── infra-dependencies.md
```

`env/<stage>/secret.sealed.yaml` files are intentionally **not** created by this plan — they require a running Sealed Secrets controller to encrypt against, which only exists after the user runs the manual steps at the end. The Application manifests reference where those files will live; they simply won't resolve until sealed.

---

### Task 1: Repo scaffolding and Taskfile skeleton

**Files:**
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/.gitignore`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/README.md`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/Taskfile.yml`

**Interfaces:**
- Produces: `Taskfile.yml` with a `sealed-secrets` namespace of tasks that later tasks (Task 2) fill in with real bodies. Establishes the `vars` block (`KEYPAIR_CERT`, `KEYPAIR_KEY`, `CLUSTERS`) other tasks reference.

- [ ] **Step 1: Write `.gitignore`**

```gitignore
.DS_Store
*.swp
.worktrees/
.superpowers/
/.task/
*.key
*.crt
```

`.superpowers/` excludes this plan's own SDD scratch workspace (ledger, briefs, review packages) from version control. The `*.key`/`*.crt` lines matter: `generate-keypair`/`rotate-keypair` (Task 2) write the shared private key to disk locally before you distribute it out-of-band — it must never be committed.

- [ ] **Step 2: Write `README.md`**

```markdown
# argo-fleet

GitOps repo for personal services managed by Argo CD + Kargo, migrating off
Flux (`fleet-infra`) one app at a time. Currently targets `demo1`/`demo2`
(the same Akuity-hosted Argo CD/Kargo instance used by `akp-platform`) as a
staging ground before the eventual move to the real `annarchy.net`/
`staging.annarchy.net` clusters.

## Layout

- `bootstrap/` — the one manifest you apply by hand
  (`bootstrap/platform-aoa.yaml`); everything else is discovered
  automatically from `infrastructure/*/argocd` and `apps/*/{argocd,kargo}`.
- `infrastructure/` — cluster-wide dependencies with no promotion pipeline
  (currently: Sealed Secrets).
- `apps/` — tenant apps, each with a full Kargo `dev → staging → prod`
  pipeline. See [`docs/onboarding.md`](docs/onboarding.md) for the pattern.
- `Taskfile.yml` — repeatable operational commands (`task --list`).

## Quickstart

1. `task sealed-secrets:generate-keypair` — generates the shared Sealed
   Secrets keypair used by every cluster in this repo (see
   [`infrastructure/sealed-secrets/README.md`](infrastructure/sealed-secrets/README.md)).
2. `argocd app create -f bootstrap/platform-aoa.yaml` — the only manifest
   applied by hand; bootstraps everything else.
3. Add Kargo git write credentials for each project (`akkoma`, `soju`) —
   same pattern as `akp-platform`'s `add-credentials.sh`.
4. Promote via the Kargo UI/CLI once Freight is discovered.
```

- [ ] **Step 3: Write `Taskfile.yml` skeleton**

```yaml
version: '3'

vars:
  KEYPAIR_DIR: '{{.ROOT_DIR}}/.sealed-secrets-keypair'
  KEYPAIR_CERT: '{{.KEYPAIR_DIR}}/tls.crt'
  KEYPAIR_KEY: '{{.KEYPAIR_DIR}}/tls.key'
  CLUSTERS: k3d-demo1 k3d-demo2

tasks:
  sealed-secrets:generate-keypair:
    desc: Generate the shared Sealed Secrets RSA keypair and install it as the active key on every cluster in CLUSTERS.
    # Body added in Task 2.

  sealed-secrets:rotate-keypair:
    desc: Rotate to a new shared keypair and re-seal every existing SealedSecret against it.
    # Body added in Task 2.

  sealed-secrets:seal:
    desc: 'Seal a plaintext secret. Usage: task sealed-secrets:seal -- <namespace> <name> <output-path> <key>=<value> [<key>=<value>...]'
    # Body added in Task 2.
```

- [ ] **Step 4: Validate YAML syntax**

Run: `ruby -ryaml -e "YAML.load_stream(File.read('Taskfile.yml'))" && echo OK`
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
cd /Users/ada/src/github.com/adamancini/argo-fleet
git add .gitignore README.md Taskfile.yml
git commit -m "Scaffold repo: gitignore, README, Taskfile skeleton"
```

---

### Task 2: Sealed Secrets Taskfile tasks

**Files:**
- Modify: `/Users/ada/src/github.com/adamancini/argo-fleet/Taskfile.yml`

**Interfaces:**
- Consumes: `KEYPAIR_CERT`, `KEYPAIR_KEY`, `CLUSTERS` vars from Task 1.
- Produces: `task sealed-secrets:seal -- <namespace> <name> <output-path> <key>=<value>...` — the command every later app task (4, 6) documents as how its `secret.sealed.yaml` gets created.

- [ ] **Step 1: Fill in `sealed-secrets:generate-keypair`**

Replace the `# Body added in Task 2.` comment under `sealed-secrets:generate-keypair` with:

```yaml
  sealed-secrets:generate-keypair:
    desc: Generate the shared Sealed Secrets RSA keypair and install it as the active key on every cluster in CLUSTERS.
    cmds:
      - mkdir -p {{.KEYPAIR_DIR}}
      - |
        openssl req -x509 -days 3650 -nodes -newkey rsa:4096 \
          -keyout {{.KEYPAIR_KEY}} -out {{.KEYPAIR_CERT}} \
          -subj "/CN=sealed-secret/O=argo-fleet"
      - for: { var: CLUSTERS, split: ' ' }
        cmd: |
          set -euo pipefail
          kubectl --context {{.ITEM}} create namespace sealed-secrets --dry-run=client -o yaml | kubectl --context {{.ITEM}} apply -f -
          kubectl --context {{.ITEM}} -n sealed-secrets create secret tls sealed-secrets-key \
            --cert={{.KEYPAIR_CERT}} --key={{.KEYPAIR_KEY}} \
            --dry-run=client -o yaml | kubectl --context {{.ITEM}} apply -f -
          kubectl --context {{.ITEM}} -n sealed-secrets label secret sealed-secrets-key \
            sealedsecrets.bitnami.com/sealed-secrets-key=active --overwrite
      - echo "Shared keypair at {{.KEYPAIR_DIR}} -- back up {{.KEYPAIR_KEY}} out-of-band. It is gitignored and will NOT be committed."
```

- [ ] **Step 2: Fill in `sealed-secrets:rotate-keypair`**

```yaml
  sealed-secrets:rotate-keypair:
    desc: Rotate to a new shared keypair and re-seal every existing SealedSecret against it.
    cmds:
      # generate-keypair always writes to the fixed name `sealed-secrets-key`,
      # so preserve the CURRENT local key material under a different name on
      # every cluster first -- built fresh from the cert/key files via
      # --dry-run=client (not fetched from the live object), so there's no
      # stale resourceVersion/uid to strip before the apply. Per Sealed
      # Secrets' own multi-key model, the controller retains every key
      # sharing this label for decrypting old SealedSecrets and uses the
      # newest for sealing new ones -- so the preserved key needs no label
      # change, only a different Secret name than the one generate-keypair
      # is about to overwrite.
      - for: { var: CLUSTERS, split: ' ' }
        cmd: |
          set -euo pipefail
          kubectl --context {{.ITEM}} -n sealed-secrets create secret tls sealed-secrets-key-previous \
            --cert={{.KEYPAIR_CERT}} --key={{.KEYPAIR_KEY}} \
            --dry-run=client -o yaml | kubectl --context {{.ITEM}} apply -f -
          kubectl --context {{.ITEM}} -n sealed-secrets label secret sealed-secrets-key-previous \
            sealedsecrets.bitnami.com/sealed-secrets-key=active --overwrite
      - mv {{.KEYPAIR_CERT}} {{.KEYPAIR_DIR}}/tls.crt.previous
      - mv {{.KEYPAIR_KEY}} {{.KEYPAIR_DIR}}/tls.key.previous
      - task: sealed-secrets:generate-keypair
      # The controller only discovers labeled key Secrets on startup, so a
      # manually-added key (unlike its own periodic --key-renew-period
      # rotation) needs a restart to take effect.
      - for: { var: CLUSTERS, split: ' ' }
        cmd: |
          set -euo pipefail
          kubectl --context {{.ITEM}} -n sealed-secrets rollout restart deployment/sealed-secrets
          kubectl --context {{.ITEM}} -n sealed-secrets rollout status deployment/sealed-secrets --timeout=60s
      - echo "New key generated and active on every cluster; old key preserved as sealed-secrets-key-previous for decrypting not-yet-re-sealed secrets. Re-seal each apps/*/env/*/secret.sealed.yaml by re-running the same 'task sealed-secrets:seal' command originally used to create it."
```

- [ ] **Step 3: Fill in `sealed-secrets:seal`**

```yaml
  sealed-secrets:seal:
    desc: 'Seal a plaintext secret. Usage: task sealed-secrets:seal -- <namespace> <name> <output-path> <key>=<value> [<key>=<value>...]'
    cmds:
      - |
        set -euo pipefail
        NAMESPACE="{{index .CLI_ARGS_LIST 0}}"
        NAME="{{index .CLI_ARGS_LIST 1}}"
        OUTPUT="{{index .CLI_ARGS_LIST 2}}"
        kubectl create secret generic "${NAME}" \
          --namespace "${NAMESPACE}" \
          {{range $i, $kv := .CLI_ARGS_LIST}}{{if ge $i 3}}--from-literal={{$kv}} {{end}}{{end}}\
          --dry-run=client -o yaml \
        | kubeseal --cert {{.KEYPAIR_CERT}} --format yaml \
        > "${OUTPUT}"
        echo "Wrote ${OUTPUT}"
```

- [ ] **Step 4: Validate YAML syntax**

Run: `ruby -ryaml -e "YAML.load_stream(File.read('Taskfile.yml'))" && echo OK`
Expected: `OK`

- [ ] **Step 5: Verify `task --list` shows all three tasks with descriptions**

Run: `cd /Users/ada/src/github.com/adamancini/argo-fleet && task --list`
Expected: output includes `sealed-secrets:generate-keypair`, `sealed-secrets:rotate-keypair`, `sealed-secrets:seal`, each with its `desc:` text. If `task` isn't installed, run `brew install go-task` first and note this as a new prerequisite in `README.md`'s Quickstart section.

- [ ] **Step 6: Commit**

```bash
git add Taskfile.yml
git commit -m "Add Sealed Secrets Taskfile tasks: generate-keypair, rotate-keypair, seal"
```

---

### Task 3: Bootstrap ApplicationSets

**Files:**
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/bootstrap/platform-aoa.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/bootstrap/infra-apps.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/bootstrap/argocd-apps.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/bootstrap/kargo-apps.yaml`

**Interfaces:**
- Consumes: none.
- Produces: the discovery convention every later task's `argocd/appset.yaml` (Task 3, 5, 7) and `kargo/*.yaml` (Task 4, 6) rely on — `infrastructure/*/argocd`, `apps/*/argocd`, `apps/*/kargo`.

- [ ] **Step 1: Write `bootstrap/platform-aoa.yaml`**

```yaml
# Root app-of-apps. Apply this ONCE against the Argo CD control plane
# (`argocd app create -f bootstrap/platform-aoa.yaml`) and everything else
# in this repo is discovered and deployed automatically by the
# ApplicationSets in this directory. Onboarding a new infra dependency or
# app never requires touching bootstrap/ again.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-aoa
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/adamancini/argo-fleet.git
    targetRevision: HEAD
    path: bootstrap
  destination:
    name: in-cluster
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

- [ ] **Step 2: Write `bootstrap/infra-apps.yaml`**

```yaml
# Discovers infrastructure/*/argocd and creates one Argo CD Application per
# cluster-wide dependency. These have no Kargo pipeline -- they're
# singletons that need to exist identically everywhere, not promoted.
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: infra-apps
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: https://github.com/adamancini/argo-fleet.git
      revision: HEAD
      directories:
      - path: infrastructure/*/argocd
  template:
    metadata:
      name: 'infra-{{path[1]}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/adamancini/argo-fleet.git
        targetRevision: HEAD
        path: '{{path}}'
        directory:
          recurse: true
      destination:
        name: in-cluster
        namespace: argocd
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

- [ ] **Step 3: Write `bootstrap/argocd-apps.yaml`**

```yaml
# Discovers apps/*/argocd/ and creates one Argo CD Application per app that
# syncs that app's AppProject and ApplicationSet. Adding a new app directory
# under apps/ is all that's needed -- no edits here.
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: argocd-apps
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: https://github.com/adamancini/argo-fleet.git
      revision: HEAD
      directories:
      - path: apps/*/argocd
  template:
    metadata:
      name: 'argocd-{{path[1]}}'
    spec:
      # Default project avoids a bootstrap chicken-and-egg: each app's
      # AppProject lives inside the argocd/ path this Application syncs, so
      # the project can't exist before the Application is created.
      project: default
      source:
        repoURL: https://github.com/adamancini/argo-fleet.git
        targetRevision: HEAD
        path: '{{path}}'
        directory:
          recurse: true
      destination:
        name: in-cluster
        namespace: argocd
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

- [ ] **Step 4: Write `bootstrap/kargo-apps.yaml`**

```yaml
# Discovers apps/*/kargo/ and creates one Argo CD Application per app that
# syncs that app's Kargo resources to the Kargo control plane (Argo CD
# cluster named `kargo`).
#
# NOTE: automated sync is REQUIRED here. Without it, merged changes to
# apps/*/kargo/*.yaml silently never reach the cluster, and promotions keep
# running the stale task.
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: kargo-apps
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: https://github.com/adamancini/argo-fleet.git
      revision: HEAD
      directories:
      - path: apps/*/kargo
      requeueAfterSeconds: 30
  template:
    metadata:
      name: 'kargo-{{path[1]}}'
    spec:
      # Convention: the app directory name IS the Argo CD AppProject name
      # and the Kargo Project name.
      project: '{{path[1]}}'
      source:
        repoURL: https://github.com/adamancini/argo-fleet.git
        targetRevision: HEAD
        path: '{{path}}'
        directory:
          recurse: true
      destination:
        name: kargo
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

- [ ] **Step 5: Validate YAML syntax of all four files**

Run:
```bash
cd /Users/ada/src/github.com/adamancini/argo-fleet
for f in bootstrap/*.yaml; do ruby -ryaml -e "YAML.load_stream(File.read('$f'))" && echo "OK $f" || echo "FAIL $f"; done
```
Expected: `OK bootstrap/argocd-apps.yaml`, `OK bootstrap/infra-apps.yaml`, `OK bootstrap/kargo-apps.yaml`, `OK bootstrap/platform-aoa.yaml`.

- [ ] **Step 6: Commit**

```bash
git add bootstrap/
git commit -m "Add bootstrap ApplicationSets: infra-apps, argocd-apps, kargo-apps"
```

---

### Task 4: Sealed Secrets infra layer

**Files:**
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/infrastructure/sealed-secrets/README.md`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/infrastructure/sealed-secrets/argocd/appset.yaml`

**Interfaces:**
- Consumes: `infra-apps.yaml`'s discovery of `infrastructure/*/argocd` (Task 3).
- Produces: a running `sealed-secrets` controller in the `sealed-secrets` namespace on both `demo1` and `demo2`, which Task 5/7's `secret.sealed.yaml` files (created later, manually, via `task sealed-secrets:seal`) depend on.

- [ ] **Step 1: Write `infrastructure/sealed-secrets/argocd/appset.yaml`**

A `list` generator, not `git.directories` — there's no per-cluster directory in this repo, just two known destination names.

```yaml
# One Application per cluster, installing the upstream Sealed Secrets
# controller. The shared keypair (see Taskfile.yml's sealed-secrets:*
# tasks) is pre-created as a labeled Secret in the sealed-secrets namespace
# before this syncs -- the chart detects the existing secret and uses it
# instead of generating a new one.
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: sealed-secrets
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: demo1
      - cluster: demo2
  template:
    metadata:
      name: 'sealed-secrets-{{cluster}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/bitnami-labs/sealed-secrets.git
        targetRevision: v2.16.1
        path: helm/sealed-secrets
        helm:
          valuesObject:
            fullnameOverride: sealed-secrets
      destination:
        name: '{{cluster}}'
        namespace: sealed-secrets
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

- [ ] **Step 2: Write `infrastructure/sealed-secrets/README.md`**

```markdown
# sealed-secrets — cluster-wide dependency, no promotion pipeline

Installs the [Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
controller on every cluster in `argocd/appset.yaml`'s `list` generator
(`demo1`, `demo2`). Unlike everything under `apps/`, this has no Kargo
pipeline -- it's a singleton that needs to exist identically everywhere,
not something with distinct dev/staging/prod versions.

## Shared keypair

All clusters use the **same** RSA keypair rather than each controller
generating its own, so a SealedSecret sealed once decrypts on every
cluster running this controller -- including `annarchy.net`/
`staging.annarchy.net` once those eventually join. See the repo root
`Taskfile.yml`:

```bash
task sealed-secrets:generate-keypair   # one-time setup
task sealed-secrets:rotate-keypair     # if the key is ever compromised
task sealed-secrets:seal -- <namespace> <name> <output-path> <key>=<value>...
```

The private key lives at `.sealed-secrets-keypair/tls.key` locally
(gitignored) -- back it up out-of-band. Losing it means every existing
SealedSecret becomes permanently undecryptable.

## Why not each cluster generating its own key

The default behavior (each controller generates a cluster-specific
keypair on first start) would mean re-sealing every secret by hand when
`annarchy.net`/`staging.annarchy.net` eventually join this repo. Bringing
one shared key avoids that at the cost of a slightly larger blast radius
if the key is ever compromised -- acceptable here since these clusters are
environments for the same services, not isolation boundaries.
```

- [ ] **Step 3: Validate YAML syntax**

Run: `ruby -ryaml -e "YAML.load_stream(File.read('infrastructure/sealed-secrets/argocd/appset.yaml'))" && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add infrastructure/
git commit -m "Add Sealed Secrets infra layer for demo1/demo2"
```

---

### Task 5: akkoma Kargo pipeline

**Files:**
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/akkoma/argocd/appproject.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/akkoma/kargo/project.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/akkoma/kargo/warehouse.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/akkoma/kargo/stages.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/akkoma/kargo/tasks.yaml`

**Interfaces:**
- Consumes: `argocd-apps.yaml`/`kargo-apps.yaml` discovery (Task 3).
- Produces: a `chartVersion` value that Task 6's `argocd/appset.yaml` reads from `env/<stage>/release.yaml` — the field name `chartVersion` is the contract between this task's `tasks.yaml` (which writes it) and Task 6's ApplicationSet template (which reads it).

- [ ] **Step 1: Write `apps/akkoma/argocd/appproject.yaml`**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: akkoma
  namespace: argocd
spec:
  description: Akkoma (Fediverse server), promoted via its published OCI Helm chart
  sourceRepos:
    - '*'
  destinations:
    - server: '*'
      name: '*'
      namespace: '*'
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
```

- [ ] **Step 2: Write `apps/akkoma/kargo/project.yaml`**

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: akkoma
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
```

- [ ] **Step 3: Write `apps/akkoma/kargo/warehouse.yaml`**

Verified live against the real registry while planning: `semverConstraint: '>=0.4.6'` against `oci://ghcr.io/adamancini/charts/akkoma` discovers version `0.4.6`. `chart.name` must stay unset for OCI repo URLs -- the URL already identifies exactly one chart.

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: akkoma
  namespace: akkoma
spec:
  subscriptions:
  - chart:
      repoURL: oci://ghcr.io/adamancini/charts/akkoma
      semverConstraint: '>=0.4.6'
```

- [ ] **Step 4: Write `apps/akkoma/kargo/stages.yaml`**

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: dev
  namespace: akkoma
  annotations:
    kargo.akuity.io/color: green
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: akkoma
    sources:
      direct: true
  promotionTemplate:
    spec:
      steps:
      - task:
          name: promote
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: staging
  namespace: akkoma
  annotations:
    kargo.akuity.io/color: amber
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: akkoma
    sources:
      stages:
      - dev
  promotionTemplate:
    spec:
      steps:
      - task:
          name: promote
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: prod
  namespace: akkoma
  annotations:
    kargo.akuity.io/color: red
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: akkoma
    sources:
      stages:
      - staging
  promotionTemplate:
    spec:
      steps:
      - task:
          name: promote
```

- [ ] **Step 5: Write `apps/akkoma/kargo/tasks.yaml`**

Bumps `chartVersion` in the stage's `release.yaml` using `yaml-update` -- the same mechanism `guestbook-helm` uses for `image.tag`, but targeting the chart version discovered from the Warehouse instead of an image tag.

```yaml
# Every promotion is a real commit to main that bumps chartVersion in the
# stage's env/<stage>/release.yaml. Argo CD's multi-source Application
# (see argocd/appset.yaml) reads that value as the OCI chart's
# targetRevision, so git history on main doubles as the deployment history.
apiVersion: kargo.akuity.io/v1alpha1
kind: PromotionTask
metadata:
  name: promote
  namespace: akkoma
spec:
  vars:
  - name: repoURL
    value: https://github.com/adamancini/argo-fleet.git
  - name: chart
    value: oci://ghcr.io/adamancini/charts/akkoma
  steps:
  - uses: git-clone
    config:
      repoURL: ${{ vars.repoURL }}
      checkout:
      - branch: main
        path: ./src
  - uses: yaml-update
    as: update-chart-version
    config:
      path: ./src/apps/akkoma/env/${{ ctx.stage }}/release.yaml
      updates:
      - key: chartVersion
        value: ${{ chartFrom(vars.chart).Version }}
  - uses: git-commit
    as: commit
    config:
      path: ./src
      message: "akkoma/${{ ctx.stage }}: promote ${{ chartFrom(vars.chart).Version }}"
  - uses: git-push
    config:
      path: ./src
      targetBranch: main
  - uses: argocd-update
    config:
      apps:
      - name: akkoma-${{ ctx.stage }}
```

- [ ] **Step 6: Validate YAML syntax of all five files**

Run:
```bash
cd /Users/ada/src/github.com/adamancini/argo-fleet
for f in apps/akkoma/argocd/appproject.yaml apps/akkoma/kargo/*.yaml; do
  ruby -ryaml -e "YAML.load_stream(File.read('$f'))" && echo "OK $f" || echo "FAIL $f"
done
```
Expected: `OK` for all five.

- [ ] **Step 7: Commit**

```bash
git add apps/akkoma/argocd/appproject.yaml apps/akkoma/kargo/
git commit -m "Add akkoma Kargo pipeline: project, warehouse, stages, promotion task"
```

---

### Task 6: akkoma ApplicationSet, env pin files, and README

**Files:**
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/akkoma/argocd/appset.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/akkoma/env/dev/release.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/akkoma/env/staging/release.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/akkoma/env/prod/release.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/akkoma/README.md`

**Interfaces:**
- Consumes: `chartVersion` field written by Task 5's `tasks.yaml`.
- Produces: `akkoma-{dev,staging,prod}` Argo CD Application names, which Task 5's `tasks.yaml` `argocd-update` step already references.

- [ ] **Step 1: Write `apps/akkoma/env/dev/release.yaml`**

`chartVersion` starts at the real published version so the Application is valid immediately, even before the first promotion. `values` sets the fields the akkoma chart's own docs/templates confirm as the GitOps-safe path around Helm's `lookup` (verified by reading `charts/akkoma/templates/secret-akkoma.yaml` and `values.yaml` in `akkoma-helm` directly): `externalSecret.enabled`/`externalSecret.name` for the app secret (keys `secret-key-base`, `signing-salt`, `release-cookie`), and `postgresql.existingSecret` for the bundled Postgres password (key `postgres-password`, matching `postgresql.existingSecretPasswordKey`'s default).

```yaml
chartVersion: 0.4.6
values:
  akkoma:
    domain: akkoma-dev.example.com
    adminEmail: admin@example.com
  externalSecret:
    enabled: true
    name: akkoma-secrets
  postgresql:
    existingSecret: akkoma-postgresql
  ingress:
    enabled: false
```

- [ ] **Step 2: Write `apps/akkoma/env/staging/release.yaml`**

```yaml
chartVersion: 0.4.6
values:
  akkoma:
    domain: akkoma-staging.example.com
    adminEmail: admin@example.com
  externalSecret:
    enabled: true
    name: akkoma-secrets
  postgresql:
    existingSecret: akkoma-postgresql
  ingress:
    enabled: false
```

- [ ] **Step 3: Write `apps/akkoma/env/prod/release.yaml`**

```yaml
chartVersion: 0.4.6
values:
  akkoma:
    domain: akkoma.example.com
    adminEmail: admin@example.com
  externalSecret:
    enabled: true
    name: akkoma-secrets
  postgresql:
    existingSecret: akkoma-postgresql
  ingress:
    enabled: false
```

- [ ] **Step 4: Write `apps/akkoma/argocd/appset.yaml`**

A `files` generator (not `directories`) -- the template needs the pin file's *contents* (`chartVersion`, `values`) as variables, not just the matched path. Multi-source: source 1 is the OCI chart, source 2 is this same repo so the SealedSecret at `apps/akkoma/env/<stage>/secret.sealed.yaml` applies alongside it (that file doesn't exist until the manual sealing step at the end of this plan -- Argo CD will report this Application as `Unknown`/degraded until then, which is expected).

```yaml
# One Argo CD Application per env/*/release.yaml. Multi-source: the OCI
# chart at the version Kargo last promoted, plus this repo's own path for
# the stage's SealedSecret (created via `task sealed-secrets:seal`, not by
# Kargo -- it isn't a release artifact).
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: akkoma
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - git:
      repoURL: https://github.com/adamancini/argo-fleet.git
      revision: HEAD
      files:
      - path: "apps/akkoma/env/*/release.yaml"
  template:
    metadata:
      name: 'akkoma-{{.path.basename}}'
      annotations:
        kargo.akuity.io/authorized-stage: 'akkoma:{{.path.basename}}'
    spec:
      project: akkoma
      sources:
      # valuesObject is an object-typed field (backed by RawExtension) --
      # Argo CD's Go-template engine only substitutes into string fields, so
      # `valuesObject: '{{.values}}'` can't work (same restriction the docs
      # call out for syncPolicy). The structure has to be spelled out here,
      # templating only the individual leaf values that genuinely vary by
      # stage (all quoted strings -- the one documented-safe pattern).
      # externalSecret.enabled and ingress.enabled are identical at every
      # stage in this design, so they're plain YAML booleans, not templated --
      # avoids relying on how an unquoted `{{...}}` in this position would
      # even parse (raw, un-rendered `{{` is ambiguous with YAML flow-mapping
      # syntax), and avoids Helm/Sprig `if` treating a quoted "false" string
      # as truthy.
      - repoURL: ghcr.io/adamancini/charts
        chart: akkoma
        targetRevision: '{{.chartVersion}}'
        helm:
          valuesObject:
            akkoma:
              domain: '{{.values.akkoma.domain}}'
              adminEmail: '{{.values.akkoma.adminEmail}}'
            externalSecret:
              enabled: true
              name: '{{.values.externalSecret.name}}'
            postgresql:
              existingSecret: '{{.values.postgresql.existingSecret}}'
            ingress:
              enabled: false
      - repoURL: https://github.com/adamancini/argo-fleet.git
        targetRevision: HEAD
        path: '{{.path.path}}'
      destination:
        name: '{{- if eq .path.basename "prod" }}demo2{{- else }}demo1{{- end }}'
        namespace: 'akkoma-{{.path.basename}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

- [ ] **Step 5: Write `apps/akkoma/README.md`**

```markdown
# akkoma — external OCI chart, promotions commit to main

Deploys [akkoma-helm](https://github.com/adamancini/akkoma-helm)'s published
chart (`oci://ghcr.io/adamancini/charts/akkoma`) directly -- unlike
`akp-platform`'s `guestbook-helm`, nothing is vendored into this repo. Each
environment's `env/<stage>/release.yaml` pins the chart version and stage
values; Argo CD's `files` generator reads it to build a multi-source
Application (chart + this repo's SealedSecret).

**Pipeline:** `Warehouse → dev → staging → prod`. `dev`/`staging` run on
`demo1`, `prod` on `demo2`.

## Why not vendor the chart

`akkoma-helm` is an independently maintained, versioned chart -- copying it
in means manually re-syncing on every upstream release, which defeats the
point of it being published. The Warehouse's `chart:` subscription tracks
real chart SemVer releases directly.

## Secrets

Argo CD renders charts via `helm template` with no cluster access, so
Helm's `lookup` (which this chart normally uses to preserve
auto-generated secrets across upgrades) always resolves empty --
deploying as-is would regenerate random secrets on every sync. Each stage's
`release.yaml` sets `externalSecret.enabled`/`externalSecret.name` and
`postgresql.existingSecret` instead, pointing at Secrets created by the
`sealed-secrets` controller (see `infrastructure/sealed-secrets/`) from
this app's `env/<stage>/secret.sealed.yaml` -- created via:

```bash
task sealed-secrets:seal -- akkoma-dev akkoma-secrets apps/akkoma/env/dev/secret.sealed.yaml \
  secret-key-base=$(openssl rand -hex 32) \
  signing-salt=$(openssl rand -hex 4) \
  release-cookie=$(openssl rand -hex 32)
task sealed-secrets:seal -- akkoma-dev akkoma-postgresql apps/akkoma/env/dev/secret.sealed.yaml \
  postgres-password=$(openssl rand -hex 16)
```

Repeat per stage (`akkoma-staging`, `akkoma-prod` namespaces). Kargo never
touches `secret.sealed.yaml` -- it isn't a release artifact.

## Things to know

- The Warehouse is chart-only, watching real chart SemVer -- no image
  subscription needed; the chart's own default `image.tag`/`appVersion`
  tracks the akkoma app version already.
- Storage defaults (bundled Postgres StatefulSet), and TLS/ingress
  (disabled, placeholder domains) are deferred -- see the design spec in
  `docs/superpowers/specs/`.
```

- [ ] **Step 6: Validate YAML syntax**

Run:
```bash
cd /Users/ada/src/github.com/adamancini/argo-fleet
for f in apps/akkoma/argocd/appset.yaml apps/akkoma/env/dev/release.yaml apps/akkoma/env/staging/release.yaml apps/akkoma/env/prod/release.yaml; do
  ruby -ryaml -e "YAML.load_stream(File.read('$f'))" && echo "OK $f" || echo "FAIL $f"
done
```
Expected: `OK` for all four.

- [ ] **Step 7: Commit**

```bash
git add apps/akkoma/argocd/appset.yaml apps/akkoma/env/ apps/akkoma/README.md
git commit -m "Add akkoma ApplicationSet, env pin files, and README"
```

---

### Task 7: soju Kargo pipeline

**Files:**
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/soju/argocd/appproject.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/soju/kargo/project.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/soju/kargo/warehouse.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/soju/kargo/stages.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/soju/kargo/tasks.yaml`

**Interfaces:**
- Same contract as Task 5, for `soju` instead of `akkoma`.

- [ ] **Step 1: Write `apps/soju/argocd/appproject.yaml`**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: soju
  namespace: argocd
spec:
  description: soju (IRC bouncer) + gamja, promoted via its published OCI Helm chart
  sourceRepos:
    - '*'
  destinations:
    - server: '*'
      name: '*'
      namespace: '*'
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
```

- [ ] **Step 2: Write `apps/soju/kargo/project.yaml`**

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: soju
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
```

- [ ] **Step 3: Write `apps/soju/kargo/warehouse.yaml`**

Verified live against the real registry while planning: `semverConstraint: '>=0.1.7'` against `oci://ghcr.io/adamancini/charts/soju` discovers version `0.1.7`.

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: soju
  namespace: soju
spec:
  subscriptions:
  - chart:
      repoURL: oci://ghcr.io/adamancini/charts/soju
      semverConstraint: '>=0.1.7'
```

- [ ] **Step 4: Write `apps/soju/kargo/stages.yaml`**

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: dev
  namespace: soju
  annotations:
    kargo.akuity.io/color: green
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: soju
    sources:
      direct: true
  promotionTemplate:
    spec:
      steps:
      - task:
          name: promote
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: staging
  namespace: soju
  annotations:
    kargo.akuity.io/color: amber
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: soju
    sources:
      stages:
      - dev
  promotionTemplate:
    spec:
      steps:
      - task:
          name: promote
---
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: prod
  namespace: soju
  annotations:
    kargo.akuity.io/color: red
spec:
  requestedFreight:
  - origin:
      kind: Warehouse
      name: soju
    sources:
      stages:
      - staging
  promotionTemplate:
    spec:
      steps:
      - task:
          name: promote
```

- [ ] **Step 5: Write `apps/soju/kargo/tasks.yaml`**

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: PromotionTask
metadata:
  name: promote
  namespace: soju
spec:
  vars:
  - name: repoURL
    value: https://github.com/adamancini/argo-fleet.git
  - name: chart
    value: oci://ghcr.io/adamancini/charts/soju
  steps:
  - uses: git-clone
    config:
      repoURL: ${{ vars.repoURL }}
      checkout:
      - branch: main
        path: ./src
  - uses: yaml-update
    as: update-chart-version
    config:
      path: ./src/apps/soju/env/${{ ctx.stage }}/release.yaml
      updates:
      - key: chartVersion
        value: ${{ chartFrom(vars.chart).Version }}
  - uses: git-commit
    as: commit
    config:
      path: ./src
      message: "soju/${{ ctx.stage }}: promote ${{ chartFrom(vars.chart).Version }}"
  - uses: git-push
    config:
      path: ./src
      targetBranch: main
  - uses: argocd-update
    config:
      apps:
      - name: soju-${{ ctx.stage }}
```

- [ ] **Step 6: Validate YAML syntax of all five files**

Run:
```bash
cd /Users/ada/src/github.com/adamancini/argo-fleet
for f in apps/soju/argocd/appproject.yaml apps/soju/kargo/*.yaml; do
  ruby -ryaml -e "YAML.load_stream(File.read('$f'))" && echo "OK $f" || echo "FAIL $f"
done
```
Expected: `OK` for all five.

- [ ] **Step 7: Commit**

```bash
git add apps/soju/argocd/appproject.yaml apps/soju/kargo/
git commit -m "Add soju Kargo pipeline: project, warehouse, stages, promotion task"
```

---

### Task 8: soju ApplicationSet, env pin files, and README

**Files:**
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/soju/argocd/appset.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/soju/env/dev/release.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/soju/env/staging/release.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/soju/env/prod/release.yaml`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/apps/soju/README.md`

**Interfaces:**
- Same contract as Task 6, for `soju`. `admin.existingSecret` replaces akkoma's `externalSecret.name` (verified against `soju-helm/charts/soju/templates/secret.yaml` and `values.yaml`: the referenced Secret needs keys `admin-username`, `admin-password`).

- [ ] **Step 1: Write `apps/soju/env/dev/release.yaml`**

```yaml
chartVersion: 0.1.7
values:
  soju:
    domain: soju-dev.example.com
  admin:
    enabled: true
    existingSecret: soju-admin
  ingress:
    enabled: false
```

- [ ] **Step 2: Write `apps/soju/env/staging/release.yaml`**

```yaml
chartVersion: 0.1.7
values:
  soju:
    domain: soju-staging.example.com
  admin:
    enabled: true
    existingSecret: soju-admin
  ingress:
    enabled: false
```

- [ ] **Step 3: Write `apps/soju/env/prod/release.yaml`**

```yaml
chartVersion: 0.1.7
values:
  soju:
    domain: soju.example.com
  admin:
    enabled: true
    existingSecret: soju-admin
  ingress:
    enabled: false
```

- [ ] **Step 4: Write `apps/soju/argocd/appset.yaml`**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: soju
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - git:
      repoURL: https://github.com/adamancini/argo-fleet.git
      revision: HEAD
      files:
      - path: "apps/soju/env/*/release.yaml"
  template:
    metadata:
      name: 'soju-{{.path.basename}}'
      annotations:
        kargo.akuity.io/authorized-stage: 'soju:{{.path.basename}}'
    spec:
      project: soju
      sources:
      # valuesObject is an object-typed field (backed by RawExtension) --
      # Argo CD's Go-template engine only substitutes into string fields, so
      # `valuesObject: '{{.values}}'` can't work (same restriction the docs
      # call out for syncPolicy). The structure has to be spelled out here,
      # templating only the individual leaf values that genuinely vary by
      # stage (all quoted strings -- the one documented-safe pattern).
      # admin.enabled and ingress.enabled are identical at every stage in
      # this design, so they're plain YAML booleans, not templated -- avoids
      # relying on how an unquoted `{{...}}` in this position would even
      # parse (raw, un-rendered `{{` is ambiguous with YAML flow-mapping
      # syntax), and avoids Helm/Sprig `if` treating a quoted "false" string
      # as truthy.
      - repoURL: ghcr.io/adamancini/charts
        chart: soju
        targetRevision: '{{.chartVersion}}'
        helm:
          valuesObject:
            soju:
              domain: '{{.values.soju.domain}}'
            admin:
              enabled: true
              existingSecret: '{{.values.admin.existingSecret}}'
            ingress:
              enabled: false
      - repoURL: https://github.com/adamancini/argo-fleet.git
        targetRevision: HEAD
        path: '{{.path.path}}'
      destination:
        name: '{{- if eq .path.basename "prod" }}demo2{{- else }}demo1{{- end }}'
        namespace: 'soju-{{.path.basename}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

- [ ] **Step 5: Write `apps/soju/README.md`**

```markdown
# soju — external OCI chart, promotions commit to main

Deploys [soju-helm](https://github.com/adamancini/soju-helm)'s published
chart (`oci://ghcr.io/adamancini/charts/soju`) directly. Same pattern as
`apps/akkoma/` -- see that README for the full rationale on the multi-source
Application and why the chart isn't vendored.

**Pipeline:** `Warehouse → dev → staging → prod`. `dev`/`staging` run on
`demo1`, `prod` on `demo2`.

## Secrets

`admin.existingSecret` replaces the chart's own post-install-hook-based
admin user creation (which would otherwise rely on Helm `lookup` and
regenerate credentials on every Argo CD sync). Create it per stage via:

```bash
task sealed-secrets:seal -- soju-dev soju-admin apps/soju/env/dev/secret.sealed.yaml \
  admin-username=admin \
  admin-password=$(openssl rand -hex 12)
```

Repeat per stage (`soju-staging`, `soju-prod` namespaces).

## Things to know

- The Warehouse is chart-only -- soju's actual application image comes
  from upstream (`codeberg.org/emersion/soju`), and `soju-helm`'s own
  `check-upstream.yml` bot already keeps the chart's pinned image tag and
  chart version bumped together, so tracking chart SemVer alone is
  sufficient.
- gamja (the bundled web client subchart) stays at its chart defaults --
  no override needed for this phase.
```

- [ ] **Step 6: Validate YAML syntax**

Run:
```bash
cd /Users/ada/src/github.com/adamancini/argo-fleet
for f in apps/soju/argocd/appset.yaml apps/soju/env/dev/release.yaml apps/soju/env/staging/release.yaml apps/soju/env/prod/release.yaml; do
  ruby -ryaml -e "YAML.load_stream(File.read('$f'))" && echo "OK $f" || echo "FAIL $f"
done
```
Expected: `OK` for all four.

- [ ] **Step 7: Commit**

```bash
git add apps/soju/argocd/appset.yaml apps/soju/env/ apps/soju/README.md
git commit -m "Add soju ApplicationSet, env pin files, and README"
```

---

### Task 9: Onboarding docs

**Files:**
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/docs/onboarding.md`
- Create: `/Users/ada/src/github.com/adamancini/argo-fleet/docs/infra-dependencies.md`

**Interfaces:**
- Consumes: the patterns established in Tasks 4-8 (documents them; doesn't change them).

- [ ] **Step 1: Write `docs/onboarding.md`**

```markdown
# Onboarding a new app

Adding an app touches exactly one place: a new directory under `apps/`.
`bootstrap/` never changes -- its ApplicationSets discover `apps/*/argocd`
and `apps/*/kargo` from git and deploy them automatically on merge.

## The naming convention (load-bearing)

Pick one name and reuse it everywhere. For an app named `orders`:

| Thing | Value |
|---|---|
| Directory | `apps/orders/` |
| Argo CD AppProject | `orders` |
| Kargo Project | `orders` |
| Argo CD Applications | `orders-<stage>` |
| Namespaces | `orders-<stage>` |

## Pattern: external OCI chart (what akkoma and soju use)

Use this when the app is an independently published, versioned Helm chart
you don't want to vendor -- copying chart source in means manually
re-syncing on every upstream release.

1. `kargo/warehouse.yaml`: a `chart:` subscription against the chart's OCI
   registry, `semverConstraint` selecting real releases. `chart.name` must
   stay unset for `oci://` URLs.
2. `env/<stage>/release.yaml`: `chartVersion` (bumped by Kargo's
   `yaml-update` step on every promotion) plus a `values:` block for that
   stage's config.
3. `argocd/appset.yaml`: a `files` generator (not `directories`) reading
   `env/*/release.yaml`, templating a multi-source Application -- source 1
   is the OCI chart at `{{.chartVersion}}` with the stage's values spelled
   out under `helm.valuesObject`, templating only the individual string
   leaf fields that genuinely vary by stage (e.g.
   `domain: '{{.values.akkoma.domain}}'`, quoted). `valuesObject` is an
   object-typed field, so `valuesObject: '{{.values}}'` does NOT work --
   Argo CD's Go-template engine only substitutes into string fields (the
   same restriction documented for `syncPolicy`). For a boolean flag that's
   identical at every stage (e.g. `externalSecret.enabled`), just write it
   as a plain YAML boolean instead of templating it -- an unquoted
   `{{...}}` in that position is ambiguous with YAML flow-mapping syntax,
   and a quoted `"false"` is a non-empty string, which Helm/Sprig `if`
   treats as truthy. Source 2 is this repo's own path for that stage's
   `secret.sealed.yaml`, if any.
4. `kargo/tasks.yaml`: `git-clone` -> `yaml-update` (bump `chartVersion`) ->
   `git-commit` -> `git-push` -> `argocd-update`.

## Secrets: never rely on Helm `lookup`

Argo CD renders charts via `helm template` with no cluster access -- any
chart logic depending on `lookup` (common for "generate once, preserve
across upgrades" secrets) will regenerate random values on every sync
instead. Check whether the chart exposes an `existingSecret`/
`externalSecret` escape hatch (most well-maintained charts do); if so,
create the real Secret via Sealed Secrets (`task sealed-secrets:seal`,
see the repo root README) and reference it by name in `release.yaml`'s
`values:` block -- never set secret material directly in `release.yaml`,
which is committed in plaintext.

## Checklist before opening the PR

- [ ] `kargo/project.yaml` carries `argocd.argoproj.io/sync-wave: "-1"`.
- [ ] Every Application the pipeline syncs carries
      `kargo.akuity.io/authorized-stage: <project>:<stage>`.
- [ ] The Warehouse doesn't create a promote-loop: if promotions commit to
      main, don't also subscribe to main via git.
- [ ] New Kargo project -> new git write credentials for it.
```

- [ ] **Step 2: Write `docs/infra-dependencies.md`**

```markdown
# Adding a cluster-wide infra dependency

Use this for anything that needs to run identically on every cluster and
has no per-app promotion pipeline -- a controller, an operator, a
cert-manager-style singleton. `sealed-secrets` is the current example.

## Steps

1. Create `infrastructure/<name>/argocd/appset.yaml`. Use a `list`
   generator with one element per cluster destination -- there's no
   per-cluster directory to discover, just a fixed, known set of clusters
   (currently `demo1`, `demo2`).
2. Write `infrastructure/<name>/README.md` explaining what it is, why every
   cluster needs it, and any bootstrap step required before the
   ApplicationSet can sync cleanly (e.g. `sealed-secrets` needs its shared
   keypair pre-created and labeled `active` before the controller starts,
   or it generates its own cluster-specific key instead).
3. If the dependency needs repeatable operational commands (key rotation,
   cert renewal, anything you'd otherwise hand-run and forget the exact
   flags for), add them to the root `Taskfile.yml` under a
   `<name>:<verb>` namespace, matching `sealed-secrets:generate-keypair`/
   `sealed-secrets:rotate-keypair`/`sealed-secrets:seal`.
4. No changes to `bootstrap/` -- `infra-apps.yaml` already discovers
   `infrastructure/*/argocd` automatically.

## Candidates already identified but deferred

- **cert-manager**: deferred until real domains exist for `akkoma`/`soju`
  -- no TLS to issue yet, so installing it now would just be an untested,
  unused dependency.
```

- [ ] **Step 3: Validate markdown has no unresolved placeholders**

Run: `grep -rn "TBD\|TODO\|FIXME" docs/onboarding.md docs/infra-dependencies.md`
Expected: no output (empty grep = pass).

- [ ] **Step 4: Commit**

```bash
git add docs/onboarding.md docs/infra-dependencies.md
git commit -m "Add onboarding and infra-dependency docs"
```

---

### Task 10: Full-repo verification

**Files:** none created; this task only validates everything from Tasks 1-9.

- [ ] **Step 1: YAML-syntax-validate every YAML file in the repo**

Run:
```bash
cd /Users/ada/src/github.com/adamancini/argo-fleet
fail=0
while IFS= read -r f; do
  ruby -ryaml -e "YAML.load_stream(File.read('$f'))" 2>/dev/null && echo "OK   $f" || { echo "FAIL $f"; fail=1; }
done < <(find . -name '*.yaml' -not -path './.git/*' -not -path './.superpowers/*')
exit $fail
```
Expected: `OK` for every file, exit code `0`.

- [ ] **Step 2: Confirm every Kargo manifest matches what was live-verified during planning**

Run:
```bash
grep -n "semverConstraint" apps/akkoma/kargo/warehouse.yaml apps/soju/kargo/warehouse.yaml
grep -n "chartFrom" apps/akkoma/kargo/tasks.yaml apps/soju/kargo/tasks.yaml
```
Expected: `semverConstraint: '>=0.4.6'` in akkoma's warehouse, `semverConstraint: '>=0.1.7'` in soju's, and `chartFrom(vars.chart).Version` in both `tasks.yaml` files. These exact field names were confirmed live against the running Kargo control plane while planning (see Task 5, Step 3's note) -- this step catches any drift introduced while writing the files.

- [ ] **Step 3: Confirm no live-cluster-mutating commands were run**

Run: `git -C /Users/ada/src/github.com/adamancini/argo-fleet log --oneline`
Expected: every commit message matches Tasks 1-9 above (scaffolding, Taskfile, bootstrap, sealed-secrets infra, akkoma x2, soju x2, docs) -- nothing about installing controllers, generating keys, or applying to `demo1`/`demo2` directly. This confirms the plan's Global Constraint (no live apply) was actually honored.

- [ ] **Step 4: Verify `task --list` still works end-to-end**

Run: `task --list`
Expected: same three `sealed-secrets:*` tasks from Task 2, still listed with descriptions -- confirms nothing in Tasks 3-9 broke `Taskfile.yml`'s syntax.

---

## Manual steps (you run these, not part of this plan's execution)

Once Tasks 1-10 are complete and committed:

1. **Push the repo**: create `adamancini/argo-fleet` on GitHub, `git remote add origin git@github.com:adamancini/argo-fleet.git`, `git push -u origin main`.
2. **Generate the shared keypair**: `task sealed-secrets:generate-keypair` — creates real Secrets on `k3d-demo1` and `k3d-demo2`. Back up `.sealed-secrets-keypair/tls.key` out-of-band immediately.
3. **Bootstrap**: `argocd app create -f bootstrap/platform-aoa.yaml` against your Akuity Argo CD instance.
4. **Add Kargo git credentials** for the `akkoma` and `soju` projects (same pattern as `akp-platform`'s `add-credentials.sh` — worth porting that script over, or running the equivalent `kargo create repo-credentials` commands by hand).
5. **Seal the real secrets**: run each `task sealed-secrets:seal` command documented in `apps/akkoma/README.md` and `apps/soju/README.md`, for every stage. Commit and push the resulting `secret.sealed.yaml` files.
6. **Promote**: once Argo CD and Kargo pick everything up, promote the discovered Freight through `dev → staging → prod` via the Kargo UI/CLI, same as `rollouts-app` in `akp-platform`.
