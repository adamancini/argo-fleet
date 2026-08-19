---
id: AF-6jta
title: "Implement arr-stack workloads ApplicationSet matrix generator"
status: open
priority: 1
type: task
parent: AF-j5rz
created_at: 2026-08-18T18:56:00Z
created_by: ada
updated_at: 2026-08-18T19:13:11Z
content_hash: "sha256:7d2373f98a1510894a8b516138c01ff67a13e6d42cc92856f3009c8f0ba0c4cb"
blocked_by: [AF-8r8l]
blocks: [AF-vm0q, AF-o0rw]
was_blocked_by: [AF-iv8x]
---

## Description
Description:
Implement `apps/arr-stack/argocd/appset-workloads.yaml` -- the matrix-generator ApplicationSet that fans out 6 apps x 3 stages = 18 workload Applications, each rendering the bjw-s `app-template` OCI chart via `helm.values` (a raw multi-line string) with the `hasDownloads` conditional persistence block working in both branches.

**This story is written for the confirmed-supported outcome of the spike (AF-iv8x).** If AF-iv8x's resolution concludes the matrix generator's inner `git files` generator does NOT support interpolating `{{.name}}` from the outer `list` generator's sibling element, do NOT implement this story as written -- stop, report back to the dispatcher/Sr PM, and wait for a replacement story covering the fallback design (a static `dev`/`staging`/`prod` list generator as the matrix's second generator, per AF-iv8x's own resolution notes) before any developer claims this issue. This story's AC and IMPLEMENTATION below assume AF-iv8x confirmed support.

Context:
`apps/arr-stack/env/<app>/<stage>/release.yaml` (AF-8r8l, blocking this story) must already exist for the inner `git files` generator to discover anything -- an ApplicationSet git-files generator only picks up paths present at the revision it reads. `apps/arr-stack/argocd/appset-kargo.yaml` (AF-hb2f) already exists and independently maintains its own copy of the same 6-app parameter subset (name + image only, no port/hasDownghosts) -- this story's `appset-workloads.yaml` maintains a second, richer copy (name + image + port + hasDownloads) of overlapping app metadata. Drift between the two lists (an app added to one and not the other, a typo'd image repo) is exactly the class of bug the static verification story (Story 6) exists to catch -- this story must not introduce that drift at authoring time by copying the per-app parameter table from the epic body exactly, not from memory or from `appset-kargo.yaml`'s narrower list.

`helm.values` (a raw multi-line string), not `helm.valuesObject`, is required here: `valuesObject` is a structured/object field (backed by `RawExtension`), so Argo CD's Go-template substitution only lands on string leaves and cannot build the conditional `hasDownloads` persistence block -- `apps/akkoma/argocd/appset.yaml`'s own header comment documents this exact restriction for a different reason (stage-varying leaf values), and this design needs the SAME underlying mechanism (`values` as a plain string, re-parsed as YAML by Helm after Go-template substitution) to make `{{- if eq .hasDownloads "true"}}...{{- end}}` possible at all. This is a deliberate departure from `akkoma`'s pattern, not an inconsistency.

This ApplicationSet uses a static per-app `list` generator with an inline `destination.name` conditional (`demo2` for `prod`, `demo1` otherwise) -- NOT a `clusters: {}` generator. This repo's own prior-epic finding (`.vault/knowledge/decisions/Argo CD clusters generator selector convention on Akuity-hosted instances.md`) confirmed a bare `clusters: {}` generator on this exact shared instance returns FOUR clusters (`demo1`, `demo2`, the control plane `in-cluster`, and `kargo`), not the two intended -- this design's static list sidesteps that risk entirely by construction, but if a FUTURE iteration of this design ever switches to cluster-discovery-based targeting, it MUST copy the `NotIn: [in-cluster, kargo]` selector convention already established fleet-wide (`docs/infra-dependencies.md`), not a bare `clusters: {}`. This story does not make that switch; it's a standing caution for future work, not an action item here.

USER INTENT:
A developer reading `appset-workloads.yaml` needs to see, in one file, the complete DRY claim for the workload half of this design: one template, 18 generated instances, differing only in the four leaf values (`name`, `image`, `port`, `hasDownloads`) the per-app parameter table declares -- and needs to trust that a promotion writing a new `imageTag` to a `release.yaml` file is picked up automatically, without ever touching this file again.

IMPLEMENTATION:
Create `apps/arr-stack/argocd/appset-workloads.yaml` verbatim per the design spec (matrix generator: outer `list` of 6 apps, inner `git files` generator over `apps/arr-stack/env/{{.name}}/*/release.yaml`):
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
                      tag: "{{.values.imageTag}}"
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
No explicit `storageClassName` is set on the `config`/`downloads` PVCs (relies on the cluster's default StorageClass, per the design spec) -- Story 5 (human-gated, `AF-<storageclass>`) independently verifies this assumption holds on the real instance before any live deploy trusts it; this story does not add `storageClassName` itself (that would silently diverge from the committed spec without the epic's own explicit verification gate having run).

