---
id: AF-yse2
title: "Bug: ghcr.io/hotio/overseerr retired -- rename merged appset-kargo.yaml/appproject.yaml entries to seerr"
status: open
priority: 0
type: bug
parent: AF-j5rz
created_at: 2026-08-19T15:40:11Z
created_by: ada
updated_at: 2026-08-19T15:40:11Z
content_hash: "sha256:dbcac6ab754cd198dae3fd77b9e766acd1330e8cc3b750764516a8054db52057"
blocks: [AF-6jta]
---

## Description
Description:
`apps/arr-stack/argocd/appset-kargo.yaml` and `apps/arr-stack/argocd/appproject.yaml` (both merged to `epic/AF-j5rz` via AF-hb2f, already accepted/closed) reference `overseerr`/`ghcr.io/hotio/overseerr`. hotio retired that image; the Warehouse subscription can never resolve, permanently deadlocking the overseerr Kargo trio. Rename the app to `seerr`/`ghcr.io/hotio/seerr` in both already-merged files. AF-hb2f itself is NOT reopened -- this is a follow-up patch, not a defect in AF-hb2f's own delivered scope (the image simply didn't exist at review time in the sense that mattered; it existed as a pullable tag but was already deprecated upstream in favor of `hotio/seerr`).

DISCOVERED DURING:
AF-8r8l's developer, while resolving each app's current digest to seed `release.yaml` files (see EVIDENCE below). Surfaced to Sr PM bug triage because AF-8r8l's developer released its claim rather than guess/fake a digest for a dead image.

SYMPTOMS:
- Any Kargo `Warehouse` subscribing to `ghcr.io/hotio/overseerr` with `imageSelectionStrategy: Digest` / `constraint: release` can never mint Freight -- the repository does not exist, so there is no tag list and no digest to discover.
- The `overseerr` Kargo trio (Project/Warehouse/3xStage) rendered by `appset-kargo.yaml`'s list-generator element is permanently dead the moment it reaches a live Argo CD/Kargo control plane (AF-o0rw/AF-c17x/AF-4wkn), independent of anything AF-8r8l or AF-6jta do.

EVIDENCE:
- ghcr.io anonymous-pull token endpoint for scope `repository:hotio/overseerr:pull` returned `{"errors":[{"code":"DENIED","message":"requested access to the resource is denied"}]}` on 3 consecutive attempts. `DENIED` means the repo is absent/private: no manifest, no tag list, therefore no digest exists to seed or to promote.
- Control probe (identical method) returned a valid anonymous pull token for `hotio/{sonarr,radarr,lidarr,bazarr,prowlarr,plex,qbittorrent,requestrr}` -- method is sound, `overseerr` specifically is gone. `hotio/jellyseerr` and `hotio/readarr` are likewise absent (not affected apps in this epic, noted for completeness).
- Root cause, hotio's own docs at https://hotio.dev/containers/overseerr/ (HTTP 200): "Warning -- Please migrate from hotio/overseerr to hotio/seerr. Seerr v3 has been released, so this should be safe to do."
- Successor verified live: `ghcr.io/hotio/seerr:release` resolves to `sha256:6ce42c9cdf64802f93639119009c1f24390bf17497775655698acd970e9920f7`.
- Currently committed (epic/AF-j5rz, `apps/arr-stack/argocd/appset-kargo.yaml`):
  ```yaml
        - name: overseerr
          image: ghcr.io/hotio/overseerr
  ```
- Currently committed (epic/AF-j5rz, `apps/arr-stack/argocd/appproject.yaml`):
  ```yaml
    description: DRY *arr family workloads + generated Kargo pipelines (PoC) -- Sonarr, Radarr, Lidarr, Bazarr, Prowlarr, Overseerr
  ```

POSSIBLE CAUSES:
1. hotio deprecated/deleted the `hotio/overseerr` image in favour of `hotio/seerr` (Seerr v3) -- confirmed root cause, not a hypothesis; see EVIDENCE.

CONFIG (if relevant):
Not applicable -- no live cluster config involved; this is a static manifest edit against already-merged files.

Acceptance Criteria:
1. `apps/arr-stack/argocd/appset-kargo.yaml`'s list-generator element renamed from `{name: overseerr, image: ghcr.io/hotio/overseerr}` to `{name: seerr, image: ghcr.io/hotio/seerr}` -- no other element in the list is touched.
2. `apps/arr-stack/argocd/appproject.yaml`'s `spec.description` string updated to read `...Prowlarr, Seerr` instead of `...Prowlarr, Overseerr`.
3. `helm template apps/arr-stack/argocd/kargo-chart --set appName=seerr --set image=ghcr.io/hotio/seerr` renders a well-formed, app-name-scoped Project/Warehouse/3xStage/PromotionTask set with zero unresolved placeholders (same render-diff check AF-hb2f itself used) -- the vendored chart is already parameterized and requires no changes of its own.
4. Repo-wide `grep -rniw overseerr` under `apps/arr-stack/` returns no matches after the fix (case-insensitive, whole-word).
5. [Unwanted] `bootstrap/*.yaml` is not modified by this fix.
6. [Unwanted] No other list element (`sonarr`, `radarr`, `lidarr`, `bazarr`, `prowlarr`) is altered.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory -- ApplicationSet list-generator conventions, Kargo Warehouse/Digest-strategy semantics), devops-toolkit:yaml-kubernetes-validator

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-19T15:40:15Z dep_added: blocks AF-6jta

## Links
- Parent: [[AF-j5rz]]
- Blocks: [[AF-6jta]]

## Comments
