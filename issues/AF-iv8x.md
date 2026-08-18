---
id: AF-iv8x
title: "Spike: confirm ApplicationSet matrix generator interpolates sibling list params into git files path"
status: in_progress
priority: 0
type: task
labels: [spike, delivered]
parent: AF-j5rz
created_at: 2026-08-18T18:55:02Z
created_by: ada
updated_at: 2026-08-18T19:44:17Z
content_hash: "sha256:5c92b7f0bf020e45dad58cdfe10cb3618f30cdc6ffc4bf8983e841b1f86ffa18"
blocks: [AF-6jta, AF-vm0q]
assignee: dev-AF-iv8x
---

## Description
Description:
SPIKE -- confirm, before `appset-workloads.yaml` is implemented for real, whether the shared `demo1`/`demo2`/`kargo` instance's Argo CD version supports a `matrix` generator's inner `git files` generator interpolating `{{.name}}` from the outer `list` generator's sibling element (the exact shape `apps/arr-stack/argocd/appset-workloads.yaml`'s design requires: `path: "apps/arr-stack/env/{{.name}}/*/release.yaml"`, where `.name` comes from the OUTER `list` generator, not the `git files` generator itself). This is a hard gate, not a nice-to-have: the design spec's own language is explicit that this "must be settled before implementation, not deferred silently," and the user has separately confirmed spike-first over guessing.

Context:
Argo CD's `matrix` generator combines two child generators; whether one child generator's template fields can reference the OTHER child generator's params (as opposed to only the matrix's own combined output being usable downstream in `template:`) is a version- and generator-pair-dependent capability, not something safe to assume from the top-level `matrix` generator's existence alone. `sedemo-platform`'s `demo-microservices` precedent (referenced in the design spec) uses two static `list` generators in its matrix, which does NOT exercise this exact cross-generator-interpolation-inside-a-generator's-own-config capability -- it is not a valid precedent for THIS specific shape, only for "matrix generators work on this instance in general."

Per this repo's own established discipline (`AGENTS.md`'s Argo CD section): check the `devops-toolkit:akp-platform` skill and Argo CD source (`~/src/github.com/argoproj/argo-cd`) / declarative-setup docs (https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/) before guessing at generator behavior. Then, per the design spec's own explicit preference: if a live check against the shared instance is safe and read-only (creates nothing), prefer that over a source-only guess -- specifically `argocd version` (confirms the exact ApplicationSet-controller version actually running, which may differ from the OSS release the source you're reading corresponds to) and a dry-run `argocd appset generate` against a throwaway matrix+git-files generator block (server-side RPC, creates nothing, safe even on this shared instance -- see `.vault/knowledge/patterns/Render-diff verification primitive for ApplicationSet changes.md`).

USER INTENT:
This story emits a decision record the next story's developer can act on directly, without re-deriving it. The user needs a documented, evidence-based answer -- not an assumption -- to "does the exact generator shape this design needs actually work on the instance we're deploying to," because the two possible answers lead to materially different downstream stories (Story 4 as currently scoped, vs. a not-yet-written fallback story that drops the auto-pickup mechanism entirely). Guessing wrong here means Story 4 either wastes a full implementation cycle on an unsupported shape, or -- worse -- silently ships something that looks like it works in a dry-run but never actually re-renders on a real promotion.

