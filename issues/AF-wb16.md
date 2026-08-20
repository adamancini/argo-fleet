---
id: AF-wb16
title: "Bug: arr-stack workload Applications fail Argo CD spec validation -- OCI repoURL cannot embed chart name, chart: field is mandatory"
status: open
priority: 0
type: bug
parent: AF-j5rz
created_at: 2026-08-20T14:43:53Z
created_by: ada
updated_at: 2026-08-20T14:43:53Z
content_hash: "sha256:75774686ea077f9537ecea3e6e3909f402b4b87d48cd0ccb5d70001e0a589bfe"
blocks: [AF-vm0q]
---

## Description
Description:
`apps/arr-stack/argocd/appset-workloads.yaml` (merged to `main` via AF-6jta, commit `63efac6`) sets its 18 workload Applications' `template.spec.source` to `repoURL: oci://ghcr.io/bjw-s-labs/helm/app-template` with no `chart:` field. Confirmed live against the real shared `demo1`/`demo2`/`kargo` instance during AF-o0rw's dispatcher-run verification: Argo CD rejects every one of the 18 generated Applications with `InvalidSpecError -- spec.source.repoURL and either spec.source.path or spec.source.chart are required`. Fix: drop the `oci://` scheme from `repoURL` and add an explicit `chart: app-template` field -- the same shape this repo's own live-working `apps/akkoma/argocd/appset.yaml` already uses for its OCI source.

DISCOVERED DURING:
AF-o0rw (dispatcher-run, human-gated live verification of the epic's merge to `main`). Step 3 (wrapper Application health) and Step 4 (ApplicationSet child counts) both passed cleanly -- `argocd-arr-stack` wrapper Synced/Healthy, `arr-stack-workloads` generated exactly 18 children, `arr-stack-kargo` generated exactly 6, all named through `seerr` (confirming this epic's prior overseerr-rename and digest-binding fixes are correct on the real instance). Step 5 ("confirm nothing broken") is where this surfaced: all 18 `arr-<app>-<stage>` workload Applications show `Sync Status: Unknown` / `Health Status: Unknown` with an `InvalidSpecError` condition. The 6 `kargo-arr-*` Applications are unaffected and remain Synced/Healthy.

This is a clean validation-time rejection, not a broken deployment: Argo CD refuses to even attempt a sync when the spec is invalid, so nothing was actually created for any of the 18 Applications -- no pods, no PVCs, no partial state. Safe and fully reversible by this fix; not a live incident requiring rollback.

SYMPTOMS:
- `argocd app get arr-sonarr-dev` (and all 17 sibling workload Applications) shows `Sync Status: Unknown`, `Health Status: Unknown`.
- Condition: `InvalidSpecError -- spec.source.repoURL and either spec.source.path or spec.source.chart are required`.
- The 6 `kargo-arr-*` Kargo pipeline Applications are unaffected (Synced/Healthy) -- this is isolated to the workload half of the design (`appset-workloads.yaml`), not the Kargo half (`appset-kargo.yaml`).

EVIDENCE:
- Live rendered `spec.source` for e.g. `arr-sonarr-dev`, confirmed via `argocd app get arr-sonarr-dev -o yaml` during AF-o0rw:
  ```yaml
  source:
    repoURL: oci://ghcr.io/bjw-s-labs/helm/app-template
    targetRevision: "4.x"
    helm: {values: "..."}
  ```
  No `chart:` field, no `path:` field. This matches `appset-workloads.yaml`'s committed `template.spec.source` exactly (see `apps/arr-stack/argocd/appset-workloads.yaml` lines 115-118 as merged by AF-6jta) -- not a rendering fluke, the file itself is wrong.
- Argo CD source, verified directly against a local clone (`~/src/github.com/argoproj/argo-cd`), not guessed:
  - `util/argo/argo.go:598-614` (`validateSourcePermissions`, single-source branch): `if source.RepoURL == "" || (source.Path == "" && source.Chart == "")` fails with the exact `InvalidSpecError` message above whenever both `path` and `chart` are empty. This check is unconditional -- there is no special case for an `oci://`-prefixed `repoURL`, and no code path treats "chart name embedded in the OCI URL's path" as satisfying the requirement.
  - `reposerver/repository/repository.go:1225-1226`: Argo CD does `strings.TrimPrefix(r.Repository, "oci://")` with the comment "trimming oci:// prefix since it is currently not supported by Argo CD (OCI repos just have no scheme)" -- `repoURL` for an OCI Helm source is expected to be the bare registry+namespace host/path with NO `oci://` scheme, and the chart name is supplied via the separate, mandatory `chart:` field, never appended to `repoURL`'s path.
- This repo's own already-live, already-working `akkoma` Application (`apps/akkoma/argocd/appset.yaml`, live-verified via `argocd app get akkoma-dev -o yaml` in a prior epic) proves the correct shape directly:
  ```yaml
  repoURL: ghcr.io/adamancini/charts    # no oci:// scheme
  chart: akkoma                          # explicit, separate field
  targetRevision: 0.6.1
  ```
  This is exactly the shape `appset-workloads.yaml` should have used and did not.
