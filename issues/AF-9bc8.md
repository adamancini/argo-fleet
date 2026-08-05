---
id: AF-9bc8
title: "Bug: Design spec line 164 quotes hostpathClass.isDefaultClass as string \"false\", making local-path the default StorageClass"
status: closed
priority: 0
type: bug
labels: [documentation, discovered-by-dev, accepted]
parent: AF-q1il
created_at: 2026-08-05T15:42:03Z
created_by: ada
updated_at: 2026-08-05T16:15:32Z
content_hash: "sha256:53df469427015b47df63dace3e22411699181c546125d2b834626b9d30fa02c8"
follows: [AF-wx9b, AF-cu83, AF-vwvq, AF-pydv]
assignee: dev-AF-9bc8
closed_at: 2026-08-05T16:15:31Z
close_reason: "Accepted via pvg story accept"
led_to: [AF-cbot]
---

## Description
Description:
docs/superpowers/specs/2026-08-05-cluster-lifecycle-and-ingress-storage-design.md
line 164 carries the same quoted-boolean defect that AF-8ik8 (manifest) and
AF-wx9b (plan document) already fixed elsewhere: `hostpathClass.isDefaultClass`
is written as the quoted string `"false"` instead of the unquoted boolean
`false`, which makes `local-path` the cluster's default StorageClass --
the opposite of the design's own stated intent.

DISCOVERED DURING:
AF-wx9b (Bug: Design spec Task 3 quotes hostpathClass.isDefaultClass as
string "false", making local-path the default StorageClass -- that bug
fixed the sibling PLAN document,
docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md,
at lines 16, 726, and 752). While verifying AF-wx9b's fix, the same defect
was found in the sibling DESIGN SPEC, which is upstream of the plan
document. AF-wx9b deliberately did NOT touch the spec: its AC4 is an
explicit [Unwanted] constraint scoping that fix to the three cited lines
of the plan document only. Leaving the spec defective means a future
regeneration of the plan from the spec would re-introduce the exact bug
AF-wx9b and AF-8ik8 already fixed everywhere else, defeating the point of
those fixes.

This is the third bug of this exact root-cause pattern in this epic:
AF-8ik8 fixed the committed manifest
(infrastructure/openebs-localpv/argocd/appset.yaml), AF-wx9b fixed the plan
document, this bug fixes the design spec -- the last remaining source
document that still carries the defect.

SYMPTOMS:
- docs/superpowers/specs/2026-08-05-cluster-lifecycle-and-ingress-storage-design.md:164
  reads (full line, verbatim):
  `` `hostpathClass.name: local-path`, `hostpathClass.isDefaultClass: "false"`. ``
  as part of this sentence (lines 162-165):
  "Values mirror `fleet-infra` exactly: `localpv.basePath: /var/openebs/local`,
  `hostpathClass.name: local-path`, `hostpathClass.isDefaultClass: "false"`.
  Not the default class deliberately — matches fleet-infra's own choice, ..."
- The quoted string `"false"` is the defect. Expected: unquoted boolean
  `false`, matching:
  - The already-fixed plan document,
    docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md:726
    (fixed by AF-wx9b).
  - The already-delivered, already-PM-accepted manifest,
    infrastructure/openebs-localpv/argocd/appset.yaml, which ships
    `hostpathClass.isDefaultClass: false` (unquoted) with an inline comment
    explaining the trap (AF-8ik8).
- Line 176 of this SAME spec file is already correct for reference:
  "`ingressClass.enabled: true` + `isDefaultClass: true`" -- unquoted
  boolean, for Traefik's ingressClass. That is the pattern line 164 must
  match.
- Confirmed line 164 is the only remaining hit of this defect pattern
  anywhere in this repo's docs: AF-wx9b's developer already swept the full
  plan document and its two sibling infra-layer stories
  (AF-vwvq traefik-gateway, AF-qujb gateway-api-crds) for quoted
  true/false patterns inside Helm valuesObject-style blocks and found zero
  besides the three lines it fixed; this bug report's own discovery swept
  the design spec and confirmed only line 164 is defective (line 176 is
  already correct).

EVIDENCE:
- File: docs/superpowers/specs/2026-08-05-cluster-lifecycle-and-ingress-storage-design.md
- Line 164 (current, defective):
  "Values mirror `fleet-infra` exactly: `localpv.basePath: /var/openebs/local`,
  `hostpathClass.name: local-path`, `hostpathClass.isDefaultClass: \"false\"`."
- Line 176 (same file, already correct, for reference/pattern-match):
  "...`ingressClass.enabled: true` + `isDefaultClass: true`, `gateway.enabled: true`..."
- Root cause (identical to AF-8ik8 and AF-wx9b): the localpv-provisioner
  Helm chart (4.5.1) gates its
  `storageclass.kubernetes.io/is-default-class` annotation on
  `{{- if .Values.hostpathClass.isDefaultClass }}`. Go/Helm template `if`
  treats ANY non-empty string -- including the string `"false"` -- as
  truthy. A quoted `"false"` in a Helm valuesObject is therefore never
  equivalent to the unquoted boolean `false`; it renders as if the value
  were `true`.
