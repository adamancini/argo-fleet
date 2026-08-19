---
id: AF-8r8l
title: "Seed arr-stack release.yaml promotion-target files for all six apps"
status: open
priority: 1
type: task
parent: AF-j5rz
created_at: 2026-08-18T18:54:12Z
created_by: ada
updated_at: 2026-08-19T15:32:42Z
content_hash: "sha256:19259cb78c03b1099c3e3d6ee06008153f9b56e470fc9f6e0586cd89838e93e8"
blocks: [AF-6jta, AF-vm0q]
was_blocked_by: [AF-q5yh, AF-hb2f]
follows: [AF-hb2f, AF-iv8x]
---

## Description
Description:
Seed the 18 `apps/arr-stack/env/<app>/<stage>/release.yaml` contract files (6 apps x dev/staging/prod) that both halves of this design need as a precondition: Kargo's per-app promotion task (AF-hb2f's `tasks.yaml`) writes to them, and `appset-workloads.yaml` (Story 4 / AF-6jta) reads them via its `git files` generator to know what image reference to render.

BUG RESOLUTION (AF-hb2f discovered-bug follow-up, applied here before any developer claims this story):
AF-hb2f's delivered `tasks.yaml` writes `${{ imageFrom(vars.image).Digest }}` -- a `sha256:<hex>` string -- into this file's `imageTag` key (the key name is fixed by AF-hb2f's already-merged AC and is NOT renamed by this story; renaming it would require reopening AF-hb2f's yaml-update step, which is explicitly out of scope). That means `imageTag` holds a digest, never a tag, for the entire lifetime of this design. The seed value in this story's original draft (`imageTag: release`) was a tag-shaped literal for a field that only ever holds digests -- if bound into app-template's `tag:` field (which AF-6jta's original draft did), it renders `repository:release` pre-promotion and `repository:sha256:...` post-promotion, and the latter is not a parseable OCI reference (a tag cannot contain a colon). Fixed here: seed each app's three `release.yaml` files with that app's REAL, currently-resolvable digest for its `release` channel tag -- not a placeholder, and not the literal string `release`. This mirrors this repo's own established precedent: `apps/akkoma/env/{dev,staging,prod}/release.yaml` seeds `image.tag: v3.20.0` / `v3.19.0`, a real resolvable version, not a placeholder -- akkoma's Warehouse uses a semver strategy so a real tag was the natural seed; arr-stack's Warehouse uses a Digest strategy, so a real digest is the equivalent seed. AF-6jta (this story's dependent) is amended in lockstep to bind this field to app-template's `digest:` field, not `tag:`.

Context:
Per the design spec's `env/<app>/<stage>/release.yaml` contract, this is the one genuinely per-instance piece of state in the whole design -- not template-able, because it's exactly what Kargo's promotion writes back to on every promote. The seed content is intentionally minimal and identical ACROSS THE THREE STAGES OF ONE APP (not across all 18 files -- see the correction above): `imageTag: "sha256:<hex>"` (the current digest of that app's `ghcr.io/hotio/<app>:release` tag at seed time -- every app's Warehouse subscribes to that tag via `imageSelectionStrategy: Digest`/`constraint: release`, per AF-hb2f's delivered `warehouse.yaml`) and `values: {}` (reserved for future stage-specific overrides; empty is correct for this PoC -- the design spec does not call for any stage-specific values beyond what `appset-workloads.yaml`'s template already hardcodes).

These files must exist as real files in git BEFORE `appset-workloads.yaml`'s `git files` generator (`path: "apps/arr-stack/env/{{.name}}/*/release.yaml"`) can discover anything -- an ApplicationSet git-files generator only picks up paths that exist at the revision it reads, so Story 4 (AF-6jta) is `blocked_by` this story regardless of the spike's (AF-iv8x, already resolved) outcome.

USER INTENT:
A developer or reviewer opening any one of these 18 files needs to see, at a glance, exactly what Kargo has most recently promoted for that app/stage -- and needs the pre-promotion (seed) state to be a genuinely pullable image reference, not a placeholder that only becomes valid after the first real promotion. Each file stores exactly the state its app/stage's next Application render will read; the user can trust that this file's content IS the promoted (or, pre-promotion, the seeded-real) state, not a cached or derived copy of it, and that the very first render of the workload Application (before any Kargo promotion has ever run) resolves to a real, pullable image.

IMPLEMENTATION:
For each of the six apps, first resolve the CURRENT digest of that app's `release` channel tag (do this at implementation time, not from memory -- the value will likely already be stale by the time of the epic's live-verification stories, AF-o0rw/AF-c17x/AF-4wkn, and that is expected and harmless: the Warehouse's `Digest` strategy will simply discover the newer digest as the next Freight the moment its `dev` Stage is reconciled, exactly the mechanism the epic exists to prove):
```bash
# any one of these resolves the same value; use whichever tool is available
crane digest ghcr.io/hotio/sonarr:release
skopeo inspect --format '{{.Digest}}' docker://ghcr.io/hotio/sonarr:release
docker manifest inspect --verbose ghcr.io/hotio/sonarr:release | jq -r '.Descriptor.digest'
```
Repeat for `radarr`, `lidarr`, `bazarr`, `prowlarr`, `overseerr`. Then create all 18 files -- the three stage files for one app share that app's resolved digest (none has been promoted yet, so dev/staging/prod all start from the same initial state, exactly like `apps/akkoma/env/{dev,staging,prod}/release.yaml` all started from one shared initial version before promotions diverged them):
```yaml
imageTag: "sha256:<that app's resolved digest, 64 lowercase hex chars>"
values: {}
```
at these paths:
```
apps/arr-stack/env/sonarr/dev/release.yaml
apps/arr-stack/env/sonarr/staging/release.yaml
apps/arr-stack/env/sonarr/prod/release.yaml
apps/arr-stack/env/radarr/dev/release.yaml
apps/arr-stack/env/radarr/staging/release.yaml
apps/arr-stack/env/radarr/prod/release.yaml
apps/arr-stack/env/lidarr/dev/release.yaml
apps/arr-stack/env/lidarr/staging/release.yaml
apps/arr-stack/env/lidarr/prod/release.yaml
apps/arr-stack/env/bazarr/dev/release.yaml
apps/arr-stack/env/bazarr/staging/release.yaml
apps/arr-stack/env/bazarr/prod/release.yaml
apps/arr-stack/env/prowlarr/dev/release.yaml
apps/arr-stack/env/prowlarr/staging/release.yaml
apps/arr-stack/env/prowlarr/prod/release.yaml
apps/arr-stack/env/overseerr/dev/release.yaml
apps/arr-stack/env/overseerr/staging/release.yaml
apps/arr-stack/env/overseerr/prod/release.yaml
```
The app names and count (6 apps x 3 stages = 18) must exactly match the per-app parameter table in both AF-hb2f's `appset-kargo.yaml` and Story 4's (AF-6jta) `appset-workloads.yaml` -- a mismatch here (a 7th app, a missing stage, a typo'd app name) is exactly the class of drift the static verification story (AF-vm0q) is built to catch, so double-check the list against the epic's per-app parameter table before creating files, not against memory.

KEY FILES:
Create: the 18 `apps/arr-stack/env/<app>/<stage>/release.yaml` files listed above. No existing file is modified.

OUT OF SCOPE:
- Any stage-specific `values:` content -- the design specifies `values: {}` for every file; a future story that needs per-stage overrides is separate work, not guessed at here.
- The Kargo chart that writes to these files (AF-hb2f, already delivered) and the workloads ApplicationSet that reads them (AF-6jta) -- this story only seeds the files themselves. AF-6jta binds this file's `imageTag` value to app-template's `digest:` field (not `tag:`) -- that binding change is AF-6jta's scope, not this one's.
- Renaming the `imageTag` key -- fixed by AF-hb2f's already-delivered `yaml-update` step; out of scope for this story (and for AF-6jta) to change.

DIFF BUDGET:
18 new files, 0 modified. ~36 LOC total (2 lines per file).

CONSUMES:
- AF-hb2f: apps/arr-stack/argocd/kargo-chart/templates/tasks.yaml -> PromotionTask `promote`
    spec: yaml-update step targets path ./src/apps/arr-stack/env/{{ .Values.appName }}/${{ ctx.stage }}/release.yaml, key: imageTag, value: ${{ imageFrom(vars.image).Digest }} (a sha256:<hex> string, per AF-hb2f's delivered warehouse.yaml using imageSelectionStrategy: Digest)
    source: AF-hb2f's own PRODUCES block and delivered code -- confirms both the exact per-app/per-stage path shape AND that the value written is always a digest, never a tag

PRODUCES:
- `apps/arr-stack/env/<app>/<stage>/release.yaml` (18 files) -> promotion-target contract file
    schema: imageTag (string, "sha256:<64 lowercase hex chars>" -- a digest, never the literal tag name, seeded at authoring time with each app's real current release-tag digest), values (object, empty at seed)
    source: docs/superpowers/specs/2026-08-18-arr-stack-appset-design.md `env/<app>/<stage>/release.yaml` contract section (key/shape), corrected per this story's BUG RESOLUTION note (value semantics -- the design spec's own literal snippet elsewhere, lines 203-205, is documented as needing a doc-only fix, tracked outside this story)

TESTING:
No unit-test suite exists for this repo's GitOps manifests -- verification is static only:
- `ruby -ryaml -e "Dir.glob('apps/arr-stack/env/*/*/release.yaml').each { |f| d = YAML.load(File.read(f)); raise \"#{f}: bad shape\" unless d['imageTag'] =~ /\Asha256:[0-9a-f]{64}\z/ && d['values'] == {} }; puts 'OK'"` -- confirms all 18 files exist, parse, hold a well-formed digest (not the literal string `release` or any other tag-shaped value), and share the identical `values: {}` shape.
- `Dir.glob('apps/arr-stack/env/*/*/release.yaml').length` must equal exactly 18, and the discovered app-name set (glob level 1) must exactly equal `{sonarr,radarr,lidarr,bazarr,prowlarr,overseerr}` and the stage set (glob level 2) must exactly equal `{dev,staging,prod}` for every app -- discover by glob, do not hard-code the count check only.
- Per app, confirm the three stage files' `imageTag` values are byte-identical to each other (none has been promoted yet, so all three stages of one app share one seed digest) -- but do NOT assert equality across different apps (each app has its own image, hence its own digest).

Acceptance Criteria:
1. [Ubiquitous] Exactly 18 `release.yaml` files exist under `apps/arr-stack/env/`, one per (app, stage) pair for all 6 apps x 3 stages.
2. [Ubiquitous] Every file's `values` key is exactly `{}`, and every file's `imageTag` value matches `sha256:<64 lowercase hex chars>` -- a well-formed digest, never the literal string `release` or any other tag-shaped value.
3. [Ubiquitous] For each app, all three stage files' `imageTag` values are byte-identical to each other (shared seed, no promotion has occurred yet).
4. [Ubiquitous] The app-name set discovered by glob exactly matches the epic's per-app parameter table (`sonarr`, `radarr`, `lidarr`, `bazarr`, `prowlarr`, `overseerr`) -- no extra, no missing, no typo'd name.
5. [Unwanted] No file shall contain a real/placeholder secret value, a hand-picked non-digest tag string (including the literal `release`), an empty string, or any stage-specific override -- every file's `imageTag` is a syntactically valid digest.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform (mandatory -- confirms the release.yaml contract shape and the Digest-strategy Warehouse semantics against its Kargo promotion-patterns reference material before seeding)

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-18T18:54:17Z dep_added: blocked_by AF-q5yh
- 2026-08-18T18:56:06Z dep_added: blocks AF-6jta
- 2026-08-18T18:57:53Z dep_added: blocks AF-vm0q
- 2026-08-18T19:11:20Z dep_removed: was_blocked_by AF-q5yh
- 2026-08-18T19:11:43Z dep_added: blocked_by AF-hb2f
- 2026-08-19T15:09:39Z dep_removed: was_blocked_by AF-hb2f
- 2026-08-19T15:09:40Z status: open -> in_progress
- 2026-08-19T15:09:40Z auto-follows: linked to predecessor AF-hb2f
- 2026-08-19T15:09:40Z claimed by dev-AF-8r8l
- 2026-08-19T15:13:01Z status: in_progress -> open
- 2026-08-19T15:13:51Z status: open -> in_progress
- 2026-08-19T15:13:51Z auto-follows: linked to predecessor AF-iv8x
- 2026-08-19T15:13:51Z claimed by dev-AF-8r8l
- 2026-08-19T15:32:42Z status: in_progress -> open
- 2026-08-19T15:32:42Z released by ada

## Links
- Parent: [[AF-j5rz]]
- Blocks: [[AF-6jta]], [[AF-vm0q]]
- Was blocked by: [[AF-q5yh]], [[AF-hb2f]]
- Follows: [[AF-hb2f]], [[AF-iv8x]]

## Comments

### 2026-08-19T15:02:49Z ada
BUG TRIAGE (Sr PM): discovered by AF-hb2f's deliver-only follow-up developer -- release.yaml's imageTag key holds a digest (per AF-hb2f's delivered tasks.yaml, imageFrom(vars.image).Digest), but this story's original draft seeded a tag-shaped literal (imageTag: release). If bound into app-template's tag: field (AF-6jta's original draft), a digest in a tag field renders an unparseable repository:sha256:... reference. Resolution applied directly to this story's body: seed each app's 3 stage files with that app's real, currently-resolvable sha256 digest for its release-channel tag (mirrors this repo's own apps/akkoma/env/*/release.yaml precedent of seeding a real resolvable value, not a placeholder), never the literal string release or an empty value. AF-6jta amended in lockstep to bind digest: not tag:. AF-vm0q (capstone) amended to verify the corrected shape and to add a regression check for this exact bug. AF-hb2f itself is NOT reopened -- the imageTag key name is unchanged, fixed by its already-merged yaml-update step.

### 2026-08-19T15:13:01Z ada
loop: reset orphaned in_progress to open (no developer worktree found; prior session presumed dead)
