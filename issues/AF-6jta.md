---
id: AF-6jta
title: "Implement arr-stack workloads ApplicationSet matrix generator"
status: closed
priority: 1
type: task
parent: AF-j5rz
created_at: 2026-08-18T18:56:00Z
created_by: ada
updated_at: 2026-08-19T20:07:17Z
content_hash: "sha256:5d8cc4b7ff0eaf8c34c50eeded85cf0a99d2197c062ef80c380eb597a21d4b21"
was_blocked_by: [AF-iv8x, AF-8r8l, AF-yse2]
assignee: dev-AF-6jta
follows: [AF-iv8x, AF-8r8l, AF-yse2, AF-hb2f]
labels: [accepted]
closed_at: 2026-08-19T20:07:16Z
close_reason: "Accepted: matrix-generator ApplicationSet verified independently -- digest binding to imageTag confirmed correct via grep + real helm render (bjw-s app-template 4.6.2); hasDownloads true/false rendering confirmed (2 PVCs plus /data vs 1 PVC, no /data); image refs render as valid at-sha256 OCI references; cross-file app/image list matches appset-kargo.yaml and all 18 seeded release.yaml dirs exactly; no overseerr, clusters generator, storageClassName, or tag-binding literals; destination demo2/demo1 plus arr-stack-stage namespace logic correct; port 5055 reconfirmed for hotio/seerr with credible dual-source evidence; diff is exactly 1 file added (173 lines, explained by repo heavily-commented-manifest convention); pvg verify PASSED; pvg gates PASS; e2e SHA matches proof (3f0fd80)."
---

## Description
Description:
Implement `apps/arr-stack/argocd/appset-workloads.yaml` -- the matrix-generator ApplicationSet that fans out 6 apps x 3 stages = 18 workload Applications, each rendering the bjw-s `app-template` OCI chart via `helm.values` (a raw multi-line string) with the `hasDownloads` conditional persistence block working in both branches.

**This story is written for the confirmed-supported outcome of the spike (AF-iv8x, already resolved -- matrix/git-files sibling-param interpolation is supported).**

**HARD BLOCK, added by this bug-triage pass: this story is now `blocked_by` AF-yse2 (the bug that patches AF-hb2f's already-merged `appset-kargo.yaml`/`appproject.yaml` from `overseerr`/`ghcr.io/hotio/overseerr` to `seerr`/`ghcr.io/hotio/seerr`). Do not claim this story until AF-yse2 is closed -- this story's own cross-check AC (#9 below) compares this file's app-name/image list against `appset-kargo.yaml`'s, and that comparison is only meaningful once AF-yse2's patch has landed.**

ROSTER CORRECTION (bug-triage pass, applied here before this story is claimed): the sixth app was originally `overseerr`/`ghcr.io/hotio/overseerr`/port `5055`. hotio retired that image in favour of `hotio/seerr` (Seerr v3) -- `ghcr.io/hotio/overseerr` is no longer a resolvable public image (confirmed via 3 consecutive `DENIED` responses from the ghcr.io anonymous-pull token endpoint, and hotio's own docs at https://hotio.dev/containers/overseerr/, which instruct migrating to `hotio/seerr`). The IMPLEMENTATION section below uses `seerr`/`ghcr.io/hotio/seerr` in the matrix generator's `list` element. **Port 5055 is CARRIED OVER from overseerr's hotio docs and is NOT yet independently reconfirmed for the seerr image** -- before hard-coding port `5055` for `seerr`, re-check hotio's `hotio/seerr` container docs/labels (https://hotio.dev/containers/seerr/ once published, or the image's own `LABEL`/`EXPOSE` metadata) for the actual listening port; if it differs from `5055`, use the confirmed value instead and note the discrepancy in delivery evidence. AF-8r8l (this story's blocker) and the epic's own per-app parameter table (AF-j5rz) have been corrected in lockstep.

BUG RESOLUTION (AF-hb2f discovered-bug follow-up, applied here before this story is claimed):
AF-hb2f's delivered `tasks.yaml` writes `${{ imageFrom(vars.image).Digest }}` (a `sha256:<hex>` string) into `release.yaml`'s `imageTag` key -- confirmed by AF-hb2f's own verified PROOF, because its `warehouse.yaml` uses `imageSelectionStrategy: Digest`, under which `.Tag` is invariantly the constant string `release` and only `.Digest` carries promotion signal. `imageTag` therefore holds a digest for the entire lifetime of this design, never a tag. This story's original draft bound that value into bjw-s app-template's `tag:` field (`tag: "{{.values.imageTag}}"`), which renders `repository:sha256:...` -- not a valid OCI reference, since a tag cannot contain a colon. Fixed here: bind it to app-template's `digest:` field instead (`digest: "{{.imageTag}}"`), which app-template's `_imageSpecificationToImage.tpl` renders as `repository@sha256:...` -- the correct, parseable form. The `imageTag` KEY NAME is unchanged (fixed by AF-hb2f's already-merged, out-of-scope-to-reopen `yaml-update` step); only the binding on this story's side changes, from `tag:` to `digest:`. AF-8r8l (this story's blocker) is amended in lockstep to seed `release.yaml`'s `imageTag` with a real, resolvable digest per app rather than the literal string `release`, so this story's very first render (before any Kargo promotion has run) also resolves to a genuinely pullable image reference.

PARAM PATH CORRECTION (second bug-triage pass, applied here before this story is claimed -- discovered by AF-6jta's own deliver-only follow-up developer, filed as a DISCOVERED_BUG, now closed out): the digest value binds to `{{.imageTag}}`, NOT `{{.values.imageTag}}`. Argo CD's git *files* generator exposes a discovered file's top-level keys directly, with no prefix (Argo CD's own Git generator docs: a file with top-level `aws_account`/`cluster` keys is referenced as `{{.aws_account}}`/`{{.cluster.name}}`). `release.yaml`'s `imageTag` key is top-level (AF-hb2f's `tasks.yaml` `yaml-update` step writes `key: imageTag`, top level); its sibling `values: {}` key is an empty map reserved for future per-stage Helm overrides -- reaching through it (`.values.imageTag`) indexes an absent key on an empty map, and under this ApplicationSet's own `goTemplateOptions: ["missingkey=error"]` that aborts template execution for all 18 Applications (without that option, it would render the unpullable `digest: "<no value>"`). Machine-checked across all 18 files AF-8r8l seeds: 18/18 have a valid top-level `imageTag` digest, 0/18 have anything under `values`. `apps/akkoma/argocd/appset.yaml` demonstrates both halves of the same rule side by side: its top-level `chartVersion` is `{{.chartVersion}}`, while `{{.values.image.tag}}` works there only because akkoma's `release.yaml` genuinely nests that value under a populated top-level `values:` key -- `arr-stack`'s `release.yaml` does not. The IMPLEMENTATION section below, AC #3, and AC #11 all use the corrected `{{.imageTag}}` path.

Context:
`apps/arr-stack/env/<app>/<stage>/release.yaml` (AF-8r8l, blocking this story) must already exist for the inner `git files` generator to discover anything -- an ApplicationSet git-files generator only picks up paths present at the revision it reads. `apps/arr-stack/argocd/appset-kargo.yaml` (AF-hb2f, patched by AF-yse2) already exists and independently maintains its own copy of the same 6-app parameter subset (name + image only, no port/hasDownloads) -- this story's `appset-workloads.yaml` maintains a second, richer copy (name + image + port + hasDownloads) of overlapping app metadata. Drift between the two lists (an app added to one and not the other, a typo'd image repo, or -- the specific case this bug-triage pass exists to prevent -- one list still saying `overseerr` after the other was corrected) is exactly the class of bug the static verification story (AF-vm0q) exists to catch -- this story must not introduce that drift at authoring time by copying the per-app parameter table from the epic body (AF-j5rz, already corrected to `seerr`) exactly, not from memory or from a stale copy of `appset-kargo.yaml`'s list.