- Verified empirically in AF-wx9b's proof (rendered both forms against
  chart 4.5.1 with `helm template`): quoted `"false"` -> annotation
  `storageclass.kubernetes.io/is-default-class: "true"` present (WRONG,
  makes local-path the cluster default); unquoted `false` -> annotation
  absent (correct, matches this same document's own stated intent "Not
  the default class deliberately").

POSSIBLE CAUSES:
1. The design spec is the ORIGINAL source of the quoted-string value; the
   plan document (fixed in AF-wx9b) and the AF-8ik8 story's
   IMPLEMENTATION/AC1 block both appear to have been transcribed from this
   spec, propagating the same quoting choice downstream.
2. Spec author copied the value from the localpv-provisioner chart's own
   README (which misdocuments the default as the string `"false"`) instead
   of from the chart's `values.yaml:119` (which correctly types it as a
   boolean) -- same likely upstream cause identified in AF-wx9b.

CONFIG (if relevant):
Chart: localpv-provisioner 4.5.1, repo
https://openebs.github.io/dynamic-localpv-provisioner. Affected field:
hostpathClass.isDefaultClass (Helm values, boolean type per
values.yaml:119). Template gate:
{{- if .Values.hostpathClass.isDefaultClass }} -> emits
storageclass.kubernetes.io/is-default-class annotation on the StorageClass
when truthy.

This is a pure documentation edit: change one quoted string to an
unquoted boolean at one line in a markdown file. No live cluster access,
no credentials, no code or chart changes. Normal developer-claimable
story -- not gated, not human-execution-required.

Acceptance Criteria:
1. [Ubiquitous] Root cause documented in the fix commit: identical to
   AF-8ik8/AF-wx9b -- Go/Helm template `if` treats the non-empty string
   "false" as truthy, so a quoted boolean in a Helm-values-style code span
   is never equivalent to the unquoted boolean.
2. [Event] docs/superpowers/specs/2026-08-05-cluster-lifecycle-and-ingress-storage-design.md
   line 164 changes `` `hostpathClass.isDefaultClass: "false"` `` to
   `` `hostpathClass.isDefaultClass: false` `` (unquoted boolean), matching
   the already-fixed plan document
   (docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md:726)
   and the already-delivered
   infrastructure/openebs-localpv/argocd/appset.yaml.
3. [Unwanted] The fix shall not alter line 176 of the same file (Traefik's
   `isDefaultClass: true`, already correct/unquoted), any other line of
   this document, or any other file in the repo -- this is a one-line
   documentation-only correction scoped to line 164 only.
4. Verification: grep the design spec file for quoted `"false"`/`"true"`
   patterns after the fix and confirm zero remaining matches inside any
   Helm-values-style code span (backtick-delimited `key: "value"` text).
5. Verification: grep this repo's docs/ tree for the same quoted-boolean
   pattern (`isDefaultClass: "false"` / `isDefaultClass: "true"`) after the
   fix and confirm no occurrences remain anywhere, closing out the defect
   class first raised in AF-8ik8 and fixed piecemeal by AF-wx9b and this
   bug -- do not open a new story if this confirms zero remaining hits;
   note the result in the fix commit/PROOF instead.
6. `git diff --stat` confirms exactly 1 file changed with a minimal,
   single-line edit -- no other Task, section, or file in the repo is
   touched.

MANDATORY SKILLS TO REVIEW:
None identified (documentation edit to a plain-text markdown spec file; no
code or chart changes).

## Acceptance Criteria


## Design


## Notes


## nd_contract
status: accepted

### evidence
- PM closeout applied via pvg story accept on 2026-08-05.

### proof
- [x] Story closed after accepted label was applied.


## nd_contract
status: delivered

### evidence
- Transitioned via pvg story deliver on 2026-08-05.

### proof
- [ ] Developer evidence block must remain authoritative above this contract.


## History
- 2026-08-05T15:47:28Z status: open -> in_progress
- 2026-08-05T15:47:28Z auto-follows: linked to predecessor AF-cu83
- 2026-08-05T15:47:28Z claimed by dev-AF-9bc8
- 2026-08-05T15:56:11Z status: in_progress -> open
- 2026-08-05T16:10:23Z status: open -> in_progress
- 2026-08-05T16:10:23Z auto-follows: linked to predecessor AF-vwvq
- 2026-08-05T16:10:23Z claimed by dev-AF-9bc8
- 2026-08-05T16:12:49Z status: in_progress -> in_progress
- 2026-08-05T16:12:49Z auto-follows: linked to predecessor AF-pydv
- 2026-08-05T16:15:31Z status: in_progress -> closed

## Links
- Parent: [[AF-q1il]]
- Follows: [[AF-wx9b]], [[AF-cu83]], [[AF-vwvq]], [[AF-pydv]]
- Led to: [[AF-cbot]]

