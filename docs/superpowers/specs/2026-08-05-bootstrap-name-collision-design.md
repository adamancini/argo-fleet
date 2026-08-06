# Bootstrap Name Collision Design

**Goal:** Let `argo-fleet`'s bootstrap tree go live on the shared Argo CD
instance without colliding with `akp-platform`'s already-live bootstrap
resources of the same name.

## Background

`argo-fleet` and `akp-platform` both register against the same
Akuity-hosted Argo CD/Kargo instance (`ada-quickstart-argocd` /
`ada-quickstart-kargo`). While closing out the `AF-q1il` cluster-lifecycle
epic, `argo-fleet`'s own root bootstrap (`bootstrap/platform-aoa.yaml`) was
discovered to have never been applied to that instance. Attempting to
apply it now surfaced that it — and two more of `argo-fleet`'s bootstrap
resources — share exact resource names with `akp-platform`'s already-live
equivalents, all in the `argocd` namespace:

| Resource | Kind | `argo-fleet` file | Collides with (live, `akp-platform`) |
| --- | --- | --- | --- |
| `platform-aoa` | Application | `bootstrap/platform-aoa.yaml` | `argocd/platform-aoa` (repo: `akp-platform`, `Synced`/`Healthy`) |
| `argocd-apps` | ApplicationSet | `bootstrap/argocd-apps.yaml` | `argocd/argocd-apps` (repo: `akp-platform`, `Healthy`) |
| `kargo-apps` | ApplicationSet | `bootstrap/kargo-apps.yaml` | `argocd/kargo-apps` (repo: `akp-platform`, `Healthy`) |

Both repos independently converged on the same discovery convention
(`apps/*/argocd`, `apps/*/kargo`) and the same names for the resources that
implement it — unsurprising, since `argo-fleet`'s bootstrap layer was
modeled on `akp-platform`'s. Applying `argo-fleet`'s versions as-is,
especially with `--upsert`, risks overwriting `akp-platform`'s live
`platform-aoa` Application — which has `prune: true` — and deleting every
Application it currently manages (`argocd-guestbook-helm`,
`argocd-guestbook-helm-rendered`, `argocd-guestbook-kustomize`,
`argocd-guestbook-rendered`, `argocd-rollouts-app`, and their generated
children across `demo1`/`demo2`).

The *children* these ApplicationSets generate do not collide —
`argo-fleet`'s `apps/` directory currently holds `akkoma`/`soju`, producing
child names like `argocd-akkoma`/`kargo-soju`, distinct from
`akp-platform`'s `argocd-guestbook-helm` etc. Only the three top-level
bootstrap resource names collide.

This is scoped as a narrow, immediate fix: disambiguate the three
colliding names so `argo-fleet`'s tree can go live safely. It is explicitly
**not** the akp-platform/akp-infra consolidation migration (a separate,
larger effort to be designed later, once this is live and proven stable).
The naming chosen here (`fleet-` prefix) is a deliberate signal that these
names are temporary — expected to be dropped once `akp-platform`'s
originals are eventually decommissioned as part of that later migration.

## Design

Rename the three colliding resources by prefixing with `fleet-`, and
rename their files to match, so a resource's name is always recoverable
from its filename:

- `bootstrap/platform-aoa.yaml` → `bootstrap/fleet-platform-aoa.yaml`
  (`metadata.name: fleet-platform-aoa`)
- `bootstrap/argocd-apps.yaml` → `bootstrap/fleet-argocd-apps.yaml`
  (`metadata.name: fleet-argocd-apps`)
- `bootstrap/kargo-apps.yaml` → `bootstrap/fleet-kargo-apps.yaml`
  (`metadata.name: fleet-kargo-apps`)

No other field changes: same generators, same `source`/`destination`,
same `syncPolicy`. The child-application naming templates
(`argocd-{{path[1]}}`, `kargo-{{path[1]}}`) are unchanged — they don't
collide with anything, so touching them would be scope creep.

`bootstrap/infra-apps.yaml` (`metadata.name: infra-apps`) does not collide
with any live `akp-platform` resource and needs no change.

`README.md`'s two references to `bootstrap/platform-aoa.yaml` (in the
`Layout` and `Quickstart` sections) are updated to
`bootstrap/fleet-platform-aoa.yaml`, matching the renamed file.

## Verification

Split by what can run statically versus what touches the live shared
instance:

**Static (safe for any agent to run):**

- YAML syntax check on the three renamed files.
- Repo-wide grep confirming no remaining reference to the old unprefixed
  names (`platform-aoa`, `argocd-apps`, `kargo-apps`) outside of git
  history and this spec's own background section.

**Live (human-run only — this touches the shared Argo CD instance that
already serves the running `akp-platform` demo, so no agent may execute
these steps):**

1. Baseline: `argocd app list` and `argocd appset list` — confirm no
   `fleet-*`-named resource exists yet, and confirm the *unprefixed*
   `platform-aoa`/`argocd-apps`/`kargo-apps` still show `akp-platform` as
   their source repo, `Synced`/`Healthy`, with their current app count.
2. Apply: `argocd app create -f bootstrap/fleet-platform-aoa.yaml`.
3. Post-check: re-run `argocd app list`/`argocd appset list`. The
   load-bearing check is that the *original* `platform-aoa`,
   `argocd-apps`, `kargo-apps` are byte-for-byte unchanged from the
   baseline (same source repo, same app count, still `Synced`/`Healthy`)
   — proof nothing was clobbered.
4. Confirm the new `fleet-*` tree comes up `Synced`/`Healthy`, and that
   the `infra-*` children (`infra-gateway-api-crds`, `infra-openebs-localpv`,
   `infra-traefik-gateway`, and their per-cluster grandchildren) sync
   `Healthy` — this is the evidence AF-tqmb's Step 7 has been blocked on.

## Out of scope

- Migrating `akp-platform`'s app content into `argo-fleet` (separate
  future epic).
- Migrating `akp-infra`'s `01-argocd`/`02-kargo` Terraform into
  `argo-fleet` (separate future epic).
- Decommissioning `akp-platform`'s original (unprefixed) bootstrap
  resources — happens only once the above migrations land and are
  proven live.
- Any change to `infra-apps.yaml`, `platform-aoa.yaml`'s Application
  fields, or the child-naming templates.