- Root cause of the wrong assumption: `docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md`'s own snippet stated "oci:// source: chart name is part of the path, so `chart:` stays unset, per onboarding.md's documented rule for OCI sources." That "onboarding.md rule" is real (`docs/onboarding.md`'s step 1, "`chart.name` must stay unset for `oci://` URLs") but it describes Kargo's `Warehouse` `chart:` subscription schema (a distinct object from an Argo CD `Application.spec.source`), where the rule is correct: for an OCI registry, each `repoURL` is dedicated to one chart, so Kargo's separate `name` field must stay unset. The design spec conflated the two unrelated schemas and carried Kargo's rule over into the Argo CD Application source, where the opposite is true (a separate, mandatory `chart:` field is always required for OCI Helm sources, regardless of `oci://` prefixing). `onboarding.md` itself does not state the wrong rule as a general Argo CD convention -- it is correctly scoped to the Kargo Warehouse subscription it documents; this triage pass added a clarifying note there distinguishing the two schemas so a future onboarder doesn't repeat the same conflation (see Links/Notes below).

ROOT CAUSE (confirmed, not a hypothesis):
1. `apps/arr-stack/argocd/appset-workloads.yaml`'s `template.spec.source` block sets only `repoURL: oci://ghcr.io/bjw-s-labs/helm/app-template` and `targetRevision: 4.x` -- no `chart:` field.
2. Argo CD's single-source spec validation (`util/argo/argo.go:598-614`) unconditionally requires `path` or `chart` to be non-empty; an `oci://`-prefixed `repoURL` does not satisfy this by itself.
3. The design spec's own rationale comment for this omission misapplied `docs/onboarding.md`'s Kargo-Warehouse-specific "chart name stays unset for oci:// URLs" rule to the unrelated Argo CD Application source schema.

CONFIG (if relevant):
Not applicable -- no live cluster config involved; this is a static manifest edit to an already-merged file. No new secrets, env vars, or credentials are introduced (this OCI registry pull is the same unauthenticated `ghcr.io` pull pattern `apps/akkoma/argocd/appset.yaml` already uses live).

KEY FILES:
Modify: `apps/arr-stack/argocd/appset-workloads.yaml` (`template.spec.source` block only). No other file needs a code change -- `apps/arr-stack/argocd/appset-kargo.yaml`, `apps/arr-stack/argocd/kargo-chart/`, and all 18 `apps/arr-stack/env/*/*/release.yaml` files are unaffected (this defect is isolated to the workload ApplicationSet's Helm chart source, not the Kargo pipeline generator or the promotion-target contract files).

IMPLEMENTATION:
In `apps/arr-stack/argocd/appset-workloads.yaml`, change the `template.spec.source` block from:
```yaml
      source:
        repoURL: oci://ghcr.io/bjw-s-labs/helm/app-template
        targetRevision: 4.x
        helm:
          values: |
            ...
```
to:
```yaml
      source:
        repoURL: ghcr.io/bjw-s-labs/helm
        chart: app-template
        targetRevision: 4.x
        helm:
          values: |
            ...
```
Three changes only: (1) `oci://` scheme prefix removed from `repoURL`, (2) `app-template` removed from `repoURL`'s path (it was the final path segment), (3) a new `chart: app-template` field added. `targetRevision: 4.x` is unchanged. The entire `helm.values` block (the multi-line string with `defaultPodOptions`, `controllers`, `service`, `ingress`, `persistence`, and the `hasDownloads` conditional) is byte-identical -- untouched by this fix. The matrix generator's `list`/`git` generators, the `template.metadata` block, `destination`, and `syncPolicy` are all byte-identical -- untouched.

USER INTENT:
The user needs to trust that every workload Application this design generates is a spec Argo CD will actually accept and reconcile -- not just a manifest that looks plausible under `helm template`/static YAML linting, which is exactly why this defect passed every static check in this epic (AF-6jta's own verification, this repo's `e2e/observability_test.rb` suite) and was only caught by a real Argo CD control plane's spec validation. The fix must be verifiable without a live cluster touch, the same static-verification discipline this epic has used throughout -- by statically confirming the corrected spec satisfies the exact validation rule read directly from Argo CD's source, not by re-guessing or re-trusting the original (wrong) assumption a second time.

OUT OF SCOPE:
- Re-running AF-o0rw's Step 3-5 live checks against the real shared instance to confirm the 18 workload Applications actually reach `Synced`/`Healthy` after this fix merges -- that re-verification happens after this story closes and merges, run by the dispatcher (continuing AF-o0rw), not as part of this story's own scope. This story is static-only, same as every other developer-claimable story in this epic.
- Reopening AF-6jta (the story that introduced this defect) -- this is a forward-fix on an already-merged file, matching this epic's established pattern (AF-yse2 patched AF-hb2f's merged files the same way) of never reopening closed/accepted stories.
- Any change to `apps/arr-stack/argocd/appset-kargo.yaml`, `kargo-chart/`, or any `release.yaml` file -- none are affected by this defect.
- Any change to `bootstrap/*.yaml` -- standing epic-wide negative assertion, unaffected by this fix.
- Correcting every other historical inaccuracy in `docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md` beyond what this triage pass already applied directly (see Notes/Comments) -- the doc has been corrected in place for this defect plus three pre-existing ones (tag/digest, overseerr/seerr, param-path/indentation) and given a top-of-file historical-document disclaimer; it is not this story's scope to re-audit it further.

