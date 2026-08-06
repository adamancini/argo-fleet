# Bootstrap Name Collision Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Task 3 is reference material only — do not execute it.** Tasks 1-2 only rename/edit files in this repo's working tree and run read-only static checks (YAML parse, grep). Task 3 documents the steps that apply these manifests to the shared, live Argo CD instance already serving the running `akp-platform` demo. Per the spec's Verification section, those steps are **human-run only — no agent may execute them.** If you are an agent executing this plan and you reach Task 3, stop and hand it back rather than running its commands.

**Goal:** Rename `argo-fleet`'s three bootstrap resources that collide with `akp-platform`'s already-live equivalents (`platform-aoa`, `argocd-apps`, `kargo-apps`), so `argo-fleet`'s bootstrap tree can go live on the shared Argo CD instance without clobbering `akp-platform`.

**Architecture:** Pure rename — `git mv` each of the three colliding files to a `fleet-`-prefixed filename, update the matching `metadata.name` (and one self-referential comment) inside each, then fix the two `README.md` references to match. No field, generator, template, or sync-policy changes.

**Tech Stack:** Argo CD (`Application`, `ApplicationSet` manifests), YAML, Markdown (`README.md`).

## Global Constraints

- Only these three resources are renamed: `platform-aoa` → `fleet-platform-aoa`, `argocd-apps` → `fleet-argocd-apps`, `kargo-apps` → `fleet-kargo-apps`. `infra-apps` (in `bootstrap/infra-apps.yaml`) does not collide and is not touched.
- Rename filenames to match the new `metadata.name` exactly, so a resource's name is always recoverable from its filename.
- No other field changes: same `generators`, same `source`/`destination`, same `syncPolicy`. The child-application naming templates (`argocd-{{path[1]}}`, `kargo-{{path[1]}}`) are unchanged.
- This is a narrow, immediate fix — not the `akp-platform`/`akp-infra` consolidation migration. The `fleet-` prefix is a deliberate, temporary signal, expected to be dropped once that later migration lands.
- The live-instance verification steps (apply + post-check against the shared Argo CD instance) are human-run only. No task in this plan except the reference-only Task 3 touches, or documents touching, that instance — and Task 3 itself must not be executed by an agent.

---

## File Structure

```text
argo-fleet/
├── README.md                              # modified: 2 references updated
└── bootstrap/
    ├── platform-aoa.yaml                  # renamed -> fleet-platform-aoa.yaml
    ├── argocd-apps.yaml                   # renamed -> fleet-argocd-apps.yaml
    ├── kargo-apps.yaml                    # renamed -> fleet-kargo-apps.yaml
    └── infra-apps.yaml                    # unchanged
```

---

### Task 1: Rename the three colliding bootstrap manifests

**Files:**
- Rename + modify: `bootstrap/platform-aoa.yaml` → `bootstrap/fleet-platform-aoa.yaml`
- Rename + modify: `bootstrap/argocd-apps.yaml` → `bootstrap/fleet-argocd-apps.yaml`
- Rename + modify: `bootstrap/kargo-apps.yaml` → `bootstrap/fleet-kargo-apps.yaml`

**Interfaces:**
- Produces: three renamed files with `metadata.name: fleet-platform-aoa`, `metadata.name: fleet-argocd-apps`, `metadata.name: fleet-kargo-apps` respectively. Task 2's README edits reference the exact new path `bootstrap/fleet-platform-aoa.yaml` produced here.

- [ ] **Step 1: Rename `platform-aoa.yaml` and update its name + self-referential comment**

```bash
git -C /Users/ada/src/github.com/adamancini/argo-fleet mv bootstrap/platform-aoa.yaml bootstrap/fleet-platform-aoa.yaml
```

Edit `bootstrap/fleet-platform-aoa.yaml`: the file currently reads (in full):

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