IMPLEMENTATION:
1. Check `devops-toolkit:akp-platform` skill and Argo CD source/docs first (per `AGENTS.md`): the matrix generator's implementation lives in the locally-cloned Argo CD source tree at `~/src/github.com/argoproj/argo-cd`, under its `applicationset/generators` package (file `matrix.go` in that package, confirmed present in the local clone at the time of this story's authoring) -- read it and its accompanying docs page (`docs/operator-manual/applicationset/Generators-Matrix.md` in that same tree) to confirm from the code/CHANGELOG whether/when cross-generator param interpolation within a sibling generator's own config fields (as opposed to only in the final `template:` block) was added, and whether it's gated behind `goTemplate: true` (the design's `appset-workloads.yaml` already sets `goTemplate: true`, `goTemplateOptions: ["missingkey=error"]`).
2. Run `argocd version` against the shared instance to confirm the exact Argo CD version in use (do not assume it matches whatever OSS release tag the locally-cloned source happens to be checked out at).
3. If a dry-run RPC check is possible without touching anything real: construct a throwaway `matrix` generator block (2-3 dummy list elements x a `git files` generator referencing `{{.name}}` in its `path`, pointed at a `path` that's safe to probe -- e.g. `apps/arr-stack/env/{{.name}}/*/release.yaml` once AF-8r8l's files exist, or a narrower probe against an existing app's `env/*/release.yaml` shape if AF-8r8l hasn't landed yet) and run it through `argocd appset generate -o json --grpc-web` (server-side dry-run, creates nothing). Confirm whether the rendered output actually reflects per-element interpolated paths, or errors, or silently renders the literal unresolved string.
4. Document BOTH possible outcomes explicitly in this story's resolution (Notes/Comments), not just the one that turns out true:
   - (a) SUPPORTED: proceed with Story 4 exactly as currently scoped (git-files-generator design, per the committed spec).
   - (b) UNSUPPORTED: Story 4 as currently scoped must NOT be implemented as written. Report back to the Sr PM (via the dispatcher) so a replacement story can be authored for the fallback: a static `dev`/`staging`/`prod` list generator as the matrix's second generator (matching `sedemo-platform`'s `demo-microservices` precedent), accepting the loss of the "Kargo commits to release.yaml and the ApplicationSet just picks it up" auto-pickup mechanism `akkoma`/`soju` rely on. Do NOT write the fallback's implementation yourself in this story -- the design spec and the epic are explicit that guessing at the fallback now, before the spike resolves, is exactly the failure mode this story exists to prevent.

KEY FILES:
No files created or modified under normal resolution -- this is an investigation story. If outcome (b) occurs, this story's ONLY file-producing action is a comment/note recording the finding; a NEW story is created separately for the fallback implementation.

OUT OF SCOPE:
- Implementing `appset-workloads.yaml` itself, under either outcome -- that is Story 4 (if supported) or a not-yet-created follow-up story (if unsupported). This story produces a decision record, not code.
- Any live mutation of the shared instance -- every live-touching step in this story (`argocd version`, `argocd appset generate` dry-run) is explicitly read-only/server-side-dry-run and creates nothing; if at any point a step would create, update, or delete a real resource, stop and treat that as a signal this story's scope has drifted, not a green light to proceed.

DIFF BUDGET:
0 files under normal resolution (pure investigation). If a throwaway probe file is needed to construct a dry-run generator block, it must live outside `apps/arr-stack/` (e.g. a scratch file, never committed) and must be deleted before this story closes.

PRODUCES:
- This issue's own Notes/Comments -> decision record
    spec: supported: true | false; evidence: [argocd version output, appset generate dry-run output or source/changelog citation]; fallback_required: true | false
    source: this story's own empirical finding -- consumed by Story 4 (AF-<workloads>, created after this spike closes) exactly as AF-d3ax consumed AF-ogxu's decision record in this repo's own prior epic (same pattern, reused deliberately)

TESTING:
This is a spike -- "testing" here means the verification steps in IMPLEMENTATION themselves (source/changelog citation, `argocd version`, dry-run `argocd appset generate` diff) are the deliverable, not a separate test suite. The bar for closing this story: the resolution documents BOTH the confirmed answer AND the evidence used to confirm it (a citation or command output a reviewer could independently re-run), not just a stated conclusion.

Acceptance Criteria:
1. [Ubiquitous] The Argo CD version actually running on the shared `demo1`/`demo2`/`kargo` instance is confirmed and recorded (`argocd version` output, not an assumption).
2. [Event] The matrix-generator-references-sibling-params question is answered with cited evidence: either a source/changelog citation (with exact file/line or PR/release reference) or a dry-run `argocd appset generate` render showing genuinely interpolated per-element paths.
3. [Ubiquitous] Both possible outcomes (supported / unsupported) and their downstream consequences are documented in this story's resolution, not just the one that turned out true.
4. [Unwanted] No live resource is created, updated, or deleted against the shared instance by any step in this story.
5. If unsupported: this story's resolution explicitly states that Story 4 (AF-<workloads>) must not be implemented as currently scoped, and that a new fallback story is required -- and does NOT itself contain that fallback's implementation.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory -- check before guessing at generator behavior, per `AGENTS.md`)

