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
updated_at: 2026-08-05T15:36:16Z
content_hash: "sha256:0a8c2d03329f587ea673e1a4ffbb704e40373cf4e4343a1bc791e1b1c2b8ef7f"
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
