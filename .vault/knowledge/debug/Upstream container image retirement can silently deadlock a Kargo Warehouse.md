---
type: debug
project: argo-fleet
status: active
actionable: pending
epic: AF-j5rz
created: 2026-08-20
---

# Upstream container image retirement can silently deadlock a Kargo Warehouse before it's ever noticed

## Symptoms
Mid-epic, while seeding `release.yaml` files for all six arr-stack apps (AF-8r8l), a developer found `ghcr.io/hotio/overseerr` -- one of the epic's original six app images, already referenced in already-merged files (AF-hb2f's `appset-kargo.yaml`/`appproject.yaml`) -- was no longer a resolvable public image at all.

## Root cause
hotio retired `hotio/overseerr` in favor of `hotio/seerr` (Seerr v3). A Kargo `Warehouse` subscribed to a retired image with `imageSelectionStrategy: Digest`/`constraint: release` can never mint Freight (no manifest, no tag list, no digest to discover) -- its Stages are permanently dead, silently, with no error surfaced anywhere until someone tries to actually resolve or promote against that image.

## Detection method (reusable)
- `GET https://ghcr.io/token?scope=repository:<org>/<repo>:pull` returning `{"errors":[{"code":"DENIED",...}]}` on multiple consecutive attempts means the repo is absent/private -- no manifest exists to seed or promote against.
- Run a **control probe** with the identical method against known-good sibling images (here, the other 5 `hotio/*` images) to confirm the method itself is sound and the failure is specific to one image, not a token/auth/network problem.
- Cross-check the vendor's own docs (here, `hotio.dev/containers/<app>/`) for an explicit deprecation/migration notice -- it usually exists and names the successor image directly.

## Actionable guidance
- **Before an epic commits a per-app parameter table for an externally-maintained image family (hotio, linuxserver.io, etc.), resolve each image's current tag/digest live at authoring time**, not from memory or a prior epic's table -- this epic's roster was drafted before the overseerr retirement and the drift wasn't caught until implementation, three stories later, after the bad name was already merged.
- For any future *arr-family (or similar third-party-image-family) onboarding, add a pre-flight check (even a manual one) that resolves every planned image's current tag/digest via the ghcr.io anonymous-pull token endpoint (or `crane`/`skopeo`/`docker buildx imagetools`) BEFORE any story authors a Warehouse subscription against it -- this is cheap and would have caught this specific defect before any file merged.
- When seeding a `Digest`-strategy Warehouse's initial `release.yaml` value, resolve the **index/manifest-list digest**, not a per-platform child manifest digest (`docker manifest inspect --verbose` returns an array of child manifests; `docker buildx imagetools inspect --format '{{.Manifest.Digest}}'` / `crane digest` return the index digest that Kargo's Digest strategy actually resolves and that the promotion will write back). A per-platform digest would silently pin one architecture and never byte-match the first real promotion.
