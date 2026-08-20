---
type: pattern
project: argo-fleet
status: active
actionable: pending
epic: AF-j5rz
created: 2026-08-20
---

# Kargo Digest-strategy Warehouse -> app-template binding is a two-part contract, not one

## Context
AF-j5rz's arr-stack design used `imageSelectionStrategy: Digest` / `constraint: release` Warehouses (required because hotio images publish under a mutable `release` tag, not semver). This makes `release.yaml`'s `imageTag` key hold a `sha256:<hex>` **digest**, never a tag -- but that fact is not obvious from the key's own name, and two independent, real defects grew out of it before the epic's static suite caught up:

1. **Field defect**: the design spec's own snippet bound the digest to bjw-s app-template's `tag:` field (`tag: "{{.values.imageTag}}"`). A digest in a tag field renders `repository:sha256:...` -- not a valid OCI reference (a tag cannot contain `:`). The correct field is app-template's separate `digest:` field, which renders `repository@sha256:...`.
2. **Path defect**: even after fixing the field, the first corrected draft used `{{.values.imageTag}}`. Argo CD's git *files* generator exposes a discovered file's top-level keys with **no prefix** -- `imageTag` is top-level in `release.yaml`, so the correct path is `{{.imageTag}}`. `.values.imageTag` indexes an empty map (`values: {}` in every seeded file) and, under `goTemplateOptions: ["missingkey=error"]`, aborts rendering for ALL generated Applications; without that option it silently renders `<no value>`.

Both defects passed every earlier static check in their own story because each story's AC only checked the piece it owned (the seed shape, or the binding literal) in isolation -- neither checked the two together against the actual generator semantics until AF-6jta's own deliver-only developer read the *consumer* (`bjw-s/app-template`'s `_imageSpecificationToImage.tpl`) and the *generator's own docs*, not just the producer.

## The technique that found and proved it
- **Read the consumer, not just the producer.** `_imageSpecificationToImage.tpl`'s `tag` -> `printf "%s:%s"` vs `digest` -> `printf "%s@%s"` turned "a digest in a tag field feels wrong" into an exact, provable mechanism.
- **Counterfactual rendering.** Render the *wrong* binding alongside the *right* one and let `docker buildx imagetools inspect` return `ERROR: invalid reference format` for the wrong one. Converts "the spec says X" into a demonstrated fact in about two minutes.
- **Machine-check the param path against every seeded file**, not just one: `18/18 files have top-level imageTag; 0/18 have values.imageTag` is stronger evidence than reading the generator docs alone.
- **Use an in-repo sibling as the tie-breaker.** `apps/akkoma/argocd/appset.yaml` demonstrates both halves of the git-files param rule side by side (top-level `{{.chartVersion}}` vs nested `{{.values.image.tag}}`, the latter only because akkoma's `release.yaml` genuinely nests it) -- faster and more convincing than the upstream docs alone.

## Actionable guidance
- Whenever a Kargo Warehouse uses `imageSelectionStrategy: Digest`, treat "which field does the consuming chart bind this to" and "what is the discovered file's exact param path" as **two separate, both-mandatory verification steps** -- do not let a story's AC pass on the field check alone.
- For any future *arr-family-shaped ApplicationSet (matrix + git-files generator over a per-app/per-stage `release.yaml`), require: (a) a render of the consuming chart's templates for the specific `image.*` fields used, and (b) a machine-check of the param path against every real seeded file, not just the generator's schema docs.
- Prefer reading the sibling app's already-live-verified ApplicationSet in this repo before the upstream generator docs when the two questions could plausibly differ per-file-shape (top-level vs nested key).
