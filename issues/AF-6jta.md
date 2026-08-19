---
id: AF-6jta
title: "Implement arr-stack workloads ApplicationSet matrix generator"
status: open
priority: 1
type: task
parent: AF-j5rz
created_at: 2026-08-18T18:56:00Z
created_by: ada
updated_at: 2026-08-19T15:02:53Z
content_hash: "sha256:a956fbb5122e608b3291811da5c00644c67f54b48d482c13eefa148315ec8042"
blocked_by: [AF-8r8l]
blocks: [AF-vm0q, AF-o0rw]
was_blocked_by: [AF-iv8x]
---

## Description
Description:
Implement `apps/arr-stack/argocd/appset-workloads.yaml` -- the matrix-generator ApplicationSet that fans out 6 apps x 3 stages = 18 workload Applications, each rendering the bjw-s `app-template` OCI chart via `helm.values` (a raw multi-line string) with the `hasDownloads` conditional persistence block working in both branches.

**This story is written for the confirmed-supported outcome of the spike (AF-iv8x, already resolved -- matrix/git-files sibling-param interpolation is supported).**

BUG RESOLUTION (AF-hb2f discovered-bug follow-up, applied here before this story is claimed):
AF-hb2f's delivered `tasks.yaml` writes `${{ imageFrom(vars.image).Digest }}` (a `sha256:<hex>` string) into `release.yaml`'s `imageTag` key -- confirmed by AF-hb2f's own verified PROOF, because its `warehouse.yaml` uses `imageSelectionStrategy: Digest`, under which `.Tag` is invariantly the constant string `release` and only `.Digest` carries promotion signal. `imageTag` therefore holds a digest for the entire lifetime of this design, never a tag. This story's original draft bound that value into bjw-s app-template's `tag:` field (`tag: "{{.values.imageTag}}"`), which renders `repository:sha256:...` -- not a valid OCI reference, since a tag cannot contain a colon. Fixed here: bind it to app-template's `digest:` field instead (`digest: "{{.values.imageTag}}"`), which app-template's `_imageSpecificationToImage.tpl` renders as `repository@sha256:...` -- the correct, parseable form. The `imageTag` KEY NAME is unchanged (fixed by AF-hb2f's already-merged, out-of-scope-to-reopen `yaml-update` step); only the binding on this story's side changes, from `tag:` to `digest:`. AF-8r8l (this story's blocker) is amended in lockstep to seed `release.yaml`'s `imageTag` with a real, resolvable digest per app rather than the literal string `release`, so this story's very first render (before any Kargo promotion has run) also resolves to a genuinely pullable image reference.

Context:
`apps/arr-stack/env/<app>/<stage>/release.yaml` (AF-8r8l, blocking this story) must already exist for the inner `git files` generator to discover anything -- an ApplicationSet git-files generator only picks up paths present at the revision it reads. `apps/arr-stack/argocd/appset-kargo.yaml` (AF-hb2f) already exists and independently maintains its own copy of the same 6-app parameter subset (name + image only, no port/hasDownloads) -- this story's `appset-workloads.yaml` maintains a second, richer copy (name + image + port + hasDownloads) of overlapping app metadata. Drift between the two lists (an app added to one and not the other, a typo'd image repo) is exactly the class of bug the static verification story (AF-vm0q) exists to catch -- this story must not introduce that drift at authoring time by copying the per-app parameter table from the epic body exactly, not from memory or from `appset-kargo.yaml`'s narrower list.

`helm.values` (a raw multi-line string), not `helm.valuesObject`, is required here: `valuesObject` is a structured/object field (backed by `RawExtension`), so Argo CD's Go-template substitution only lands on string leaves and cannot build the conditional `hasDownloads` persistence block -- `apps/akkoma/argocd/appset.yaml`'s own header comment documents this exact restriction for a different reason (stage-varying leaf values), and this design needs the SAME underlying mechanism (`values` as a plain string, re-parsed as YAML by Helm after Go-template substitution) to make `{{- if eq .hasDownloads "true"}}...{{- end}}` possible at all. This is a deliberate departure from `akkoma`'s pattern, not an inconsistency.