`helm.values` (a raw multi-line string), not `helm.valuesObject`, is required here: `valuesObject` is a structured/object field (backed by `RawExtension`), so Argo CD's Go-template substitution only lands on string leaves and cannot build the conditional `hasDownloads` persistence block -- `apps/akkoma/argocd/appset.yaml`'s own header comment documents this exact restriction for a different reason (stage-varying leaf values), and this design needs the SAME underlying mechanism (`values` as a plain string, re-parsed as YAML by Helm after Go-template substitution) to make `{{- if eq .hasDownloads "true"}}...{{- end}}` possible at all. This is a deliberate departure from `akkoma`'s pattern, not an inconsistency.

This ApplicationSet uses a static per-app `list` generator with an inline `destination.name` conditional (`demo2` for `prod`, `demo1` otherwise) -- NOT a `clusters: {}` generator. This repo's own prior-epic finding (`.vault/knowledge/decisions/Argo CD clusters generator selector convention on Akuity-hosted instances.md`) confirmed a bare `clusters: {}` generator on this exact shared instance returns FOUR clusters (`demo1`, `demo2`, the control plane `in-cluster`, and `kargo`), not the two intended -- this design's static list sidesteps that risk entirely by construction, but if a FUTURE iteration of this design ever switches to cluster-discovery-based targeting, it MUST copy the `NotIn: [in-cluster, kargo]` selector convention already established fleet-wide (`docs/infra-dependencies.md`), not a bare `clusters: {}`. This story does not make that switch; it's a standing caution for future work, not an action item here.

USER INTENT:
A developer reading `appset-workloads.yaml` needs to see, in one file, the complete DRY claim for the workload half of this design: one template, 18 generated instances, differing only in the four leaf values (`name`, `image`, `port`, `hasDownloads`) the per-app parameter table declares -- and needs to trust that a promotion writing a new digest to a `release.yaml` file is picked up automatically, without ever touching this file again, AND that the resulting image reference is always parseable (never a colon-separated tag string built from a digest), AND that every app named here is a real, currently-resolvable image (never a retired one like the original `overseerr`).

IMPLEMENTATION:
Create `apps/arr-stack/argocd/appset-workloads.yaml` verbatim per the design spec, WITH THE CORRECTED BINDING (`digest:`, not `tag:`), THE CORRECTED PARAM PATH (`{{.imageTag}}`, not `{{.values.imageTag}}`), THE CORRECTED SIXTH-APP ROSTER (matrix generator: outer `list` of 6 apps, inner `git files` generator over `apps/arr-stack/env/{{.name}}/*/release.yaml`), AND THE `{{- if}}`/`{{- end}}` LINES INDENTED TO THE `values: |` BLOCK-SCALAR CONTENT MARGIN (12 spaces -- at file column 0 they are less indented than the block scalar and terminate it, which is a YAML syntax error, not a style choice; indenting to 12 spaces lands them at column 0 *within* the string, which is what the `{{-` chomping needs and is byte-identical to the intended rendered payload):
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
                - name: seerr
                  image: ghcr.io/hotio/seerr
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
                      digest: "{{.imageTag}}"
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
**Before finalizing, reconfirm `seerr`'s listening port.** The `5055` value above is carried over from the retired `overseerr` image's hotio docs and has NOT been independently verified for `hotio/seerr`. Check https://hotio.dev/containers/seerr/ (or the image's `docker inspect`/`LABEL`/`EXPOSE` metadata if the docs page isn't live yet) before committing this value; if the real port differs, use the confirmed value and record the correction as delivery evidence rather than silently keeping `5055`.