DIFF BUDGET:
1 file modified (`apps/arr-stack/argocd/appset-workloads.yaml`), 0 files added/deleted. Expect exactly 3 changed lines in the `template.spec.source` block (repoURL value change, one new `chart:` line); everything else in the file is byte-identical to the pre-fix version.

PRODUCES:
- `apps/arr-stack/argocd/appset-workloads.yaml` -> corrected `template.spec.source` block
    spec: `repoURL: ghcr.io/bjw-s-labs/helm` (no `oci://` scheme), `chart: app-template` (new, explicit field), `targetRevision: 4.x` (unchanged), `helm.values` block unchanged
    source: this bug's own AC #1-#3, verified against Argo CD source (`util/argo/argo.go:598-614`, `reposerver/repository/repository.go:1225-1226`) and this repo's live-working `apps/akkoma/argocd/appset.yaml` precedent

TESTING:
Static only -- no live cluster touch required or permitted for this story (matching every other developer-claimable story in this epic; live re-verification is out of scope, see above).
1. Statically substitute the matrix generator's params for at least one `hasDownloads: true` app/stage (e.g. `sonarr`/`dev`) and one `hasDownloads: false` app/stage (e.g. `prowlarr`/`staging`) into the corrected `template.spec.source` block by hand and confirm the resulting `spec.source` YAML has: a non-empty `chart` field, a `repoURL` value with no `oci://` prefix, and no `path` field -- i.e., it satisfies Argo CD's `validateSourcePermissions` single-source rule (`RepoURL != "" && (Path != "" || Chart != "")`) read directly from `util/argo/argo.go:598-614`.
2. Repo-wide grep confirming `apps/arr-stack/argocd/appset-workloads.yaml` contains no `oci://` substring anywhere after the fix, and contains exactly one `chart:` line with value `app-template`.
3. Diff the fixed file against the pre-fix committed version (`git show 63efac6:apps/arr-stack/argocd/appset-workloads.yaml`) and confirm the diff touches only the `repoURL`/`chart` lines inside `template.spec.source` -- everything else (matrix generators, `helm.values` block including the `hasDownloads` conditional, `template.metadata`, `destination`, `syncPolicy`) is byte-identical.
4. Regression: run the existing static suite, `ruby e2e/observability_test.rb`, and confirm it still passes with the same pass count as before this change (this story does not add a new permanent assertion to that suite -- AF-vm0q, the epic's capstone, owns adding the permanent regression check for this specific invariant; this story's own static checks above are its own delivery evidence).

Acceptance Criteria:
1. [Ubiquitous] `apps/arr-stack/argocd/appset-workloads.yaml`'s `template.spec.source.repoURL` is `ghcr.io/bjw-s-labs/helm`, with no `oci://` scheme prefix.
2. [Ubiquitous] `template.spec.source` carries an explicit `chart: app-template` field.
3. [Ubiquitous] `targetRevision: 4.x` and the entire `helm.values` block (including the `hasDownloads` conditional in both branches) are byte-identical to the pre-fix version -- no unrelated changes.
4. [Event] Hand-substituting the matrix/git-files params for at least one `hasDownloads: true` app/stage and one `hasDownloads: false` app/stage produces a rendered `spec.source` with a non-empty `chart` and a `repoURL` with no `oci://` prefix, satisfying Argo CD's `validateSourcePermissions` single-source rule confirmed directly against `util/argo/argo.go:598-614`.
5. [Unwanted] The file contains no `oci://` substring anywhere after the fix.
6. [Unwanted] No field outside `template.spec.source`'s `repoURL`/`chart` lines changes -- diff against the pre-fix committed file (`63efac6`) touches only those lines.
7. [Unwanted] `bootstrap/*.yaml` is not modified by this fix (standing epic-wide negative assertion).
8. Regression: `ruby e2e/observability_test.rb` passes with 0 failures after the fix.
9. Root cause (Argo CD's unconditional single-source validation rule, and the design doc's conflation of Kargo Warehouse vs. Argo CD Application source schemas) is documented in the commit message, citing the two Argo CD source locations verified above.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory -- ApplicationSet/Application source conventions, OCI Helm source shape), devops-toolkit:yaml-kubernetes-validator, devops-toolkit:helm-chart-developer

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-20T14:43:59Z dep_added: blocks AF-vm0q

## Links
- Parent: [[AF-j5rz]]
- Blocks: [[AF-vm0q]]

## Comments