This ApplicationSet uses a static per-app `list` generator with an inline `destination.name` conditional (`demo2` for `prod`, `demo1` otherwise) -- NOT a `clusters: {}` generator. This repo's own prior-epic finding (`.vault/knowledge/decisions/Argo CD clusters generator selector convention on Akuity-hosted instances.md`) confirmed a bare `clusters: {}` generator on this exact shared instance returns FOUR clusters (`demo1`, `demo2`, the control plane `in-cluster`, and `kargo`), not the two intended -- this design's static list sidesteps that risk entirely by construction, but if a FUTURE iteration of this design ever switches to cluster-discovery-based targeting, it MUST copy the `NotIn: [in-cluster, kargo]` selector convention already established fleet-wide (`docs/infra-dependencies.md`), not a bare `clusters: {}`. This story does not make that switch; it's a standing caution for future work, not an action item here.

USER INTENT:
A developer reading `appset-workloads.yaml` needs to see, in one file, the complete DRY claim for the workload half of this design: one template, 18 generated instances, differing only in the four leaf values (`name`, `image`, `port`, `hasDownloads`) the per-app parameter table declares -- and needs to trust that a promotion writing a new digest to a `release.yaml` file is picked up automatically, without ever touching this file again, AND that the resulting image reference is always parseable (never a colon-separated tag string built from a digest).

IMPLEMENTATION:
Create `apps/arr-stack/argocd/appset-workloads.yaml` verbatim per the design spec, WITH THE CORRECTED BINDING (matrix generator: outer `list` of 6 apps, inner `git files` generator over `apps/arr-stack/env/{{.name}}/*/release.yaml`):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: arr-stack-workloads
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - matrix:
        generators:
          - list:
              elements:
                - name: sonarr
                  image: ghcr.io/hotio/sonarr
                  port: "8989"
                  hasDownloads: "true"
                - name: radarr
                  image: ghcr.io/hotio/radarr
                  port: "7878"
                  hasDownloads: "true"
                - name: lidarr
                  image: ghcr.io/hotio/lidarr
                  port: "8686"
                  hasDownloads: "true"
                - name: bazarr
                  image: ghcr.io/hotio/bazarr
                  port: "6767"
                  hasDownloads: "true"
                - name: prowlarr
                  image: ghcr.io/hotio/prowlarr
                  port: "9696"
                  hasDownloads: "false"
                - name: overseerr
                  image: ghcr.io/hotio/overseerr
                  port: "5055"
                  hasDownloads: "false"
          - git:
              repoURL: https://github.com/adamancini/argo-fleet.git
              revision: HEAD
              files:
                - path: "apps/arr-stack/env/{{.name}}/*/release.yaml"
  template:
    metadata:
      name: "arr-{{.name}}-{{.path.basename}}"
      annotations:
        kargo.akuity.io/authorized-stage: "{{.name}}:{{.path.basename}}"
    spec:
      project: arr-stack
      source:
        repoURL: oci://ghcr.io/bjw-s-labs/helm/app-template
        targetRevision: 4.x
        helm:
          values: |
            defaultPodOptions:
              automountServiceAccountToken: false
            controllers:
              main:
                pod:
                  securityContext:
                    fsGroup: 100
                    fsGroupChangePolicy: OnRootMismatch
                containers:
                  main:
                    image:
                      repository: {{.image}}
                      digest: "{{.values.imageTag}}"
                    env:
                      - name: PUID
                        value: "1000"
                      - name: PGID
                        value: "1000"
                      - name: TZ
                        value: "America/New_York"
                      - name: UMASK
                        value: "002"
            service:
              main:
                enabled: true
                ports:
                  http:
                    port: 80
                    targetPort: {{.port}}
            ingress:
              main:
                enabled: false
            persistence:
              config:
                accessMode: ReadWriteOnce
                size: 1Gi
{{- if eq .hasDownloads "true"}}
              downloads:
                accessMode: ReadWriteOnce
                size: 1Gi
                advancedMounts:
                  main:
                    main:
                      - path: /data
{{- end}}
      destination:
        name: "{{- if eq .path.basename \"prod\" -}}demo2{{- else -}}demo1{{- end -}}"
        namespace: "arr-stack-{{.path.basename}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```
Note the ONE deviation from the design spec's own literal snippet (`docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md` lines ~203-205): `image.digest: "{{.values.imageTag}}"` replaces the spec's `image.tag: "{{.values.imageTag}}"`. This is a deliberate, verified correction (see BUG RESOLUTION above), not a transcription error -- the spec's own snippet is tracked separately as a documentation-only fix, non-blocking for this story.

No explicit `storageClassName` is set on the `config`/`downloads` PVCs (relies on the cluster's default StorageClass, per the design spec) -- AF-pfbv (human-gated) independently verifies this assumption holds on the real instance before any live deploy trusts it; this story does not add `storageClassName` itself (that would silently diverge from the committed spec without the epic's own explicit verification gate having run).

