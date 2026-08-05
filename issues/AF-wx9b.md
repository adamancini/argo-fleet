---
id: AF-wx9b
title: "Bug: Design spec Task 3 quotes hostpathClass.isDefaultClass as string \"false\", making local-path the default StorageClass"
status: in_progress
priority: 0
type: bug
labels: [documentation, discovered-by-dev, delivered]
parent: AF-q1il
created_at: 2026-08-05T15:12:18Z
created_by: ada
updated_at: 2026-08-05T15:37:14Z
content_hash: "sha256:4b587b21dbbf01ac6566c16b9a21591ab365fa450e4fbe2a87c6c6c7a7a8f189"
assignee: dev-AF-wx9b
follows: [AF-8ik8, AF-qujb]
---

## Description
Description:
docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
Task 3 (the openebs-localpv infrastructure layer) specifies
`hostpathClass.isDefaultClass: "false"` as a quoted YAML string in three
places (lines 16, 726, 752). The localpv-provisioner Helm chart gates its
`storageclass.kubernetes.io/is-default-class` annotation on
`{{- if .Values.hostpathClass.isDefaultClass }}`, and Go template `if`
treats any non-empty string -- including the string "false" -- as truthy.
Shipping the spec's literal quoted value therefore marks `local-path` as
the cluster's default StorageClass, directly contradicting the same
document's own stated intent ("Not the default class deliberately", line
752) and the sibling prose at line 16.

DISCOVERED DURING:
Story AF-8ik8 (Add openebs-localpv infrastructure layer for demo1/demo2,
epic AF-q1il). The developer transcribed Task 3 verbatim into AF-8ik8's
IMPLEMENTATION block and AC1, caught the truthiness trap while running
`helm template` against the extracted valuesObject, and corrected the
committed manifest (infrastructure/openebs-localpv/argocd/appset.yaml)
to the unquoted boolean isDefaultClass: false, with an inline comment
explaining the trap. AF-8ik8 itself is NOT affected by this bug -- it
already ships the correct value and is delivered for PM review. This bug
tracks only the SOURCE SPEC DOCUMENT, which still carries the defective
quoted form and would re-propagate it if any future story were regenerated
from Task 3. This is a documentation/spec-only bug and is NOT a blocker on
AF-8ik8 or any other in-flight story in this epic.

SYMPTOMS:
- The plan document instructs (and a naive transcription would produce) a
  local-path StorageClass marked as the cluster default via the
  storageclass.kubernetes.io/is-default-class: "true" annotation.