## Acceptance Criteria


## Design


## Notes
SPIKE RESOLVED: supported: true; fallback_required: false. Matrix inner (2nd) child generator DOES interpolate outer (1st) child's params into its own config fields, incl. git-files 'path'. Evidence: (1) source -- matrix.go:50-55 passes child#1 params into child#2 getParams; generator_spec_processor.go:175-176 'InterpolateGenerator allows interpolating the matrix's 2nd child generator with values from the 1st child generator'; utils.go:337 RenderGeneratorParams deep-walks all string fields (GitGenerator.Files[].Path covered). Landed in v2.5.0 (commit 5515cde64, #10236); server is v3.4.6+c2a2a97.dirty (client v3.5.1). (2) live dry-run -- 'argocd appset generate -o json --grpc-web' on a throwaway list x git-files matrix returned 6 apps with correct per-element interpolated paths, cross-contamination mismatches=0 (12 would indicate no interpolation); negative control with a bogus list element still returned 6 (not 9, no error), proving per-element resolution; a third probe confirmed the exact {{.name}}-immediately-before-* glob adjacency the design uses. (3) webhook re-render works -- webhook.go:536-550 interpolates child#2 before deciding to refresh, so Kargo-commit auto-pickup is preserved. NO live mutation: version/generate/list are read-only or server-side dry-run; verified no probe-*/arr-* Applications or ApplicationSets exist. 0 files changed. AF-6jta UNBLOCKED as currently scoped. Caveats for AF-6jta: (a) list MUST be generators[0], git MUST be generators[1] -- interpolation flows first->second only; (b) a list element whose dir does not exist yields ZERO apps SILENTLY (exit 0, no error) -- assert rendered app COUNT, not just exit code, and land AF-8r8l first; (c) matrix takes exactly 2 children; (d) valuesObject string-field-only templating restriction still applies.


## nd_contract
status: delivered

### evidence
- Transitioned via pvg story deliver on 2026-08-18.

### proof
- [ ] Developer evidence block must remain authoritative above this contract.


## History
- 2026-08-18T18:56:07Z dep_added: blocks AF-6jta
- 2026-08-18T18:57:53Z dep_added: blocks AF-vm0q
- 2026-08-18T19:36:09Z status: open -> in_progress
- 2026-08-18T19:36:09Z claimed by dev-AF-iv8x
- 2026-08-18T19:43:30Z status: in_progress -> in_progress

## Links
- Parent: [[AF-j5rz]]
- Blocks: [[AF-6jta]], [[AF-vm0q]]

## Comments

### 2026-08-18T19:43:02Z ada
DECISION RECORD (AF-iv8x spike) -- machine-readable summary:

    supported: true
    fallback_required: false
    unblocks: AF-6jta as currently scoped (git-files-generator design, per committed spec)

## VERDICT: SUPPORTED

A `matrix` generator's INNER (second) child generator CAN interpolate params produced by the
OUTER (first) child generator inside its OWN config fields -- including a `git files` generator's
`path`. The exact shape `apps/arr-stack/env/{{.name}}/*/release.yaml` (where `.name` comes from a
sibling `list` generator, not from the git generator itself) is supported on the instance we deploy to.

## AC1 -- Argo CD version on the shared demo1/demo2/kargo instance

    $ argocd version --short
    argocd: v3.5.1+109ca7c.dirty
    argocd-server: v3.4.6+c2a2a97.dirty

Server (and therefore the ApplicationSet controller) is **v3.4.6+c2a2a97.dirty**; client v3.5.1.
Clusters registered: demo1, demo2, kargo, in-cluster.

## AC2 -- Evidence

### (a) Source citation

Local clone `~/src/github.com/argoproj/argo-cd` @ `21804a2ac` (v0.8.0-10807-g21804a2ac).

1. `applicationset/generators/matrix.go:50-55` -- the first child's params (`a`) are passed as the
   `params` argument into the second child's `getParams`, establishing the first -> second data flow:

       g0, err := m.getParams(appSetGenerator.Matrix.Generators[0], appSet, nil, client)
       for _, a := range g0 {
           g1, err := m.getParams(appSetGenerator.Matrix.Generators[1], appSet, a, client)

2. `applicationset/generators/generator_spec_processor.go:175-176` -- explicit doc comment on the
   function that performs it:

       // InterpolateGenerator allows interpolating the matrix's 2nd child generator with values
       // from the 1st child generator

   Called at `generator_spec_processor.go:57` (`Transform`), guarded only by `len(genParams) != 0`.

3. `applicationset/utils/utils.go:337` `RenderGeneratorParams` -> `deeplyReplaceWithFilter`
   (`utils.go:93`) is a generic reflect-based deep walk over the generator struct, so ALL string
   fields are interpolated -- `GitGenerator.Files[].Path` is a plain string field and is therefore
   covered. (The only special-cased field is `Values map[string]string`, `utils.go:361`.)

4. Docs page `docs/operator-manual/applicationset/Generators-Matrix.md` has a dedicated section
   "Using Parameters from one child generator in another child generator" documenting this as a
   supported feature.

5. Feature history -- first landed in **v2.5.0**:

       $ git log --oneline --reverse -S InterpolateGenerator -- applicationset/generators/generator_spec_processor.go
       5515cde64 fix(applicationset): support webhook with matrix interpolation (#9931) (#10236)   [2022-08-11]
       98475bc43 fix: use field-wise templating for child matrix generators (#11661) (#12287)

       $ git tag --contains 5515cde64 | grep -E '^v[0-9]+\.[0-9]+\.0$'
       v2.5.0  v2.6.0  v2.7.0  v2.8.0  v2.9.0 ...

   Server v3.4.6 is far newer than v2.5.0, so the capability is present.

6. `goTemplate: true` gating -- NOT gated behind it; interpolation runs in both modes. But under
   `goTemplate: true`, `RenderGeneratorParams` (`utils.go:349-358`) FORCES `missingkey=error` for the
   generator-interpolation stage regardless of `goTemplateOptions`. The design's
   `goTemplate: true` + `goTemplateOptions: ["missingkey=error"]` is consistent with this.

### (b) Live dry-run render (server-side, created nothing)

Throwaway probe (scratch file outside the repo, since deleted) mirroring the target shape:
outer `list` generator producing `.name` x inner `git files` generator whose own `path` references
`{{.name}}`. Probed against existing `apps/*/env/*/release.yaml` because AF-8r8l has not landed yet.

    generators:
    - matrix:
        generators:
        - list:                                        # child #1 (OUTER)
            elements: [{name: akkoma}, {name: soju}]
        - git:                                         # child #2 (INNER)
            repoURL: https://github.com/adamancini/argo-fleet.git
            revision: HEAD
            files:
            - path: "apps/{{.name}}/env/*/release.yaml"

    $ argocd appset generate -o json --grpc-web probe-matrix-interp.yaml
    app_count=6
    probe-akkoma-dev      | listElem=akkoma | gitPath=apps/akkoma/env/dev
    probe-akkoma-prod     | listElem=akkoma | gitPath=apps/akkoma/env/prod
    probe-akkoma-staging  | listElem=akkoma | gitPath=apps/akkoma/env/staging
    probe-soju-dev        | listElem=soju   | gitPath=apps/soju/env/dev
    probe-soju-prod       | listElem=soju   | gitPath=apps/soju/env/prod
    probe-soju-staging    | listElem=soju   | gitPath=apps/soju/env/staging
    cross-contamination mismatches=0

This is a genuine interpolation, not an accidental pass. Three discriminators were built in:

- **Count discriminator**: 6 apps, not 12. Had `{{.name}}` been dropped or collapsed to a wildcard,
  each of the 2 list elements would have paired with all 6 release.yaml files = 12 Applications with
  akkoma paired to soju paths. Every element resolved to only its own 3 paths (mismatches=0).
- **Literal-string discriminator**: an un-interpolated literal `apps/{{.name}}/env/*/release.yaml`
  matches nothing, which would have surfaced as a "child generator generated no parameters" error
  rather than 6 correctly-pathed apps.
- **Negative control**: adding a bogus third element `nonexistent-app-xyz` still returned
  `app_count=6` (not 9, and no error) -- proving the path is resolved per-element, with the bogus
  element's interpolated glob matching nothing.

**Adjacency fidelity**: the design puts `{{.name}}` IMMEDIATELY before the `*` glob
(`.../env/{{.name}}/*/release.yaml`). A third probe tested that exact adjacency
(`path: "apps/{{.name}}/*/release.yaml"` with elements `akkoma/env`, `soju/env`) and also returned
`app_count=6` with correct per-element paths. Glob-adjacent interpolation works.

### (c) Auto-pickup / re-render on a real promotion does work

The stated worst-case failure mode -- "renders fine in a dry-run but never re-renders on a real
Kargo promotion" -- is explicitly handled. `applicationset/webhook/webhook.go:536-550` interpolates
the second child generator with the first child's params BEFORE deciding whether to refresh:

    // Interpolate second child generator with params from first child generator, if there are any params
    tempInterpolatedGenerator, err := generators.InterpolateGenerator(requestedGenerator1, p, ...)
    ...
    if shouldRefreshGitGenerator(interpolatedGenerator.Git, gitGenInfo) || ...

The very commit that introduced this feature is titled "fix(applicationset): support webhook with
matrix interpolation (#9931)". So the "Kargo commits to release.yaml and the ApplicationSet just
picks it up" mechanism that akkoma/soju rely on is preserved under this design.

## AC3 -- Both outcomes and their downstream consequences

- **(a) SUPPORTED -- THIS IS THE ACTUAL OUTCOME.** Proceed with Story 4 (AF-6jta) exactly as
  currently scoped: the git-files-generator design per the committed spec, with
  `path: "apps/arr-stack/env/{{.name}}/*/release.yaml"`, `goTemplate: true`,
  `goTemplateOptions: ["missingkey=error"]`. The Kargo-commits-then-ApplicationSet-picks-it-up
  auto-pickup mechanism is retained. No fallback story is needed. AF-6jta is unblocked.

- **(b) UNSUPPORTED -- did NOT occur, recorded for completeness.** Had the probe shown the literal
  unresolved string, a cross-contaminated 12-app render, or an interpolation error, then AF-6jta as
  currently scoped must NOT have been implemented as written. The consequence would have been:
  report back so Sr PM triage could author a replacement story using a static `dev`/`staging`/`prod`
  `list` generator as the matrix's second generator (matching sedemo-platform's `demo-microservices`
  precedent), accepting the loss of the auto-pickup mechanism -- every new stage would then require
  a manual edit to `appset-workloads.yaml` instead of being discovered from the committed
  `release.yaml` tree. That fallback is deliberately NOT designed or implemented here.

## AC4 -- No live mutation

Every live step was read-only or a server-side dry-run: `argocd version --short`,
`argocd appset generate` (Generate RPC -- renders and returns, creates nothing),
`argocd app list -o name`, `argocd appset list -o name`. Verified after the probes:

    $ argocd appset list --grpc-web -o name | grep -Ei 'probe|arr'
    confirmed: no probe-*/arr-* ApplicationSets
    $ argocd app list --grpc-web -o name | grep -Ei 'probe|arr'
    confirmed: no probe-*/arr-* Applications

ApplicationSets on the instance are unchanged: akkoma, argo-rollouts-crds, fleet-argocd-apps,
fleet-kargo-apps, gateway-api-crds, infra-apps, kube-prometheus-stack, openebs-localpv,
sealed-secrets, soju, traefik-gateway.

## AC5 -- N/A

Outcome was SUPPORTED, so the "must not implement AF-6jta" clause does not apply. No fallback
implementation is contained in this record.

## Diff budget

0 files created or modified. Worktree `git status -uall --short` is empty. The three throwaway
probe YAMLs lived in a scratch directory outside the repo and were deleted.

## CAVEATS for AF-6jta's developer (constraints, not blockers)

1. **Generator ORDER is load-bearing.** Interpolation flows first-child -> second-child ONLY
   (`matrix.go:50-55`). The `list` generator MUST be `generators[0]` and the `git files` generator
   MUST be `generators[1]`. Reversing them silently breaks interpolation -- the git generator would
   run first with no params to interpolate from.
2. **A list element whose directory does not exist yields ZERO Applications, silently -- no error.**
   Proven by the negative control (bogus element -> app_count stayed 6, exit 0). `missingkey=error`
   does NOT protect against this, because `.name` is present; it is the glob that matches nothing.
   Practical consequence: AF-8r8l (which seeds `apps/arr-stack/env/<app>/<stage>/release.yaml`) must
   land BEFORE AF-6jta can be meaningfully verified, and a per-app typo in the list generator will
   fail open (missing app) rather than loudly. Verify the rendered app COUNT, not just exit 0.
3. **Matrix accepts exactly two child generators** -- not one, not three
   (`matrix.go:18-21,40-46`: ErrLessThanTwoGenerators / ErrMoreThanTwoGenerators).
4. **`valuesObject` templating restriction still applies**, same as the existing akkoma appset:
   the reflect walker only substitutes into STRING fields, so object-typed fields must be spelled
   out with templated leaf values.
5. Use `argocd appset generate -o json --grpc-web` as the verification primitive for AF-6jta, and
   assert the app count and per-app interpolated paths -- exit 0 alone proves nothing (see caveat 2).

### 2026-08-18T19:44:17Z ada
DELIVERY -- AF-iv8x (spike). Full decision record is in the preceding comment; this is the proof/learnings wrapper.

PROOF:

Producing commit SHA: e2bd0438131ac912d527f163a5b4573d533a3934 (story/AF-iv8x HEAD).
No commits were made -- this is an investigation story with a 0-file diff budget, so HEAD is
unchanged from the epic base. Verified:
    $ git diff --name-only epic/AF-j5rz...HEAD   -> (empty)
    $ git status --porcelain -uall               -> (empty)
`pvg verify` was not run because it has NO INPUTS: zero files were created or modified. The three
throwaway probe YAMLs lived in a scratch dir outside the repo and were deleted before delivery.

Commands run (all read-only or server-side dry-run -- none mutate the instance):
    $ argocd version --short
      argocd: v3.5.1+109ca7c.dirty
      argocd-server: v3.4.6+c2a2a97.dirty
    $ argocd appset generate -o json --grpc-web <probe>.yaml     (x3 probes, all exit 0)
    $ argocd app list --grpc-web -o name        (baseline check)
    $ argocd appset list --grpc-web -o name     (baseline check)
    $ git log --oneline --reverse -S InterpolateGenerator -- applicationset/generators/generator_spec_processor.go
    $ git tag --contains 5515cde64

Probe results (pass/fail counts -- 3 probes, 3 pass, 0 fail):
    probe 1 (target shape, list x git-files):        app_count=6 (expected 6)  PASS
                                                    cross-contamination mismatches=0            PASS
    probe 2 (negative control, +bogus element):      app_count=6 (expected 6, NOT 9, no error)  PASS
    probe 3 (exact {{.name}}-adjacent-* glob):       app_count=6 (expected 6)  PASS
Coverage: N/A -- no code was written. Verification coverage is instead expressed as the 3
discriminators (count / literal-string / negative-control) plus source citation, described below.

Acceptance-criteria verification table:
    AC1  Argo CD version confirmed + recorded              PASS  argocd-server v3.4.6+c2a2a97.dirty (client v3.5.1); clusters demo1/demo2/kargo/in-cluster
    AC2  Question answered with cited evidence             PASS  BOTH forms supplied: (i) source cites matrix.go:50-55, generator_spec_processor.go:175-176 + :57, utils.go:337/:93/:349-358, docs Generators-Matrix.md, feature landed v2.5.0 via commit 5515cde64 (#10236), refined by 98475bc43 (#12287); (ii) dry-run render showing genuinely interpolated per-element paths (6 apps, mismatches=0)
    AC3  Both outcomes + consequences documented           PASS  Outcome (a) SUPPORTED recorded as actual; outcome (b) UNSUPPORTED recorded for completeness with its downstream consequence (static list fallback, loss of auto-pickup), explicitly NOT designed or implemented
    AC4  No live resource created/updated/deleted          PASS  Only version/generate/list RPCs used; post-probe verification found no probe-*/arr-* Applications or ApplicationSets; instance appset inventory unchanged (11 appsets, same as baseline)
    AC5  If unsupported: state AF-6jta blocked             N/A   Outcome was SUPPORTED; clause does not apply. Record contains no fallback implementation.

Verdict: SUPPORTED. supported: true; fallback_required: false. AF-6jta is unblocked as currently scoped.

Why the dry-run is trustworthy rather than a coincidence -- three built-in discriminators:
  1. Count: 6 apps, not 12. No interpolation (or a collapsed wildcard) would have paired each of the
     2 list elements with all 6 release.yaml files.
  2. Literal string: an un-interpolated `apps/{{.name}}/env/*/release.yaml` matches nothing and would
     have surfaced as "child generator generated no parameters", not 6 correctly-pathed apps.
  3. Negative control: a bogus third list element left app_count at 6 (not 9), proving per-element
     path resolution rather than a single shared glob.
Plus: webhook.go:536-550 interpolates child #2 before deciding to refresh, so the "renders in dry-run
but never re-renders on a real promotion" failure mode the story called out is genuinely excluded --
Kargo-commit auto-pickup is preserved.

LEARNINGS:

- The spike was worth it, but not for the reason the story predicted. The headline capability
  (matrix cross-generator interpolation) turned out to be 4 years old -- landed in v2.5.0 (Aug 2022),
  server runs v3.4.6 -- so it was never really at risk. The genuinely valuable finding was a caveat
  nobody had scoped: a `list` element whose interpolated glob matches nothing yields ZERO
  Applications SILENTLY, exit 0, no error. `missingkey=error` does not catch it (`.name` is present;
  it's the glob that misses). That is a fail-open mode, and it means AF-6jta must assert rendered app
  COUNT, not just a clean exit -- and that AF-8r8l must land first for AF-6jta to be verifiable.
- Design a dry-run probe with a discriminator, or it proves nothing. My first instinct was
  "run appset generate, check exit 0" -- which would have passed even with interpolation completely
  broken. Encoding both sides of the matrix into the output (`probe.listName` + `probe.gitPath`
  annotations) plus a deliberate 6-vs-12 count expectation and a bogus-element negative control is
  what turned "it ran" into "it interpolated". Reusable pattern for any future generator spike.
- Generator ORDER is load-bearing and silently so. `matrix.go:50-55` only flows child#1 -> child#2.
  The story's phrasing ("`.name` from the OUTER list generator") already implied the right order, but
  it is worth stating explicitly in AF-6jta because reversing the two children breaks interpolation
  with no error -- another fail-open.
- Probe adjacency, not just the mechanism. The target path puts `{{.name}}` immediately before the
  `*` glob. My first probe had `env` sitting between them, which tests the mechanism but not the
  exact string. A third probe with true adjacency cost one command and removed a real residual doubt.
  Cheap fidelity is worth buying on a hard-gate spike.
- Environment gotcha for future agents in this repo: the pvg guard blocks `cd` into a worktree
  outright, so the standard "prefix every command with cd <worktree> &&" instruction in the dispatch
  prompt cannot be followed. Everything has to run via `git -C <worktree>` and absolute paths. Worth
  reconciling the dispatch prompt with the guard, since they currently contradict each other.