Replace it with (only the comment's filename and `metadata.name` change):

```yaml
# Root app-of-apps. Apply this ONCE against the Argo CD control plane
# (`argocd app create -f bootstrap/fleet-platform-aoa.yaml`) and everything
# else in this repo is discovered and deployed automatically by the
# ApplicationSets in this directory. Onboarding a new infra dependency or
# app never requires touching bootstrap/ again.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fleet-platform-aoa
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

- [ ] **Step 2: Rename `argocd-apps.yaml` and update its name**

```bash
git -C /Users/ada/src/github.com/adamancini/argo-fleet mv bootstrap/argocd-apps.yaml bootstrap/fleet-argocd-apps.yaml
```

In `bootstrap/fleet-argocd-apps.yaml`, change only:

```yaml
metadata:
  name: argocd-apps
```

to:

```yaml
metadata:
  name: fleet-argocd-apps
```

Every other line (comment, `generators`, `template.metadata.name: 'argocd-{{path[1]}}'`, `spec.source`, `destination`, `syncPolicy`) stays byte-for-byte identical.

- [ ] **Step 3: Rename `kargo-apps.yaml` and update its name**

```bash
git -C /Users/ada/src/github.com/adamancini/argo-fleet mv bootstrap/kargo-apps.yaml bootstrap/fleet-kargo-apps.yaml
```

In `bootstrap/fleet-kargo-apps.yaml`, change only:

```yaml
metadata:
  name: kargo-apps
```

to:

```yaml
metadata:
  name: fleet-kargo-apps
```

Every other line (the two comment blocks, `generators`, `template.metadata.name: 'kargo-{{path[1]}}'`, `template.spec.project: '{{path[1]}}'`, `source`, `destination`, `syncPolicy`, `syncOptions`) stays byte-for-byte identical.

- [ ] **Step 4: Validate YAML syntax on all three renamed files**

Run:

```bash
for f in bootstrap/fleet-platform-aoa.yaml bootstrap/fleet-argocd-apps.yaml bootstrap/fleet-kargo-apps.yaml; do
  ruby -ryaml -e "YAML.load_stream(File.read('/Users/ada/src/github.com/adamancini/argo-fleet/$f'))" && echo "OK: $f"
done
```

Expected: `OK: bootstrap/fleet-platform-aoa.yaml`, `OK: bootstrap/fleet-argocd-apps.yaml`, `OK: bootstrap/fleet-kargo-apps.yaml` — no exceptions.

- [ ] **Step 5: Confirm `git mv` was tracked as renames, not delete+add**

```bash
git -C /Users/ada/src/github.com/adamancini/argo-fleet status
```

Expected: three entries under "Changes to be committed" reading `renamed: bootstrap/platform-aoa.yaml -> bootstrap/fleet-platform-aoa.yaml` (and the `argocd-apps`/`kargo-apps` equivalents), each also showing as modified (the content edit alongside the rename).

- [ ] **Step 6: Commit**

```bash
git -C /Users/ada/src/github.com/adamancini/argo-fleet add bootstrap/fleet-platform-aoa.yaml bootstrap/fleet-argocd-apps.yaml bootstrap/fleet-kargo-apps.yaml
git -C /Users/ada/src/github.com/adamancini/argo-fleet commit -m "bootstrap: prefix colliding resource names with fleet-"
```

---

### Task 2: Update README.md and verify no stale references remain

**Files:**
- Modify: `README.md:12`, `README.md:31`

**Interfaces:**
- Consumes: the renamed path `bootstrap/fleet-platform-aoa.yaml` produced in Task 1, Step 1.
- Produces: a repo in which the only remaining occurrences of the old unprefixed names (`platform-aoa`, `argocd-apps`, `kargo-apps`) are in git history and in dated planning documents that predate this fix (historical records, not live references) — the final check in Step 2 enumerates and confirms exactly which files those are.

- [ ] **Step 1: Update both `README.md` references to `platform-aoa.yaml`**

Change:

```markdown
- `bootstrap/` — the one manifest you apply by hand
  (`bootstrap/platform-aoa.yaml`); everything else is discovered
  automatically from `infrastructure/*/argocd` and `apps/*/{argocd,kargo}`.
```

to:

```markdown
- `bootstrap/` — the one manifest you apply by hand
  (`bootstrap/fleet-platform-aoa.yaml`); everything else is discovered
  automatically from `infrastructure/*/argocd` and `apps/*/{argocd,kargo}`.
```

And change:

```markdown
2. `argocd app create -f bootstrap/platform-aoa.yaml` — the only manifest
   applied by hand; bootstraps everything else.
```

to:

```markdown
2. `argocd app create -f bootstrap/fleet-platform-aoa.yaml` — the only manifest
   applied by hand; bootstraps everything else.
```

- [ ] **Step 2: Repo-wide grep confirming no live stale reference to the old unprefixed names**

Run:

```bash
grep -rnP --exclude-dir=.git '(?<!fleet-)(platform-aoa|argocd-apps|kargo-apps)' /Users/ada/src/github.com/adamancini/argo-fleet
```

Expected: every remaining hit is in one of these five pre-existing files (dated planning documents that record past design decisions — not live references — plus this fix's own spec, which mentions the old names in its Background section by design):

- `docs/superpowers/specs/2026-08-05-bootstrap-name-collision-design.md`
- `docs/superpowers/specs/2026-08-05-cluster-lifecycle-and-ingress-storage-design.md`
- `docs/superpowers/specs/2026-08-04-argo-fleet-bootstrap-design.md`
- `docs/superpowers/plans/2026-08-04-argo-fleet-bootstrap.md`
- `docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md`

No hit should appear in `README.md`, `bootstrap/*.yaml`, or any other file. If one does, that file was missed by Task 1 or Step 1 above — go back and fix it before proceeding.

- [ ] **Step 3: Commit**

```bash
git -C /Users/ada/src/github.com/adamancini/argo-fleet add README.md
git -C /Users/ada/src/github.com/adamancini/argo-fleet commit -m "docs: update README bootstrap reference to fleet-platform-aoa.yaml"
```

---

### Task 3: Live-instance verification (reference only — human-run, do NOT execute as an agent)

This task is documentation of the steps a human runs against the shared Akuity-hosted Argo CD instance after Tasks 1-2 are merged. **No agent may execute any command in this task.** It is included so the plan is complete against the spec, and so a human executing it by hand has the exact commands in one place.

**Files:** none — this task touches only the live Argo CD/Kargo instance, not this repository.

- [ ] **Step 1 (human): Baseline the live instance**

```bash
argocd app list
argocd appset list
```

Confirm: no `fleet-*`-named resource exists yet, and the *unprefixed* `platform-aoa`/`argocd-apps`/`kargo-apps` still show `akp-platform` as their source repo, `Synced`/`Healthy`, with their current app count. Record this output — it's the baseline Step 3 compares against.

- [ ] **Step 2 (human): Apply the renamed bootstrap Application**

```bash
argocd app create -f /Users/ada/src/github.com/adamancini/argo-fleet/bootstrap/fleet-platform-aoa.yaml
```

- [ ] **Step 3 (human): Post-check — confirm nothing was clobbered**

```bash
argocd app list
argocd appset list
```

The load-bearing check: the *original* `platform-aoa`, `argocd-apps`, `kargo-apps` are byte-for-byte unchanged from the Step 1 baseline (same source repo, same app count, still `Synced`/`Healthy`). If any of those three regressed, stop — do not proceed to Step 4 — and investigate before touching anything further.

- [ ] **Step 4 (human): Confirm the new fleet-* tree comes up healthy**

Confirm the new `fleet-platform-aoa`, `fleet-argocd-apps`, `fleet-kargo-apps` resources sync `Synced`/`Healthy`, and that the `infra-*` children (`infra-gateway-api-crds`, `infra-openebs-localpv`, `infra-traefik-gateway`, and their per-cluster grandchildren) sync `Healthy` — this is the evidence AF-tqmb's Step 7 has been blocked on.