KEY FILES:
Create: `apps/arr-stack/argocd/appset-workloads.yaml`. Reference-only (not modified): `apps/arr-stack/argocd/appset-kargo.yaml` (AF-hb2f, cross-check the per-app parameter table matches), `apps/akkoma/argocd/appset.yaml` (reference for the `valuesObject` vs `values` restriction), `apps/arr-stack/env/*/*/release.yaml` (AF-8r8l, the files this ApplicationSet's `git files` generator discovers).

OUT OF SCOPE:
- `storageClassName` on the PVCs -- deliberately left unset per the committed spec; AF-pfbv verifies the underlying assumption, this story does not pre-empt that verification by adding it speculatively.
- Any change to `appset-kargo.yaml`'s own per-app list -- if a drift is found between the two lists during authoring, fix THIS file to match the epic's parameter table (the source of truth), do not "fix" `appset-kargo.yaml` as a side effect of this story (that would be an undeclared change to AF-hb2f's already-delivered scope).
- Renaming the `imageTag` key or touching AF-hb2f's `tasks.yaml` -- fixed by AF-hb2f's already-delivered `yaml-update` step; this story only changes which app-template field consumes that value (`digest:` instead of `tag:`), never the upstream key name.
- Switching to a `clusters: {}` generator -- explicitly out of scope; this story uses the static per-app `list` + inline `destination.name` conditional exactly as specified.
- Real NFS-backed shared media volumes, ingress/HTTPRoute wiring -- both explicitly out of scope for this PoC per the epic body.
- Correcting the design spec doc's own snippet -- tracked as a documentation-only follow-up outside the execution path, not this story's concern.

DIFF BUDGET:
1 new file, 0 modified. ~75-90 LOC (matches the design spec's literal YAML length).

CONSUMES:
- AF-8r8l: apps/arr-stack/env/<app>/<stage>/release.yaml (18 files) -> promotion-target contract file
    schema: imageTag (string, "sha256:<64 lowercase hex chars>" -- always a digest, seeded per-app with a real resolvable value, never the literal tag name), values (object)
    source: AF-8r8l's own PRODUCES block (as amended by this same bug-triage pass)
- AF-iv8x: this issue's own Notes/Comments -> decision record
    spec: supported: true (confirmed -- this story proceeds as written)
    source: the spike's empirical finding (already resolved, dependency removed)

PRODUCES:
- `apps/arr-stack/argocd/appset-workloads.yaml` -> ApplicationSet `arr-stack-workloads`
    spec: generators: [matrix: [list (6 apps: name/image/port/hasDownloads), git files (path: apps/arr-stack/env/{{.name}}/*/release.yaml)]]; template.spec.source: oci://ghcr.io/bjw-s-labs/helm/app-template@4.x, helm.values (raw string, NOT valuesObject); template.spec.source's rendered image block binds `digest: "{{.values.imageTag}}"` (NOT `tag:`); template.spec.destination.name: demo2 if stage==prod else demo1; template.spec.destination.namespace: arr-stack-{{.path.basename}}
    source: docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md, WITH the digest-binding correction from this bug-triage pass (spec's own literal snippet is a tracked doc-only defect, see BUG RESOLUTION)

TESTING:
No unit-test suite exists for this repo's GitOps manifests -- verification is static/render-level only for this story (no live cluster touch; the first live confirmation of actual sync health happens in AF-o0rw/AF-c17x, human-gated):
- `ruby -ryaml -e "YAML.load_stream(File.read('apps/arr-stack/argocd/appset-workloads.yaml'))" && echo OK`.
- Manually render the `helm.values` block for both a `hasDownloads: true` app (e.g. sonarr) and a `hasDownloads: false` app (e.g. prowlarr) by hand-substituting the Go-template fields (using a real `sha256:<hex>` value for `{{.values.imageTag}}`, matching AF-8r8l's seed shape), then run each through `helm template <local copy or OCI pull of ghcr.io/bjw-s-labs/helm/app-template:4.x>` -- confirm the `downloads` persistence block is present for the `true` case and absent for the `false` case, and confirm the rendered container image reference is `<repository>@sha256:<hex>` (never `<repository>:sha256:<hex>`) in both branches.
- Cross-file contract check (also re-verified independently in AF-vm0q): the app-name/image set in this file's `list` generator exactly matches `appset-kargo.yaml`'s (AF-hb2f) `list` generator's name/image pairs, and exactly matches the 6-app, 18-directory set AF-8r8l seeded.
- Grep this file for `tag: "{{.values.imageTag}}"` and confirm NO match (the bug this story exists to avoid reintroducing); confirm `digest: "{{.values.imageTag}}"` IS present exactly once.
- `devops-toolkit:yaml-kubernetes-validator` and `devops-toolkit:helm-chart-developer` consulted before finalizing.

Acceptance Criteria:
1. [Ubiquitous] `apps/arr-stack/argocd/appset-workloads.yaml` uses a `matrix` generator (outer `list` of 6 apps, inner `git files` generator over `apps/arr-stack/env/{{.name}}/*/release.yaml`).
2. [Ubiquitous] The rendered template uses `helm.values` (raw string), never `helm.valuesObject`, for the `app-template` source.
3. [Ubiquitous] The container image block binds `digest: "{{.values.imageTag}}"` -- it shall never bind that value to `tag:`.
4. [Event] Rendering for a `hasDownloads: true` app includes the `downloads` persistence block with `advancedMounts.main.main[0].path: /data`; rendering for a `hasDownloads: false` app omits it entirely.
5. [Event] Rendering the container image block with a real `sha256:<hex>` value substituted for `{{.values.imageTag}}` produces `<repository>@sha256:<hex>` -- a syntactically valid OCI image reference.
6. [Ubiquitous] The generator produces exactly 18 Applications (6 apps x 3 stages), each named `arr-{{.name}}-{{.path.basename}}` and annotated `kargo.akuity.io/authorized-stage: "{{.name}}:{{.path.basename}}"`.
7. [Ubiquitous] `destination.name` resolves to `demo2` for `prod` and `demo1` for `dev`/`staging`; `destination.namespace` resolves to `arr-stack-<stage>` (shared across all 6 apps, per the epic's namespace decision).
8. [Ubiquitous] No `storageClassName` is set on either PVC (deliberately deferred to AF-pfbv's verification, not silently added or silently omitted-without-acknowledgment).
9. [Unwanted] The app-name/image list in this file shall not diverge from `appset-kargo.yaml`'s (AF-hb2f) app-name/image list.
10. [Unwanted] This ApplicationSet's generator shall not use `clusters: {}`.
11. [Unwanted] This file shall not contain the substring `tag: "{{.values.imageTag}}"` -- the exact regression this story's bug-triage pass exists to prevent.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory -- its GitOps app-patterns reference material for the matrix/git-files generator shape), devops-toolkit:helm-chart-developer (mandatory -- bjw-s app-template values shape, specifically the `image.digest` vs `image.tag` fields in `_imageSpecificationToImage.tpl`), devops-toolkit:yaml-kubernetes-validator (mandatory)

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-18T18:56:06Z dep_added: blocked_by AF-8r8l
- 2026-08-18T18:56:07Z dep_added: blocked_by AF-iv8x
- 2026-08-18T18:57:54Z dep_added: blocks AF-vm0q
- 2026-08-18T19:06:18Z dep_added: blocks AF-o0rw
- 2026-08-19T14:44:32Z dep_removed: was_blocked_by AF-iv8x

## Links
- Parent: [[AF-j5rz]]
- Blocks: [[AF-vm0q]], [[AF-o0rw]]
- Blocked by: [[AF-8r8l]]
- Was blocked by: [[AF-iv8x]]

## Comments

### 2026-08-19T15:02:53Z ada
BUG TRIAGE (Sr PM): discovered by AF-hb2f's deliver-only follow-up developer -- this story's original draft bound release.yaml's imageTag value into bjw-s app-template's tag: field (tag: "{{.values.imageTag}}"), but imageTag always holds a sha256 digest (per AF-hb2f's delivered tasks.yaml/warehouse.yaml, Digest selection strategy). A digest in a tag field renders repository:sha256:..., which is not a valid OCI reference (tags cannot contain a colon); app-template's own _imageSpecificationToImage.tpl exposes a separate digest: field that renders the correct repository@sha256:... form. Resolution applied directly to this story's body: bind digest: "{{.values.imageTag}}" instead of tag:. AF-8r8l (this story's blocker) amended in lockstep to seed release.yaml with a real per-app digest rather than the literal string release. AF-vm0q (capstone) amended to verify the corrected binding and add a regression check. AF-hb2f itself is NOT reopened -- the imageTag key name is unchanged.