Note the THREE deviations from the design spec's own literal snippet (`docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md` lines ~170-171, ~203-205, ~296-297 -- tracked as a documentation-only, non-blocking defect on the epic, see that epic's comments): (1) `image.digest: "{{.imageTag}}"` replaces the spec's `image.tag: "{{.values.imageTag}}"` (verified correction, see BUG RESOLUTION and PARAM PATH CORRECTION above -- both the field, `digest:` not `tag:`, AND the param path, `.imageTag` not `.values.imageTag`, are corrected); (2) the sixth list element is `seerr`/`ghcr.io/hotio/seerr` instead of the spec's `overseerr`/`ghcr.io/hotio/overseerr` (verified correction, see ROSTER CORRECTION above, port independently reconfirmed -- see delivery evidence); (3) the `{{- if}}`/`{{- end}}` lines are indented to the `values: |` block-scalar content margin (12 spaces) rather than the spec's literal column 0, which is invalid YAML as written (a less-indented line terminates a block scalar) -- the indented form renders a byte-identical string, so this is a faithful transcription fix, not a design change. None of the three is a transcription error.

No explicit `storageClassName` is set on the `config`/`downloads` PVCs (relies on the cluster's default StorageClass, per the design spec) -- AF-pfbv (human-gated) independently verifies this assumption holds on the real instance before any live deploy trusts it; this story does not add `storageClassName` itself (that would silently diverge from the committed spec without the epic's own explicit verification gate having run).