- This is the opposite of the document's own two stated intents: line 16
  ("Not the default class") and line 752 ("Not the default class
  deliberately -- the choice of which StorageClass new PVCs use unqualified
  stays explicit rather than falling back to whatever happens to be marked
  default").
- Root cause is a YAML type error: isDefaultClass: "false" (quoted
  string) instead of isDefaultClass: false (boolean).

EVIDENCE:
- docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md:16
  -- "hostpathClass.isDefaultClass: \"false\" for OpenEBS ... Not the
  default class."
- docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md:726
  (Task 3's YAML block) -- isDefaultClass: "false" under hostpathClass:.
- docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md:752
  (Task 3's README prose) -- "isDefaultClass: \"false\". Not the default
  class deliberately".
- Confirmed (by the AF-8ik8 developer, and re-confirmed directly for this
  bug report by grepping the current plan document) by rendering the
  localpv-provisioner chart 4.5.1 with both forms: the quoted string form
  renders the is-default-class annotation as present/true; the unquoted
  boolean false form renders the annotation absent (not default). Chart
  template gate: {{- if .Values.hostpathClass.isDefaultClass }}.
- Likely upstream source of the error: the localpv-provisioner chart's own
  README documents the default as the string "false", while the chart's
  actual values.yaml:119 correctly declares the boolean false -- the spec
  author most likely copied the README's (wrong) documented form rather
  than the schema's actual type.
- Verified isolated to this one field: grepped the entire plan document
  for quoted "true"/"false" patterns. The only other quoted match (line
  554, a Terraform labels = { fleet = "true" } example) is an unrelated
  Terraform string label, not a Helm values boolean. The two sibling
  infrastructure-layer stories in this epic (AF-vwvq traefik-gateway,
  AF-qujb gateway-api-crds) were checked directly against the current plan
  document and their own story bodies -- both use unquoted booleans
  throughout (enabled: true, isDefaultClass: true, etc.) with zero quoted
  true/false strings. This defect does not recur elsewhere in the plan.

POSSIBLE CAUSES:
1. Spec author copied the value from the localpv-provisioner chart's
   README (which misdocuments the default as the string "false") instead
   of from values.yaml:119 (which correctly types it as a boolean).
2. Spec author manually quoted the value out of habit/caution when
   transcribing YAML into prose, not realizing Helm/Go-template if treats
   any non-empty string as truthy.

CONFIG (if relevant):
Chart: localpv-provisioner 4.5.1, repo
https://openebs.github.io/dynamic-localpv-provisioner. Affected field:
hostpathClass.isDefaultClass (Helm values, boolean type per
values.yaml:119). Template gate:
{{- if .Values.hostpathClass.isDefaultClass }} -> emits
storageclass.kubernetes.io/is-default-class annotation on the StorageClass
when truthy.

Acceptance Criteria:
1. [Ubiquitous] Root cause documented in the fix commit: Go/Helm template
   if treats the non-empty string "false" as truthy, so a quoted boolean
   in Helm valuesObject YAML is never equivalent to the unquoted boolean.
2. [Event] docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
   line 726's Task 3 YAML block changes isDefaultClass: "false" to the
   unquoted boolean isDefaultClass: false.
3. [Event] The same document's prose at line 16 and line 752 is updated to
   reference the unquoted boolean form (isDefaultClass: false), removing
   the quoted "false" from both.
4. [Unwanted] The fix shall not alter any other Task 3 field, any other
   Task's content, or any already-delivered story's committed manifest --
   this is a documentation-only correction scoped to the three cited
   lines.
5. Verification: render the corrected YAML block's hostpathClass values
   through helm template against localpv-provisioner 4.5.1 and confirm the
   storageclass.kubernetes.io/is-default-class annotation is absent from
   the rendered StorageClass (i.e., local-path is NOT the cluster
   default).
6. Verification: grep the full plan document for quoted "true"/"false"
   patterns after the fix and confirm zero remaining matches inside any
   Helm valuesObject block.

MANDATORY SKILLS TO REVIEW:
None identified (documentation edit to a plain-text plan file; no code or
chart changes).

## Acceptance Criteria


## Design


## Notes


## nd_contract
status: delivered

### evidence
- Transitioned via pvg story deliver on 2026-08-05.

### proof
- [ ] Developer evidence block must remain authoritative above this contract.


## History
- 2026-08-05T15:30:23Z status: open -> in_progress
- 2026-08-05T15:30:23Z auto-follows: linked to predecessor AF-8ik8
- 2026-08-05T15:30:23Z claimed by dev-AF-wx9b
- 2026-08-05T15:36:16Z status: in_progress -> in_progress
- 2026-08-05T15:36:16Z auto-follows: linked to predecessor AF-qujb

## Links
- Parent: [[AF-q1il]]
- Follows: [[AF-8ik8]], [[AF-qujb]]

## Comments

### 2026-08-05T15:37:14Z ada
PROOF:

Commit: ca7482e (branch story/AF-wx9b, pushed to origin)
Merge base note: the target document lives ONLY on origin/main -- it was
never on epic/AF-q1il. Merged origin/main into story/AF-wx9b (d9eb114,
clean, no conflicts) to obtain the file; the fix commit ca7482e sits on
top. See "Deviation / note for PM" below.

Commands run (all synchronous, in the story worktree):

1. Locate + confirm defect (pre-fix, on origin/main):
   $ git grep -n '"false"' origin/main -- docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
   -> hits at lines 16, 726, 752 exactly as the bug report states.

2. Extract the Task 3 valuesObject VERBATIM from the fixed document
   (python block-extractor keyed on `chart: localpv-provisioner` ->
   `valuesObject:`, dedented) so the rendering below is proven to use the
   document's own literal content, not hand-retyped values:
     localpv: {basePath: /var/openebs/local, resources: {...}}
     hostpathClass: {name: local-path, isDefaultClass: false, reclaimPolicy: Delete}

3. AC5 render (helm v4.2.3, chart localpv-provisioner 4.5.1 from
   https://openebs.github.io/dynamic-localpv-provisioner):
   $ helm template openebs-localpv openebs-localpv/localpv-provisioner \
       --version 4.5.1 --namespace openebs -f task3-values.yaml
   Rendered StorageClass/local-path annotations:
     openebs.io/cas-type: local
     cas.openebs.io/config: |...
   -> storageclass.kubernetes.io/is-default-class occurrences: 0 (ABSENT)
   -> local-path is NOT the cluster default. AC5 SATISFIED.

4. Root-cause control (same command, only isDefaultClass re-quoted):
   isDefaultClass: false    -> is-default-class annotation ABSENT
   isDefaultClass: "false"  -> storageclass.kubernetes.io/is-default-class: "true"
   Confirms the Go-template truthiness trap empirically, both directions.

5. AC6 grep, full plan document post-fix:
   $ grep -n '"true"\|"false"\|'\''true'\''\|'\''false'\''' docs/.../2026-08-05-cluster-lifecycle-and-ingress-storage.md
   -> exactly 1 match: line 554 `#   # labels = { fleet = "true" }`
      (a commented-out Terraform string label, NOT a Helm value).
   Plus a structural scan that walks every `valuesObject:` block by
   indentation and regex-matches quoted booleans inside them:
   -> valuesObject blocks scanned: 2; quoted true/false inside them: 0.
   AC6 SATISFIED.

6. AC4 scope check:
   $ git diff --stat -> 1 file changed, 3 insertions(+), 3 deletions(-)
   $ git diff -U0    -> @@ -16 +16 @@ / @@ -726 +726 @@ / @@ -752 +752 @@
   Three 1:1 line substitutions; every line number in the document is
   unchanged. No other Task, no other Task 3 field, and no committed
   manifest touched. Confirmed infrastructure/openebs-localpv/ is
   untouched by this commit. AC4 SATISFIED.

7. $ pvg verify docs/.../2026-08-05-cluster-lifecycle-and-ingress-storage.md --format text
   VERIFY: PASSED (0 files scanned, 0 issues)   exit=0
   (note: `--format=text` with an `=` is rejected by this pvg build;
   the space form works.)

Test counts: this is a documentation-only story with no test suite.
Verification is the 2 helm renders above (2/2 produced the expected
annotation state: 1 absent as required, 1 present as the control) and the
2 grep/scan assertions (2/2 passed). 0 failures, 0 warnings, 0 skipped.
Coverage: N/A -- no executable code changed; all 3 defective lines cited
in the bug report are covered by the diff (3/3).

AC verification table:

| AC | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| 1  | [Ubiquitous] Root cause documented in the fix commit | PASS | ca7482e commit body has a ROOT CAUSE section naming the `{{- if .Values.hostpathClass.isDefaultClass }}` gate, Go-template truthiness of any non-empty string, the quoted-vs-unquoted non-equivalence, and the VERIFIED render results both ways |
| 2  | [Event] Line 726 Task 3 YAML: `"false"` -> `false` | PASS | diff hunk `@@ -726 +726 @@`: `-  isDefaultClass: "false"` / `+  isDefaultClass: false` |
| 3  | [Event] Prose at lines 16 and 752 updated to the unquoted form | PASS | diff hunks `@@ -16 +16 @@` and `@@ -752 +752 @@`; zero quoted `"false"` remains anywhere in the document |
| 4  | [Unwanted] No other field/Task/manifest altered | PASS | `git diff --stat` = 1 file, 3+/3-; line numbers preserved 1:1; step 6 above |
| 5  | Verification: helm template -> is-default-class ABSENT | PASS | step 3: 0 occurrences of the annotation in the rendered StorageClass |
| 6  | Verification: grep quoted bools -> zero in any valuesObject | PASS | step 5: 0 inside both valuesObject blocks; sole remaining match is the unrelated Terraform label at line 554 |

Deviation / note for PM (please confirm this is acceptable):

(a) Branch base. story/AF-wx9b was cut from epic/AF-q1il, but the target
    document does not exist on that epic -- it was added to main in 9cd3f16
    and main has 3 commits the epic lacks. I merged origin/main into the
    story branch (clean) rather than cherry-picking, so the epic converges
    with main on integration instead of carrying a duplicate commit. That
    merge is what brings docs/.../*.md, the design spec, and main's
    .vault/.gitignore + .vault/.nd-shared.yaml into the branch -- those are
    inherited from main, not content I authored or staged.

(b) Wording choice on line 752. AC3 requires only removing the quotes. I
    made line 752 byte-identical to the corresponding sentence in the
    already-accepted infrastructure/openebs-localpv/README.md (i.e. plain
    `isDefaultClass: false`, no added parenthetical), because that block is
    the fenced literal source for that README -- so a future regeneration
    from Task 3 now reproduces the accepted file rather than drifting from
    it. On line 16 (Global Constraints, a single unwrapped bullet) I did add
    "(unquoted boolean)", since that is the first place a regenerating author
    reads and it costs no reflow. Adding the parenthetical to 752 forced an
    ugly mid-sentence rewrap, so I reverted it there.

(c) NOT fixed, deliberately, per AC4's scope constraint: the sibling design
    spec carries the same defect. See DISCOVERED_BUG below.

DISCOVERED_BUG:
  title: Design spec line 164 carries the same quoted isDefaultClass: "false" defect as the plan document
  context: While verifying AF-wx9b (which corrects the quoted-boolean defect
    in the PLAN document), I found the same defect in the sibling DESIGN SPEC:
    docs/superpowers/specs/2026-08-05-cluster-lifecycle-and-ingress-storage-design.md:164
    reads "`hostpathClass.name: local-path`, `hostpathClass.isDefaultClass:
    \"false\"`." -- identical root cause, identical consequence. The design
    spec is upstream of the plan document, so leaving it defective means a
    regeneration of the PLAN from the SPEC would re-introduce the exact bug
    AF-wx9b just fixed, defeating the point of this fix. I did NOT fix it
    here because AF-wx9b's AC4 is an explicit [Unwanted] constraint scoping
    the change to three cited lines of the plan document only; silently
    widening scope would violate the AC I was asked to satisfy. Needs its own
    triaged story. Note line 176 of the same file is correct (`isDefaultClass:
    true` unquoted, for Traefik's ingressClass) -- line 164 is the only hit.
  affected_files: docs/superpowers/specs/2026-08-05-cluster-lifecycle-and-ingress-storage-design.md (line 164)
  discovered_during: AF-wx9b

LEARNINGS:
- The defect class generalizes well beyond this field: in ANY Helm
  valuesObject, a quoted boolean is never equivalent to an unquoted one,
  because Go template `if` tests truthiness and every non-empty string --
  "false" included -- is truthy. Worth a standing review rule for
  Argo CD Application `helm.valuesObject` blocks, where there is no
  values.yaml schema nearby to catch the type error.
- Trust the chart's values.yaml, never its README. The upstream
  localpv-provisioner README documents this default as the string "false"
  while values.yaml:119 correctly declares the boolean -- that upstream
  doc bug is the most plausible origin of the defect, and it will keep
  seeding the same mistake in anything copied from that README.
- Verify a doc fix by extracting the block PROGRAMMATICALLY from the fixed
  document and rendering that, rather than retyping the values into a
  scratch file. Retyping proves only that a correct value renders
  correctly; extraction proves the DOCUMENT is now correct, which is the
  actual claim. Rendering the defective form as a control alongside it is
  what turns "the annotation is absent" into evidence of a fixed cause.
- Gotcha for this repo: not every story's target file lives on its epic
  branch. The plan/spec docs were committed straight to main while
  epic/AF-q1il carries the implementation, so a doc-fix story cut from the
  epic starts without the file it is supposed to edit. Check `git log --all
  -- <path>` and `git branch --contains` before assuming the file is missing
  or already fixed.
- Gotcha: `pvg verify --format=text` (with `=`) is rejected by this build;
  use `--format text`. Also note pvg verify reports "0 files scanned" for
  markdown -- it does not actually inspect prose, so it is a scope/stub
  check here, not real verification of this story's content.