KEY FILES:
Create: `apps/arr-stack/argocd/appset-workloads.yaml`. Reference-only (not modified): `apps/arr-stack/argocd/appset-kargo.yaml` (AF-hb2f, cross-check the per-app parameter table matches), `apps/akkoma/argocd/appset.yaml` (reference for the `valuesObject` vs `values` restriction), `apps/arr-stack/env/*/*/release.yaml` (AF-8r8l, the files this ApplicationSet's `git files` generator discovers).

OUT OF SCOPE:
- `storageClassName` on the PVCs -- deliberately left unset per the committed spec; Story 5 verifies the underlying assumption, this story does not pre-empt that verification by adding it speculatively.
- Any change to `appset-kargo.yaml`'s own per-app list -- if a drift is found between the two lists during authoring, fix THIS file to match the epic's parameter table (the source of truth), do not "fix" `appset-kargo.yaml` as a side effect of this story (that would be an undeclared change to AF-hb2f's already-delivered scope).
- Switching to a `clusters: {}` generator -- explicitly out of scope; this story uses the static per-app `list` + inline `destination.name` conditional exactly as specified.
- Real NFS-backed shared media volumes, ingress/HTTPRoute wiring -- both explicitly out of scope for this PoC per the epic body.

DIFF BUDGET:
1 new file, 0 modified. ~75-90 LOC (matches the design spec's literal YAML length).

CONSUMES:
- AF-8r8l: apps/arr-stack/env/<app>/<stage>/release.yaml (18 files) -> promotion-target contract file
    schema: imageTag (string), values (object)
    source: AF-8r8l's own PRODUCES block
- AF-iv8x: this issue's own Notes/Comments -> decision record
    spec: supported: true (required for this story to proceed as written) | false (this story must not be implemented as written -- see Description)
    source: the spike's empirical finding

PRODUCES:
- `apps/arr-stack/argocd/appset-workloads.yaml` -> ApplicationSet `arr-stack-workloads`
    spec: generators: [matrix: [list (6 apps: name/image/port/hasDownloads), git files (path: apps/arr-stack/env/{{.name}}/*/release.yaml)]]; template.spec.source: oci://ghcr.io/bjw-s-labs/helm/app-template@4.x, helm.values (raw string, NOT valuesObject); template.spec.destination.name: demo2 if stage==prod else demo1; template.spec.destination.namespace: arr-stack-{{.path.basename}}
    source: docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md, verbatim

TESTING:
No unit-test suite exists for this repo's GitOps manifests -- verification is static/render-level only for this story (no live cluster touch; the first live confirmation of actual sync health happens in Story 7/8, human-gated):
- `ruby -ryaml -e "YAML.load_stream(File.read('apps/arr-stack/argocd/appset-workloads.yaml'))" && echo OK`.
- Manually render the `helm.values` block for both a `hasDownloads: true` app (e.g. sonarr) and a `hasDownloads: false` app (e.g. prowlarr) by hand-substituting the Go-template fields, then run each through `helm template <local copy or OCI pull of ghcr.io/bjw-s-labs/helm/app-template:4.x>` -- confirm the `downloads` persistence block is present for the `true` case and absent for the `false` case, and that the chart accepts the rendered values without error in both branches.
- Cross-file contract check (also re-verified independently in Story 6): the app-name/image set in this file's `list` generator exactly matches `appset-kargo.yaml`'s (AF-hb2f) `list` generator's name/image pairs, and exactly matches the 6-app, 18-directory set `AF-8r8l` seeded.
- `devops-toolkit:yaml-kubernetes-validator` and `devops-toolkit:helm-chart-developer` consulted before finalizing.

Acceptance Criteria:
1. [Ubiquitous] `apps/arr-stack/argocd/appset-workloads.yaml` uses a `matrix` generator (outer `list` of 6 apps, inner `git files` generator over `apps/arr-stack/env/{{.name}}/*/release.yaml`), NOT two static list generators -- unless AF-iv8x's resolution required the fallback, in which case this story must not proceed as written (see Description).
2. [Ubiquitous] The rendered template uses `helm.values` (raw string), never `helm.valuesObject`, for the `app-template` source.
3. [Event] Rendering for a `hasDownloads: true` app includes the `downloads` persistence block with `advancedMounts.main.main[0].path: /data`; rendering for a `hasDownloads: false` app omits it entirely.
4. [Ubiquitous] The generator produces exactly 18 Applications (6 apps x 3 stages), each named `arr-{{.name}}-{{.path.basename}}` and annotated `kargo.akuity.io/authorized-stage: "{{.name}}:{{.path.basename}}"`.
5. [Ubiquitous] `destination.name` resolves to `demo2` for `prod` and `demo1` for `dev`/`staging`; `destination.namespace` resolves to `arr-stack-<stage>` (shared across all 6 apps, per the epic's namespace decision).
6. [Ubiquitous] No `storageClassName` is set on either PVC (deliberately deferred to Story 5's verification, not silently added or silently omitted-without-acknowledgment).
7. [Unwanted] The app-name/image list in this file shall not diverge from `appset-kargo.yaml`'s (AF-hb2f) app-name/image list.
8. [Unwanted] This ApplicationSet's generator shall not use `clusters: {}`.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory -- its GitOps app-patterns reference material for the matrix/git-files generator shape), devops-toolkit:helm-chart-developer (mandatory -- bjw-s app-template values shape), devops-toolkit:yaml-kubernetes-validator (mandatory)

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