KEY FILES:
Create: `apps/arr-stack/argocd/appset-workloads.yaml`. Reference-only (not modified): `apps/arr-stack/argocd/appset-kargo.yaml` (AF-hb2f, as patched by AF-yse2 -- cross-check the per-app parameter table matches, including the `seerr` rename), `apps/akkoma/argocd/appset.yaml` (reference for the `valuesObject` vs `values` restriction, and for the top-level-vs-nested git-files param convention), `apps/arr-stack/env/*/*/release.yaml` (AF-8r8l, the files this ApplicationSet's `git files` generator discovers, including the `seerr` trio).

OUT OF SCOPE:
- `storageClassName` on the PVCs -- deliberately left unset per the committed spec; AF-pfbv verifies the underlying assumption, this story does not pre-empt that verification by adding it speculatively.
- Any change to `appset-kargo.yaml`'s own per-app list -- that rename is AF-yse2's scope (already a hard blocker on this story); if a drift is found between the two lists during authoring beyond the `seerr` rename itself, fix THIS file to match the epic's parameter table (the source of truth), do not further modify `appset-kargo.yaml` as a side effect of this story.
- Renaming the `imageTag` key, restructuring `release.yaml`'s shape, or touching AF-hb2f's `tasks.yaml` -- fixed by AF-hb2f's already-delivered `yaml-update` step; this story only changes which app-template field consumes that value and which param path reaches it (`digest: "{{.imageTag}}"` instead of `tag: "{{.values.imageTag}}"`), never the upstream key name or file shape.
- Switching to a `clusters: {}` generator -- explicitly out of scope; this story uses the static per-app `list` + inline `destination.name` conditional exactly as specified.
- Real NFS-backed shared media volumes, ingress/HTTPRoute wiring -- both explicitly out of scope for this PoC per the epic body.
- Correcting the design spec doc's own snippet -- tracked as a documentation-only follow-up outside the execution path, not this story's concern.

DIFF BUDGET:
1 new file, 0 modified. ~75-90 LOC (matches the design spec's literal YAML length).

CONSUMES:
- AF-8r8l: apps/arr-stack/env/<app>/<stage>/release.yaml (18 files, app roster: sonarr/radarr/lidarr/bazarr/prowlarr/seerr) -> promotion-target contract file
    schema: imageTag (string, top-level key, "sha256:<64 lowercase hex chars>" -- always a digest, seeded per-app with a real resolvable value, never the literal tag name), values (object, empty map -- do not reach through it)
    source: AF-8r8l's own PRODUCES block (as amended by this same bug-triage pass)
- AF-yse2: apps/arr-stack/argocd/appset-kargo.yaml -> corrected list-generator element `{name: seerr, image: ghcr.io/hotio/seerr}`
    source: AF-yse2's own AC -- confirms the app-name/image pair this story's list must match for the cross-check AC (#9 below)
- AF-iv8x: this issue's own Notes/Comments -> decision record
    spec: supported: true (confirmed -- this story proceeds as written)
    source: the spike's empirical finding (already resolved, dependency removed)

PRODUCES:
- `apps/arr-stack/argocd/appset-workloads.yaml` -> ApplicationSet `arr-stack-workloads`
    spec: generators: [matrix: [list (6 apps: name/image/port/hasDownloads, sixth app `seerr`/`ghcr.io/hotio/seerr`), git files (path: apps/arr-stack/env/{{.name}}/*/release.yaml)]]; template.spec.source: oci://ghcr.io/bjw-s-labs/helm/app-template@4.x, helm.values (raw string, NOT valuesObject); template.spec.source's rendered image block binds `digest: "{{.imageTag}}"` (NOT `tag:`, NOT `.values.imageTag`); template.spec.destination.name: demo2 if stage==prod else demo1; template.spec.destination.namespace: arr-stack-{{.path.basename}}
    source: docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md, WITH the digest-binding correction, the param-path correction, and the seerr-roster correction from this bug-triage pass (spec's own literal snippet is a tracked doc-only defect, see BUG RESOLUTION / PARAM PATH CORRECTION / ROSTER CORRECTION)

TESTING:
No unit-test suite exists for this repo's GitOps manifests -- verification is static/render-level only for this story (no live cluster touch; the first live confirmation of actual sync health happens in AF-o0rw/AF-c17x, human-gated):
- `ruby -ryaml -e "YAML.load_stream(File.read('apps/arr-stack/argocd/appset-workloads.yaml'))" && echo OK`.
- Manually render the `helm.values` block for both a `hasDownloads: true` app (e.g. sonarr) and a `hasDownloads: false` app (e.g. seerr) by hand-substituting the Go-template fields (using a real `sha256:<hex>` value for `{{.imageTag}}`, matching AF-8r8l's seed shape), then run each through `helm template <local copy or OCI pull of ghcr.io/bjw-s-labs/helm/app-template:4.x>` -- confirm the `downloads` persistence block is present for the `true` case and absent for the `false` case, and confirm the rendered container image reference is `<repository>@sha256:<hex>` (never `<repository>:sha256:<hex>`) in both branches.
- Cross-file contract check (also re-verified independently in AF-vm0q): the app-name/image set in this file's `list` generator exactly matches `appset-kargo.yaml`'s (AF-hb2f, as patched by AF-yse2) `list` generator's name/image pairs, and exactly matches the 6-app, 18-directory set AF-8r8l seeded -- specifically confirm `seerr`/`ghcr.io/hotio/seerr` appears in all three places and `overseerr` appears in none.
- Grep this file (case-insensitive on the field name) for a `tag:` binding of the digest under either param path -- `tag: "{{.imageTag}}"` and `tag: "{{.values.imageTag}}"` -- and confirm NO match for either (the bug this story exists to avoid reintroducing, and the specific wrong-path variant discovered afterward); confirm `digest: "{{.imageTag}}"` IS present exactly once and `digest: "{{.values.imageTag}}"` is absent.
- Grep this file (case-insensitive) for `overseerr` and confirm NO match.
- `devops-toolkit:yaml-kubernetes-validator` and `devops-toolkit:helm-chart-developer` consulted before finalizing.

Acceptance Criteria:
1. [Ubiquitous] `apps/arr-stack/argocd/appset-workloads.yaml` uses a `matrix` generator (outer `list` of 6 apps, inner `git files` generator over `apps/arr-stack/env/{{.name}}/*/release.yaml`).
2. [Ubiquitous] The rendered template uses `helm.values` (raw string), never `helm.valuesObject`, for the `app-template` source.
3. [Ubiquitous] The container image block binds `digest: "{{.imageTag}}"` -- it shall never bind that value to `tag:`, and shall never reach through `.values.imageTag` (that path resolves in 0 of the 18 seeded `release.yaml` files and aborts rendering under `missingkey=error`).
4. [Event] Rendering for a `hasDownloads: true` app includes the `downloads` persistence block with `advancedMounts.main.main[0].path: /data`; rendering for a `hasDownloads: false` app (`prowlarr` or `seerr`) omits it entirely.
5. [Event] Rendering the container image block with a real `sha256:<hex>` value substituted for `{{.imageTag}}` produces `<repository>@sha256:<hex>` -- a syntactically valid OCI image reference.
6. [Ubiquitous] The generator produces exactly 18 Applications (6 apps x 3 stages), each named `arr-{{.name}}-{{.path.basename}}` and annotated `kargo.akuity.io/authorized-stage: "{{.name}}:{{.path.basename}}"`.
7. [Ubiquitous] `destination.name` resolves to `demo2` for `prod` and `demo1` for `dev`/`staging`; `destination.namespace` resolves to `arr-stack-<stage>` (shared across all 6 apps, per the epic's namespace decision).
8. [Ubiquitous] No `storageClassName` is set on either PVC (deliberately deferred to AF-pfbv's verification, not silently added or silently omitted-without-acknowledgment).
9. [Unwanted] The app-name/image list in this file shall not diverge from `appset-kargo.yaml`'s (AF-hb2f, as patched by AF-yse2) app-name/image list.
10. [Unwanted] This ApplicationSet's generator shall not use `clusters: {}`.
11. [Unwanted] This file shall not contain the substring `tag: "{{.imageTag}}"` or `tag: "{{.values.imageTag}}"` anywhere -- the exact regression this story's bug-triage pass exists to prevent, under either the originally-drafted param path or the corrected one; either wrong-field variant, under either path, is the same class of regression.
12. [Unwanted] This file shall not contain the substring `overseerr` (case-insensitive) anywhere -- the sixth app is `seerr`.
13. The port value used for `seerr` is either the confirmed `5055` or a corrected value, with the reconfirmation check (and its result) recorded as delivery evidence -- not silently assumed.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory -- its GitOps app-patterns reference material for the matrix/git-files generator shape), devops-toolkit:helm-chart-developer (mandatory -- bjw-s app-template values shape, specifically the `image.digest` vs `image.tag` fields in `_imageSpecificationToImage.tpl`), devops-toolkit:yaml-kubernetes-validator (mandatory)

## Acceptance Criteria


## Design


## Notes


## nd_contract
status: delivered

### evidence
- Transitioned via pvg story deliver on 2026-08-19.

### proof
- [ ] Developer evidence block must remain authoritative above this contract.


## History
- 2026-08-18T18:56:06Z dep_added: blocked_by AF-8r8l
- 2026-08-18T18:56:07Z dep_added: blocked_by AF-iv8x
- 2026-08-18T18:57:54Z dep_added: blocks AF-vm0q
- 2026-08-18T19:06:18Z dep_added: blocks AF-o0rw
- 2026-08-19T14:44:32Z dep_removed: was_blocked_by AF-iv8x
- 2026-08-19T15:40:15Z dep_added: blocked_by AF-yse2
- 2026-08-19T15:59:15Z dep_removed: was_blocked_by AF-8r8l
- 2026-08-19T16:03:25Z dep_removed: was_blocked_by AF-yse2
- 2026-08-19T16:03:26Z status: open -> in_progress
- 2026-08-19T16:03:26Z auto-follows: linked to predecessor AF-iv8x
- 2026-08-19T16:03:26Z auto-follows: linked to predecessor AF-8r8l
- 2026-08-19T16:03:26Z auto-follows: linked to predecessor AF-yse2
- 2026-08-19T16:03:26Z claimed by dev-AF-6jta
- 2026-08-19T16:06:31Z status: in_progress -> open
- 2026-08-19T16:06:59Z status: open -> in_progress
- 2026-08-19T16:06:59Z auto-follows: linked to predecessor AF-hb2f
- 2026-08-19T16:06:59Z claimed by dev-AF-6jta
- 2026-08-19T19:49:26Z status: in_progress -> in_progress
- 2026-08-19T20:07:16Z status: in_progress -> closed
- 2026-08-19T20:07:16Z dep_removed: no_longer_blocks AF-vm0q
- 2026-08-19T20:07:16Z dep_removed: no_longer_blocks AF-o0rw

## Links
- Parent: [[AF-j5rz]]
- Was blocked by: [[AF-iv8x]], [[AF-8r8l]], [[AF-yse2]]
- Follows: [[AF-iv8x]], [[AF-8r8l]], [[AF-yse2]], [[AF-hb2f]]

## Comments

### 2026-08-19T15:02:53Z ada
BUG TRIAGE (Sr PM): discovered by AF-hb2f's deliver-only follow-up developer -- this story's original draft bound release.yaml's imageTag value into bjw-s app-template's tag: field (tag: "{{.values.imageTag}}"), but imageTag always holds a sha256 digest (per AF-hb2f's delivered tasks.yaml/warehouse.yaml, Digest selection strategy). A digest in a tag field renders repository:sha256:..., which is not a valid OCI reference (tags cannot contain a colon); app-template's own _imageSpecificationToImage.tpl exposes a separate digest: field that renders the correct repository@sha256:... form. Resolution applied directly to this story's body: bind digest: "{{.values.imageTag}}" instead of tag:. AF-8r8l (this story's blocker) amended in lockstep to seed release.yaml with a real per-app digest rather than the literal string release. AF-vm0q (capstone) amended to verify the corrected binding and add a regression check. AF-hb2f itself is NOT reopened -- the imageTag key name is unchanged.

### 2026-08-19T16:06:32Z ada
loop: reset orphaned in_progress to open (no developer worktree found; prior session presumed dead)

### 2026-08-19T19:49:19Z ada
DELIVERED: `apps/arr-stack/argocd/appset-workloads.yaml` (1 new file, 0 modified, 173 lines: 108 YAML + 65 header/inline comment lines, consistent with this repo's heavily-commented manifest convention — cf. `appset-kargo.yaml`, `apps/akkoma/argocd/appset.yaml`, `kargo-chart/templates/tasks.yaml`).

Commit SHA producing every result below: **3f0fd80** (`story/AF-6jta`, parent `04b0158` = `origin/epic/AF-j5rz` tip; pushed fast-forward, 0 ahead / 0 behind, working tree clean).

## ⚠️ ONE DELIBERATE DEVIATION FROM AC #3's LITERAL TEXT — NEEDS PM RATIFICATION

**Shipped `digest: "{{.imageTag}}"`, not `digest: "{{.values.imageTag}}"`.**

The `digest:`-not-`tag:` half of AC #3 (the entire point of this story's bug-triage pass) is implemented exactly as specified. The *parameter path* is corrected: `.imageTag`, not `.values.imageTag`. Evidence, three independent confirmations:

1. **Argo CD's own Git generator docs** — the git *files* generator exposes a discovered file's **top-level keys directly, with no prefix**. Their example file has top-level `aws_account` / `cluster`, referenced as `{{.aws_account}}` / `{{.cluster.name}}`.
2. **This repo's own merged, live-verified precedent** — `apps/akkoma/argocd/appset.yaml` reads its release.yaml's top-level `chartVersion` as `{{.chartVersion}}`. It uses `{{.values.image.tag}}` only because akkoma's `release.yaml` *genuinely nests* that under a populated top-level `values:` key.
3. **The producer side** — `kargo-chart/templates/tasks.yaml`'s `yaml-update` step writes `key: imageTag` — top level.

Machine-checked across all 18 seeded files (AF-8r8l):

```
files checked: 18
all have a valid top-level `imageTag` digest?  true   []
any file has `values.imageTag`?                false  []
==> `.imageTag`        resolves in 18/18 files
==> `.values.imageTag` resolves in 0/18 files (values is an empty map everywhere)
```

Every seeded `release.yaml` is `imageTag: "sha256:<64 hex>"` + `values: {}`. Under this ApplicationSet's own `goTemplateOptions: ["missingkey=error"]`, `.values.imageTag` indexes an absent key on an empty map → **template execution aborts and all 18 Applications fail to generate**. Without `missingkey=error` it would render `digest: "<no value>"` — an unpullable reference. Either way the story's literal path yields zero working Applications, defeating the story's own stated USER INTENT ("a promotion writing a new digest to a `release.yaml` file is picked up automatically").

Correcting it inside *this* file was the only in-scope fix: changing `release.yaml`'s shape (AF-8r8l) or `tasks.yaml`'s write key (AF-hb2f) is explicitly OUT OF SCOPE per this story's own OUT OF SCOPE section.

Note the substring ACs are unaffected: AC #11's forbidden `tag: "{{.values.imageTag}}"` is absent, and no `tag:` binding of the digest exists under either path. **AC #3's and AC #11's literal quoted strings, and AF-vm0q's regression check (which this story's body says was amended to assert `{{.values.imageTag}}`), should be amended to `{{.imageTag}}`.** Filed as a DISCOVERED_BUG for Sr PM triage.

## PROOF

### Commands run (all static, no live cluster touch)

```
ruby -ryaml -e "YAML.load_stream(File.read('apps/arr-stack/argocd/appset-workloads.yaml'))" && echo OK
  -> OK

helm pull oci://ghcr.io/bjw-s-labs/helm/app-template --version 4.x --untar
  -> Pulled: ghcr.io/bjw-s-labs/helm/app-template:4.6.2 (targetRevision 4.x resolves here)

helm template arr-sonarr-dev <chart> -f values-sonarr.yaml --namespace arr-stack-dev   -> exit 0
helm template arr-seerr-dev  <chart> -f values-seerr.yaml  --namespace arr-stack-dev   -> exit 0
helm template arr-sonarr-dev <chart> -f values-COUNTERFACTUAL-tag.yaml                 -> exit 0

ruby e2e/observability_test.rb   -> RESULT: PASS -- 150 assertions, 0 failures
pvg verify apps/arr-stack/argocd/appset-workloads.yaml --format text
  -> VERIFY: PASSED (0 files scanned, 0 issues); exit=0
```

**Pass/fail counts: 150/150 repo e2e assertions passed, 0 failed, 0 skipped. 3/3 helm renders exited 0. 13/13 ACs verified. 0 errors, 0 warnings across every command above.**

`pvg verify` reports "0 files scanned" because its substance scanner skips `.yaml`; it is not a silent pass on a scanned file. Coverage percentage: **not applicable** — this repo has no unit-test suite and no instrumented code (GitOps manifests only); verification is static/render-level, exactly as the story's TESTING section prescribes. Live sync health is deferred to AF-o0rw/AF-c17x (human-gated).

Blast radius: 1 new file, referenced by nothing yet (the bootstrap app-of-apps discovers `apps/*/argocd` wholesale, so it is picked up by directory convention, not by an edit elsewhere). Ran the full repo suite (the sole `e2e/observability_test.rb`, 150 assertions) — nothing skipped.

### Render proof — `hasDownloads: true` (sonarr) vs `false` (seerr)

Values payloads hand-rendered from the shipped `helm.values` string with faithful Go-template `{{-` chomping semantics, substituting the **real seeded digests** from `apps/arr-stack/env/<app>/dev/release.yaml`.

| | sonarr (`hasDownloads: "true"`) | seerr (`hasDownloads: "false"`) |
|---|---|---|
| helm template exit | 0 | 0 |
| kinds rendered | Deployment, **2x** PersistentVolumeClaim, Service | Deployment, **1x** PersistentVolumeClaim, Service |
| `persistence` keys | `["config", "downloads"]` | `["config"]` |
| PVCs | `arr-sonarr-dev-config`, `arr-sonarr-dev-downloads` | `arr-seerr-dev-config` only |
| `/data` mount | present (`mountPath: /data`) | **absent** |
| `storageClassName` occurrences | **0** | **0** |
| service targetPort | 8989 | 5055 |
| rendered image ref | `ghcr.io/hotio/sonarr@sha256:e029ce19…d551a` | `ghcr.io/hotio/seerr@sha256:6ce42c9c…20f7` |

Both image references use `@`, never `:`. AC #4, #5, #8 satisfied in both branches.

### Counterfactual proof — why `digest:` is required (bonus, not an AC)

Same digest, same chart, only the bound field changed:

```
tag:    -> image: ghcr.io/hotio/sonarr:sha256:e029ce19…d551a
           docker buildx imagetools inspect  =>  ERROR: invalid reference format

digest: -> image: ghcr.io/hotio/sonarr@sha256:e029ce19…d551a
           docker buildx imagetools inspect  =>  application/vnd.oci.image.index.v1+json
                                                 digest=sha256:e029ce19…d551a  (resolves)
```

Root cause confirmed in the chart source, `charts/common/templates/lib/common/_imageSpecificationToImage.tpl`: `tag` → `printf "%s:%s"`, `digest` → `printf "%s@%s"`. `values.schema.json` accepts `repository`/`tag`/`digest` with none required, so `digest`-without-`tag` is schema-valid. Side benefit: this also proves AF-8r8l's seeded digests are real, resolvable images.

### AC #13 — seerr port reconfirmed (NOT inherited): **5055 confirmed, no correction needed**

Two independent sources for `ghcr.io/hotio/seerr` itself, not the retired predecessor:

1. **hotio's live docs** (https://hotio.dev/containers/seerr/) — docker run example shows `-p 5055:5055`; env shows `WEBUI_PORTS=5055/tcp`.
2. **The image's own OCI config** (`docker buildx imagetools inspect ghcr.io/hotio/seerr:release`) — `"ExposedPorts": {"5055/tcp": {}}` and `WEBUI_PORTS=5055/tcp`. Image is Seerr v3.4.1, built 2026-08-18.

The carried-over `5055` is correct. Kept it, and recorded the confirmation in an inline comment on the list element so the next reader knows it was verified for this image rather than inherited.

### AC #9 — cross-file contract, three-way check

`appset-workloads.yaml` name/image pairs vs `appset-kargo.yaml` (AF-hb2f + AF-yse2) vs `env/` directories (AF-8r8l):

```
name/image pair set equality (workloads vs kargo):
  identical (order-insensitive)? true
  identical (order-SENSITIVE)?   true
  only in workloads: []     only in kargo: []

app-name set vs env/ dirs: ["bazarr","lidarr","prowlarr","radarr","seerr","sonarr"] == identical? true

release.yaml per app: bazarr 3/3, lidarr 3/3, prowlarr 3/3, radarr 3/3, seerr 3/3, sonarr 3/3
  TOTAL = 18  (=> 18 generated Applications)

seerr in workloads list? true | in kargo list? true | env/ dir exists? true
retired predecessor name in either appset? false | in any env path? false
```

Zero drift introduced. All six ports/hasDownloads values taken from the epic's corrected parameter table (AF-j5rz), not from memory.

### AC verification table

| AC | Verdict | Evidence |
|----|---------|----------|
| 1 — matrix generator (outer list of 6, inner git-files over `env/{{.name}}/*/release.yaml`) | PASS | Parsed: 1 top-level generator (`matrix`); inner = `list, git`; 6 list elements; git path `apps/arr-stack/env/{{.name}}/*/release.yaml` @ `HEAD` |
| 2 — `helm.values` raw string, never `valuesObject` | PASS | `helm` keys = `["values"]`; `values` is a String = true; `valuesObject` present = **false** (the token appears only in the rationale comment, never as a field) |
| 3 — binds `digest:`, never `tag:` | PASS *(with corrected param path — see deviation above)* | `digest: "{{.imageTag}}"` present exactly once (line 132); no `tag:` binding of the digest under any path |
| 4 — true renders `downloads` + `advancedMounts.main.main[0].path: /data`; false omits entirely | PASS | sonarr: 2 PVCs, `/data` mounted; seerr: 1 PVC, no `/data`. Both `helm template` exit 0 |
| 5 — real digest → valid `<repo>@sha256:<hex>` | PASS | `ghcr.io/hotio/sonarr@sha256:e029…`, `ghcr.io/hotio/seerr@sha256:6ce4…`; both resolve via `imagetools inspect`; counterfactual `tag:` form rejected as `invalid reference format` |
| 6 — exactly 18 Apps, named `arr-{{.name}}-{{.path.basename}}`, annotated `kargo.akuity.io/authorized-stage` | PASS | 6 apps x 3 stages, 18/18 `release.yaml` present. Name template `arr-{{.name}}-{{.path.basename}}`; annotation `{{.name}}:{{.path.basename}}`. Matches the `<kargo-project>:<stage>` contract: `kargo-chart` names the Project `{{ .Values.appName }}` with Stages `dev`/`staging`/`prod` |
| 7 — `destination.name` demo2 for prod / demo1 for dev+staging; ns `arr-stack-<stage>` | PASS | Hand-resolved: `dev→demo1 / arr-stack-dev`, `staging→demo1 / arr-stack-staging`, `prod→demo2 / arr-stack-prod` |
| 8 — no `storageClassName` on either PVC | PASS | `grep -c storageClassName` = **0** in both rendered outputs. Not silently omitted: acknowledged in the header comment, with the AF-pfbv deferral named |
| 9 — no divergence from `appset-kargo.yaml`'s list | PASS | Three-way set equality, order-sensitive AND order-insensitive; empty symmetric difference |
| 10 — no `clusters: {}` generator | PASS | Parsed generators = `matrix{list, git}`. Literal `clusters:` substring also absent from the file (comment reworded so a grep-based verifier can't false-positive) |
| 11 — no `tag: "{{.values.imageTag}}"` substring | PASS | `grep` → no match. Extended check `^\s*tag: *"\{\{\.(values\.)?imageTag\}\}"` → no match |
| 12 — no `overseerr` substring, case-insensitive | PASS | `grep -i` → no match (the `seerr` comment describes the predecessor without naming it, matching `appset-kargo.yaml`'s approach) |
| 13 — seerr port confirmed, result recorded | PASS | 5055 confirmed by hotio docs *and* the image's own `ExposedPorts`/`WEBUI_PORTS`; recorded above and in an inline comment |

### YAML hygiene / skills

`tabs: 0`, `trailing whitespace: 0`, `CRLF: 0`, ends with newline: YES, parse→emit→parse round-trip stable: true, single document, `apiVersion: argoproj.io/v1alpha1`, `kind: ApplicationSet`, `metadata: {name: arr-stack-workloads, namespace: argocd}`, 2-space indent throughout.

Mandatory skills reviewed before finalizing: `devops-toolkit:akp-platform` (incl. `references/gitops-app-patterns.md` — confirmed the `<project>:<stage>` authorized-stage contract and the app-of-apps discovery convention), `devops-toolkit:helm-chart-developer` (drove reading `_imageSpecificationToImage.tpl` and `values.schema.json` directly rather than trusting the field names), `devops-toolkit:yaml-kubernetes-validator` (drove the hygiene/round-trip pass). Also read `AGENTS.md` per repo convention.

### Second spec defect found and fixed (formatting, zero semantic change)

The story's IMPLEMENTATION snippet places `{{- if eq .hasDownloads "true"}}` and `{{- end}}` at **file column 0**, inside a `values: |` block scalar whose content indent is 12. Transcribed literally that is **invalid YAML** — a line less-indented than the block scalar terminates it. Proven both ways:

```
variantA (story literal, col 0):  YAML PARSE: FAILED -- Psych::SyntaxError:
                                  could not find expected ':' while scanning a simple key at line 15 column 1
variantB (indented to col 12):    YAML PARSE: OK
```

and the extracted string from variantB is exactly the intended payload, with the actions at **column 0 of the string** (which is what `{{-` chomping needs):

```
|    size: 1Gi
|{{- if eq .hasDownloads "true"}}
|  downloads:
```

So indenting to the block-scalar margin is the faithful rendition, not a design change: the rendered string is byte-identical to the snippet's intent. Documented in the file's header so nobody "tidies" it back to column 0. This is a doc-only defect in the spec snippet, same class as the two the story already tracks.

## DISCOVERED_BUG

```
DISCOVERED_BUG:
  title: appset-workloads git-files param path is .imageTag, not .values.imageTag -- AC #3/#11 literal text and AF-vm0q's regression check need amending
  context: AF-6jta's body (and AF-vm0q's amended regression check) specify binding the promotion
    digest as `digest: "{{.values.imageTag}}"`. That path cannot resolve. Argo CD's git *files*
    generator exposes a discovered file's top-level keys directly with no prefix (official Git
    generator docs: top-level `aws_account` -> `{{.aws_account}}`), and AF-hb2f's tasks.yaml
    yaml-update step writes `key: imageTag` at the top level. Machine-checked across all 18 files
    seeded by AF-8r8l: 18/18 have a valid top-level `imageTag` sha256 digest and 0/18 have
    `values.imageTag` (`values` is `{}` everywhere). Under this ApplicationSet's own
    `goTemplateOptions: ["missingkey=error"]`, `.values.imageTag` aborts template execution and
    ZERO of the 18 Applications generate; without that option it renders `digest: "<no value>"`.
    This repo's merged, live-verified `apps/akkoma/argocd/appset.yaml` demonstrates both halves of
    the rule: top-level `chartVersion` is `{{.chartVersion}}`, while `{{.values.image.tag}}` works
    there only because akkoma's release.yaml genuinely nests it under a populated `values:` key.
    AF-6jta shipped the corrected `.imageTag` because the alternatives (reshaping release.yaml or
    tasks.yaml's write key) are explicitly out of scope for it. The digest-vs-tag correction that
    AF-6jta's bug-triage pass exists to enforce is unaffected and fully implemented.
    Needed: amend AC #3's and AC #11's literal quoted strings to `{{.imageTag}}`, and amend
    AF-vm0q's regression check to assert `digest: "{{.imageTag}}"` (and to forbid a `tag:` binding
    under BOTH the `.imageTag` and `.values.imageTag` paths).
    Second, separate, doc-only item: AF-6jta's IMPLEMENTATION snippet (and the design spec at
    docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md) places the `{{- if}}`/`{{- end}}`
    lines at file column 0 inside a `values: |` block scalar with content indent 12 -- invalid YAML
    as literally written (Psych::SyntaxError, verified). Indenting them to the block margin yields a
    byte-identical rendered string; AF-6jta ships the indented form and documents why.
  affected_files: .vault issue bodies AF-6jta (AC #3, #11) and AF-vm0q (regression check);
    docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md (snippet, doc-only).
    NOT a code defect in any merged file -- apps/arr-stack/argocd/appset-workloads.yaml ships correct.
  discovered_during: AF-6jta
```

## LEARNINGS

- **A cross-story "schema" contract stated in prose is not a param path.** This story's CONSUMES block correctly described release.yaml as `imageTag (string)` + `values (object)` and *still* specified `{{.values.imageTag}}` — the prose and the binding contradicted each other in the same paragraph. When a story hands you a template expression that reaches into a consumed file, resolve it against the real file plus the generator's documented param shape before writing it down. Cheapest possible check (`ruby -ryaml` over all 18 files), caught a defect that would have generated zero Applications while every substring-based AC passed green.
- **The in-repo precedent was worth more than the docs.** `apps/akkoma/argocd/appset.yaml` settled the git-files param question faster and more convincingly than the upstream docs did, because it shows *both* cases side by side (`{{.chartVersion}}` top-level vs `{{.values.image.tag}}` nested) and is already live-verified. On a repo with an established sibling pattern, read the sibling first.
- **Counterfactual rendering is disproportionately strong evidence.** Rendering the *buggy* binding alongside the correct one and letting `docker buildx imagetools inspect` return `ERROR: invalid reference format` converts "the spec says bind digest" into a demonstrated fact in about two minutes. Worth doing routinely for any story whose whole purpose is preventing one specific regression.
- **Watch for forbidden tokens leaking into your own explanatory comments.** My first draft's rationale comments contained `clusters:` and `storageClassName` — both are semantic ACs here (#10, #8) so structural checks pass, but AF-vm0q is a *static/grep* verification story and would plausibly false-positive. Reworded where it cost no clarity; deliberately kept `valuesObject` (the token is load-bearing documentation) and flagged it explicitly so AF-vm0q strips comments before substring checks. Future authors of heavily-commented manifests in this repo should assume grep-based verification and keep forbidden literals out of prose.
- **Block scalars silently swallow Go-template control flow.** Templating inside `values: |` only works if the `{{- if}}`/`{{- end}}` lines are indented to the block's content margin; at column 0 they are a YAML *syntax error*, not a style nit. Both this story's snippet and the committed design spec get it wrong, which suggests it will be transcribed wrong again — hence the header comment in the file pinning the reason.
- Process note: the pvg guard blocks `cd` into the dispatcher-managed worktree, and `git push --force-with-lease` was (correctly) denied as an unrequested history rewrite. `git -C <worktree>` + absolute paths covered everything, and a plain fast-forward `git push` was the right call once I checked 1-ahead/0-behind — the lease flag was never needed.

### 2026-08-19T19:56:42Z ada
PM RATIFICATION (Sr PM bug triage, DISCOVERED_BUG from AF-6jta's own deliver-only follow-up developer): the deviation from AC #3's literal text flagged above is RATIFIED -- .imageTag (top-level) is correct, .values.imageTag is not (values is an empty map in all 18 seeded release.yaml files; under goTemplateOptions missingkey=error that path aborts rendering for all 18 Applications). AC #3 and AC #11's literal text have been amended in this story's own body to .imageTag, and AC #11 now forbids the tag: binding under BOTH the .imageTag and .values.imageTag paths. AF-vm0q's regression check has been amended in lockstep (see its own comments). No code change needed -- apps/arr-stack/argocd/appset-workloads.yaml already ships the correct .imageTag binding; only this story's own AC literal text was out of sync with its actual delivery. The IMPLEMENTATION snippet and its deviation note have also been updated to reflect the corrected param path and to record the {{- if}}/{{- end}} block-scalar-margin indentation as a third (formatting-only) deviation from the design spec's literal snippet. Design spec doc (docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md) is being corrected in a real pass rather than flagged a fourth time -- see AF-j5rz's comments for the consolidated rationale.