## Comments

### 2026-08-05T15:56:11Z ada
loop: reset orphaned in_progress to open (no developer worktree found; prior session presumed dead)

### 2026-08-05T16:13:19Z ada
PROOF:

Commit: 311520f (branch story/AF-9bc8, pushed to origin; parent 66240b7 = epic/AF-q1il tip, so the branch contains all merged epic work including AF-wx9b's plan-document fix)

Change (git diff, full):
```
-`hostpathClass.name: local-path`, `hostpathClass.isDefaultClass: "false"`.
+`hostpathClass.name: local-path`, `hostpathClass.isDefaultClass: false`.
```

Pre-check (mandatory already-landed sweep): `git log epic/AF-q1il --oneline -n 20` shows ca7482e (AF-wx9b, plan doc) and fca5308 (AF-8ik8, manifest) landed, but NO spec fix. Work was not already merged; implementation proceeded.

AC verification table:

| AC | Requirement | Command | Result |
|----|-------------|---------|--------|
| 1 | Root cause documented in fix commit | `git show 311520f` | PASS -- commit body documents Go/Helm `if` treating non-empty string "false" as truthy, so a quoted boolean in a Helm-values code span is never equivalent to unquoted `false` |
| 2 | Line 164 `"false"` -> unquoted `false` | `sed -n 164p <spec>` | PASS -- now reads ``​`hostpathClass.name: local-path`, `hostpathClass.isDefaultClass: false`.`` matching plan doc :726 and appset.yaml:43 |
| 3 | Line 176 and all other lines/files untouched | `sed -n 176p <spec>`; `git diff` | PASS -- line 176 still ``​`isDefaultClass: true`, `gateway.enabled: true` + `gateway.name:``; diff is exactly 1 insertion / 1 deletion on one line |
| 4 | Zero quoted true/false in spec Helm-values code spans | `grep -nE '`[^`]*:[[:space:]]*"(true\|false)"' <spec>` | PASS -- ZERO MATCHES. Broader `grep -nE '"(true\|false)"' <spec>` also ZERO MATCHES |
| 5 | Zero quoted isDefaultClass anywhere in docs/ | `grep -rnE 'isDefaultClass:[[:space:]]*"(true\|false)"' docs/` | PASS -- ZERO MATCHES. Defect class closed; no new story opened, per AC5 |
| 6 | Exactly 1 file, minimal single-line edit | `git diff --stat` | PASS -- `1 file changed, 1 insertion(+), 1 deletion(-)` |

AC5 repo-wide extension (beyond docs/): `grep -rnE 'isDefaultClass:[[:space:]]*"(true|false)"' . --exclude-dir=.git --exclude-dir=.vault --exclude-dir=.claude` returns exactly ONE textual match, infrastructure/openebs-localpv/README.md:18. Inspected and confirmed NOT a defect: it is prose deliberately quoting the anti-pattern to warn against it ("Go templates treat the non-empty string `"false"` as true -- so writing `isDefaultClass: "false"` does the exact opposite of what it reads like"). That same README line 11 carries the correct unquoted `isDefaultClass: false`. Left untouched, as AC3 forbids touching any other file. No remaining real defect anywhere in the repo.

pvg verify: `pvg verify <spec> --format text` -> `VERIFY: PASSED (0 files scanned, 0 issues)`, exit 0. Note: 0 files scanned because pvg verify does not scan markdown; recorded for completeness, not as substantive coverage.

Test suite / pass-fail counts: N/A -- this is a documentation-only, single-line markdown edit with zero code, chart, or manifest changes and therefore no executable test surface. The AC-specified verification is grep-based and is fully reported above (6/6 AC pass, 0 fail). No wiring site applies (no component introduced). Zero errors and zero warnings encountered during the work.

LEARNINGS:
- The `--format=text` form is rejected by `pvg verify`; it requires space-separated `--format text`. Worth knowing since the developer instructions show the `=` form.
- `pvg verify` reports "0 files scanned" for markdown-only changes. It is a genuine pass but proves nothing about content -- doc-only stories should lean on the AC grep evidence, and say plainly that the verify result is vacuous rather than presenting it as coverage.
- Grepping for a defect pattern repo-wide will hit documentation that quotes the anti-pattern on purpose. infrastructure/openebs-localpv/README.md:18 looks exactly like the bug but is the warning about it. Always read the surrounding lines before "fixing" a grep hit -- editing it would have destroyed the warning AF-8ik8 deliberately wrote and violated AC3.
- This closes a three-bug chain of one root cause (AF-8ik8 manifest -> AF-wx9b plan -> AF-9bc8 spec). The fixes ran downstream-to-upstream, which left the generating document defective longest. When a defect appears in a generated artifact, checking the source document in the same pass would have collapsed three stories into one.
- Tightly scoped [Unwanted] ACs did real work here: AC3 forbade touching anything else, which made the README hit an easy call instead of a judgment call.
