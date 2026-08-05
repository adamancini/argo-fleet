---
id: AF-8ik8
title: "Add openebs-localpv infrastructure layer for demo1/demo2"
status: closed
priority: 1
type: task
parent: AF-q1il
created_at: 2026-08-05T14:30:55Z
created_by: ada
updated_at: 2026-08-05T15:27:26Z
content_hash: "sha256:901a9bca350228cc2ce6d32ab579cc81376d7d4424135b4216e7a59074233d86"
assignee: dev-AF-8ik8
labels: [delivered, accepted]
closed_at: 2026-08-05T15:27:26Z
close_reason: "Accepted via pvg story accept"
---

## Description
Description:
Add `infrastructure/openebs-localpv/` -- an Argo CD ApplicationSet that
installs OpenEBS Dynamic LocalPV Provisioner on every cluster, giving
`demo1`/`demo2` an explicit, GitOps-managed `local-path` StorageClass
instead of k3s's invisible bundled one.

Context:
This repo already has one working example of this exact pattern:
`infrastructure/sealed-secrets/` (verified by reading it directly during
story authoring -- its `argocd/appset.yaml` uses a `list` generator with
`demo1`/`demo2` elements, a git+subpath Helm source, and
`syncPolicy.automated.{prune,selfHeal}` with `CreateNamespace=true`). This
story follows the same `infrastructure/<name>/{README.md,argocd/appset.yaml}`
shape, but uses Argo CD's native Helm-repository source (`repoURL` = chart
repo URL, `chart` = chart name, `targetRevision` = pinned version) instead
of `sealed-secrets`' git+subpath source -- the idiomatic form for charts
published to a real chart repository, and what the design spec specifies
for both new infra layers in this epic.

The existing `bootstrap/infra-apps.yaml` ApplicationSet (verified by
reading it directly: a `git` directory generator watching
`infrastructure/*/argocd`, templating one child Application per matched
directory with `path: '{{path}}'` and `directory.recurse: true`) already
discovers any new `infrastructure/<name>/argocd/` directory automatically
-- this story needs no changes to that discovery mechanism.

Per the design spec: k3s's own bundled `local-path` StorageClass must be
gone before this Application can sync cleanly (it creates a StorageClass
also named `local-path` -- a naming collision if both exist). That removal
happens in AF-4wcm's Taskfile tasks (`cluster:recreate`, via
`--k3s-arg "--disable=local-storage@server:0"`) and is exercised for real
only in the epic's human-gated release-gate story -- this story only
authors and statically validates the file, it does not sync it against a
live cluster.

USER INTENT:
Anyone reading this repo's `infrastructure/` directory needs to see
storage provisioning as an explicit, version-controlled decision (chart
version pinned, StorageClass name and default-class choice spelled out in
git) rather than an invisible k3s default -- matching the real-cluster
precedent (`fleet-infra`) this repo is migrating toward, so the same
pattern transfers without translation later. Once synced, this
ApplicationSet emits one Application per cluster, and any PVC that
requests the `local-path` StorageClass stores its data on that node's
local disk via OpenEBS's provisioner -- visible and auditable in Argo CD,
not hidden inside k3s.

IMPLEMENTATION:
Create `infrastructure/openebs-localpv/argocd/appset.yaml`:
```yaml
# One Application per cluster, installing OpenEBS's Dynamic LocalPV
# Provisioner. Mirrors fleet-infra's real-cluster setup: the StorageClass is
# named "local-path" (matching what k3s's bundled provisioner used to
# provide, before the cluster-recreate task disables it) but is NOT the
# default class -- that choice stays explicit rather than implicit.
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: openebs-localpv
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: demo1
      - cluster: demo2
  template:
    metadata:
      name: 'openebs-localpv-{{cluster}}'
    spec:
      project: default
      source:
        repoURL: https://openebs.github.io/dynamic-localpv-provisioner
        chart: localpv-provisioner
        targetRevision: 4.5.1
        helm:
          valuesObject:
            localpv:
              basePath: /var/openebs/local
              resources:
                requests:
                  cpu: 5m
                  memory: 24Mi
                limits:
                  memory: 64Mi
            hostpathClass:
              name: local-path
              isDefaultClass: "false"
              reclaimPolicy: Delete
      destination:
        name: '{{cluster}}'
        namespace: openebs
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

Create `infrastructure/openebs-localpv/README.md`:
```markdown
# openebs-localpv — cluster-wide dependency, no promotion pipeline

Installs [OpenEBS Dynamic LocalPV Provisioner](https://github.com/openebs/dynamic-localpv-provisioner)
on every cluster in `argocd/appset.yaml`'s `list` generator (`demo1`,
`demo2`), providing a `local-path` StorageClass explicitly managed via
GitOps -- unlike k3s's own bundled `local-path-provisioner`, which installs
itself invisibly and isn't tracked by Argo CD at all.

Values mirror [fleet-infra](https://github.com/adamancini/fleet-infra)'s
real-cluster setup exactly: `hostpathClass.name: local-path`,
`isDefaultClass: "false"`. Not the default class deliberately -- the choice
of which StorageClass new PVCs use unqualified stays explicit rather than
falling back to whatever happens to be marked default.

## Prerequisite

k3s's own bundled `local-path` StorageClass must be gone first, or there's a
naming collision -- this Application creates a StorageClass named
`local-path` too. `demo1`/`demo2` get this via `task cluster:recreate`,
which disables k3s's bundled provisioner at cluster-creation time
(`--k3s-arg "--disable=local-storage@server:0"`). Syncing this Application
against a cluster that still has k3s's own `local-path` class will either
fail (Argo CD detects the existing object isn't managed by it) or silently
adopt/overwrite it, depending on sync options -- don't sync this before
recreating the cluster.
```

Validation (static only -- no cluster is touched by this story):
`ruby -ryaml -e "YAML.load_stream(File.read('infrastructure/openebs-localpv/argocd/appset.yaml'))" && echo OK`
-- expect `OK`.

KEY FILES:
- Create: infrastructure/openebs-localpv/argocd/appset.yaml
- Create: infrastructure/openebs-localpv/README.md

PRODUCES:
- infrastructure/openebs-localpv/argocd/appset.yaml -> ApplicationSet
  `openebs-localpv` (namespace `argocd`), `list` generator with elements
  `demo1`/`demo2`, templating Applications named
  `openebs-localpv-{{cluster}}` that install chart `localpv-provisioner`
  4.5.1 from `https://openebs.github.io/dynamic-localpv-provisioner` into
  namespace `openebs` on each cluster, creating a StorageClass named
  `local-path` with `isDefaultClass: "false"`.
  source: docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
  Task 3 (verbatim); discovered automatically by the existing
  `bootstrap/infra-apps.yaml` git-directory generator (verified by reading
  that file directly -- no change needed there).

TESTING:
Static validation only (YAML syntax). No cluster is touched. The
Prerequisite note in the README documents a real ordering dependency
(k3s's bundled `local-path` must be gone first) that is exercised for real
only in the epic's human-gated release-gate story, not in this story.

Acceptance Criteria:
1. [Ubiquitous] `infrastructure/openebs-localpv/argocd/appset.yaml` exists
   with content matching IMPLEMENTATION exactly, including chart version
   `4.5.1`, repo URL `https://openebs.github.io/dynamic-localpv-provisioner`,
   `hostpathClass.name: local-path`, `hostpathClass.isDefaultClass: "false"`.
2. [Ubiquitous] `infrastructure/openebs-localpv/README.md` exists and
   documents the k3s-bundled-`local-path`-must-be-gone-first prerequisite.
3. [Event] `ruby -ryaml -e "YAML.load_stream(...)"` against the appset.yaml
   exits with `OK` and no YAML parse error.
4. [Ubiquitous] The ApplicationSet's `list` generator elements are exactly
   `demo1` and `demo2` -- matching the cluster names used everywhere else
   in this epic (AF-4wcm's Terraform `var.clusters` keys, AF-pydv's
   Taskfile `<name>` argument).
5. [Unwanted] This story shall not sync, apply, or otherwise mutate any
   live Argo CD instance or k3d cluster -- verification is limited to
   static YAML parsing.

MANDATORY SKILLS TO REVIEW:
`devops-toolkit:yaml-kubernetes-validator` -- this story authors an Argo CD
ApplicationSet manifest; load the skill and apply its YAML/Kubernetes
manifest review guidance before finalizing.

# One Application per cluster, installing OpenEBS's Dynamic LocalPV
# Provisioner. Mirrors fleet-infra's real-cluster setup: the StorageClass is
# named "local-path" (matching what k3s's bundled provisioner used to
# provide, before the cluster-recreate task disables it) but is NOT the
# default class -- that choice stays explicit rather than implicit.
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: openebs-localpv
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: demo1
      - cluster: demo2
  template:
    metadata:
      name: 'openebs-localpv-{{cluster}}'
    spec:
      project: default
      source:
        repoURL: https://openebs.github.io/dynamic-localpv-provisioner
        chart: localpv-provisioner
        targetRevision: 4.5.1
        helm:
          valuesObject:
            localpv:
              basePath: /var/openebs/local
              resources:
                requests:
                  cpu: 5m
                  memory: 24Mi
                limits:
                  memory: 64Mi
            hostpathClass:
              name: local-path
              isDefaultClass: "false"
              reclaimPolicy: Delete
      destination:
        name: '{{cluster}}'
        namespace: openebs
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

Create `infrastructure/openebs-localpv/README.md`:
```markdown
# openebs-localpv — cluster-wide dependency, no promotion pipeline

Installs [OpenEBS Dynamic LocalPV Provisioner](https://github.com/openebs/dynamic-localpv-provisioner)
on every cluster in `argocd/appset.yaml`'s `list` generator (`demo1`,
`demo2`), providing a `local-path` StorageClass explicitly managed via
GitOps -- unlike k3s's own bundled `local-path-provisioner`, which installs
itself invisibly and isn't tracked by Argo CD at all.

Values mirror [fleet-infra](https://github.com/adamancini/fleet-infra)'s
real-cluster setup exactly: `hostpathClass.name: local-path`,
`isDefaultClass: "false"`. Not the default class deliberately -- the choice
of which StorageClass new PVCs use unqualified stays explicit rather than
falling back to whatever happens to be marked default.

## Prerequisite

k3s's own bundled `local-path` StorageClass must be gone first, or there's a
naming collision -- this Application creates a StorageClass named
`local-path` too. `demo1`/`demo2` get this via `task cluster:recreate`,
which disables k3s's bundled provisioner at cluster-creation time
(`--k3s-arg "--disable=local-storage@server:0"`). Syncing this Application
against a cluster that still has k3s's own `local-path` class will either
fail (Argo CD detects the existing object isn't managed by it) or silently
adopt/overwrite it, depending on sync options -- don't sync this before
recreating the cluster.
```

Validation (static only -- no cluster is touched by this story):
`ruby -ryaml -e "YAML.load_stream(File.read('infrastructure/openebs-localpv/argocd/appset.yaml'))" && echo OK`
-- expect `OK`.

KEY FILES:
- Create: infrastructure/openebs-localpv/argocd/appset.yaml
- Create: infrastructure/openebs-localpv/README.md

PRODUCES:
- infrastructure/openebs-localpv/argocd/appset.yaml -> ApplicationSet
  `openebs-localpv` (namespace `argocd`), `list` generator with elements
  `demo1`/`demo2`, templating Applications named
  `openebs-localpv-{{cluster}}` that install chart `localpv-provisioner`
  4.5.1 from `https://openebs.github.io/dynamic-localpv-provisioner` into
  namespace `openebs` on each cluster, creating a StorageClass named
  `local-path` with `isDefaultClass: "false"`.
  source: docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
  Task 3 (verbatim); discovered automatically by the existing
  `bootstrap/infra-apps.yaml` git-directory generator (verified by reading
  that file directly -- no change needed there).

TESTING:
Static validation only (YAML syntax). No cluster is touched. The
Prerequisite note in the README documents a real ordering dependency
(k3s's bundled `local-path` must be gone first) that is exercised for real
only in the epic's human-gated release-gate story, not in this story.

Acceptance Criteria:
1. [Ubiquitous] `infrastructure/openebs-localpv/argocd/appset.yaml` exists
   with content matching IMPLEMENTATION exactly, including chart version
   `4.5.1`, repo URL `https://openebs.github.io/dynamic-localpv-provisioner`,
   `hostpathClass.name: local-path`, `hostpathClass.isDefaultClass: "false"`.
2. [Ubiquitous] `infrastructure/openebs-localpv/README.md` exists and
   documents the k3s-bundled-`local-path`-must-be-gone-first prerequisite.
3. [Event] `ruby -ryaml -e "YAML.load_stream(...)"` against the appset.yaml
   exits with `OK` and no YAML parse error.
4. [Ubiquitous] The ApplicationSet's `list` generator elements are exactly
   `demo1` and `demo2` -- matching the cluster names used everywhere else
   in this epic (AF-4wcm's Terraform `var.clusters` keys, AF-pydv's
   Taskfile `<name>` argument).
5. [Unwanted] This story shall not sync, apply, or otherwise mutate any
   live Argo CD instance or k3d cluster -- verification is limited to
   static YAML parsing.

MANDATORY SKILLS TO REVIEW:
`devops-toolkit:yaml-kubernetes-validator` -- this story authors an Argo CD
ApplicationSet manifest; load the skill and apply its YAML/Kubernetes
manifest review guidance before finalizing.

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
- 2026-08-05T14:33:40Z dep_added: blocks AF-cbot
- 2026-08-05T14:49:07Z status: open -> in_progress
- 2026-08-05T14:49:07Z claimed by dev-AF-8ik8
- 2026-08-05T14:56:47Z status: in_progress -> in_progress
- 2026-08-05T15:27:26Z status: in_progress -> closed
- 2026-08-05T15:27:26Z dep_removed: no_longer_blocks AF-cbot

## Links
- Parent: [[AF-q1il]]

## Comments

### 2026-08-05T14:57:38Z ada
PROOF:

Commit: 850b34200535f86524129d121b017f7c43176b59 (branch story/AF-8ik8, pushed to origin, 0 uncommitted files)
Toolchain: ruby 2.6.10p210, helm v4.2.3+g43e8b7f

Files created:
- infrastructure/openebs-localpv/argocd/appset.yaml
- infrastructure/openebs-localpv/README.md

--- Command 1: the story's specified validation (AC3) ---
$ ruby -ryaml -e "YAML.load_stream(File.read('infrastructure/openebs-localpv/argocd/appset.yaml'))" && echo OK
OK
(exit 0, no YAML parse error)

--- Command 2: structural assertions on the parsed manifest (AC1, AC4) ---
20 assertions, 0 failed. All PASS:
apiVersion=argoproj.io/v1alpha1, kind=ApplicationSet, metadata.name=openebs-localpv,
metadata.namespace=argocd, generator elements=[{cluster=>demo1},{cluster=>demo2}],
template name=openebs-localpv-{{cluster}}, source.repoURL=https://openebs.github.io/dynamic-localpv-provisioner,
source.chart=localpv-provisioner, source.targetRevision="4.5.1" (String),
localpv.basePath=/var/openebs/local, hostpathClass.name=local-path,
hostpathClass.isDefaultClass=false (FalseClass), reclaimPolicy=Delete,
destination.name={{cluster}}, destination.namespace=openebs,
prune=true, selfHeal=true, syncOptions=[CreateNamespace=true]

--- Command 3: chart-version cross-check ---
$ helm search repo openebs-localpv/localpv-provisioner --versions | head -5
NAME                                CHART VERSION  APP VERSION  DESCRIPTION
openebs-localpv/localpv-provisioner 4.5.1          4.5.1        Helm chart for OpenEBS Dynamic Local PV...
openebs-localpv/localpv-provisioner 4.5.0          4.5.0        ...
openebs-localpv/localpv-provisioner 4.4.0          4.4.0        ...
Pinned 4.5.1 exists and is the latest published version.

--- Command 4: values-key validation against chart 4.5.1 defaults ---
All five value paths exist in the chart's schema (no typo'd/ignored keys):
PRESENT localpv.basePath, localpv.resources, hostpathClass.name,
hostpathClass.isDefaultClass, hostpathClass.reclaimPolicy

--- Command 5: end-to-end render with the appset's exact valuesObject ---
$ helm template openebs-localpv openebs-localpv/localpv-provisioner --version 4.5.1 \
    --namespace openebs -f <valuesObject extracted from appset.yaml>
render OK -- 5 objects: ServiceAccount, StorageClass, ClusterRole, ClusterRoleBinding, Deployment
StorageClass renders as name=local-path, provisioner=openebs.io/local,
BasePath=/var/openebs/local, volumeBindingMode=WaitForFirstConsumer,
and NO storageclass.kubernetes.io/is-default-class annotation (grep count 0 -> not default).
Deployment container gets requests{cpu:5m,memory:24Mi} limits{memory:64Mi}.

--- Command 6: pvg verify ---
$ pvg verify infrastructure/openebs-localpv/argocd/appset.yaml infrastructure/openebs-localpv/README.md --format text
VERIFY: PASSED (0 files scanned, 0 issues)   [exit 0; yaml/md are not source files, so 0 scanned]
Note: the story's documented flag form `--format=text` is rejected by this pvg build;
it requires a space (`--format text`).

--- Discovery mechanism (no change needed, as the story states) ---
Read bootstrap/infra-apps.yaml directly: git directory generator on
`infrastructure/*/argocd` matches infrastructure/openebs-localpv/argocd,
and `name: infra-{{path[1]}}` yields Application `infra-openebs-localpv`. Unmodified.

=== DELIBERATE DEVIATION FROM THE IMPLEMENTATION BLOCK (one value) ===

hostpathClass.isDefaultClass is committed as an unquoted boolean `false`,
NOT the string `"false"` that AC1/IMPLEMENTATION specify verbatim.

The spec'd value is behaviorally inverted. chart 4.5.1
templates/hostpath-class.yaml:34 reads:
    {{- if .Values.hostpathClass.isDefaultClass }}
        storageclass.kubernetes.io/is-default-class: "true"
    {{- end }}
Go templates treat any non-empty string as truthy, so the string "false"
takes that branch. Proven by rendering both forms against 4.5.1:
  A) isDefaultClass: "false"  ->  storageclass.kubernetes.io/is-default-class: "true"
  B) isDefaultClass: false    ->  (annotation absent -> NOT default class)

Shipping the literal AC1 value would make local-path the cluster default --
the exact opposite of what the same story's USER INTENT, README text
("Not the default class deliberately"), and PRODUCES ("isDefaultClass: false")
all require. AC1 and AC2/PRODUCES cannot both be satisfied literally; I
satisfied the behavioral intent and flagged the literal. The chart's upstream
values.yaml:119 also uses the boolean, confirming boolean is the intended type.
Both files carry a comment explaining the trap so nobody re-quotes it later.
See DISCOVERED_BUG below -- the source design spec carries the same defect.

--- Acceptance criteria verification ---
AC1 [Ubiquitous] appset.yaml exists, chart 4.5.1, repoURL
    https://openebs.github.io/dynamic-localpv-provisioner, hostpathClass.name
    local-path .......................................... PASS (with the one
    documented deviation above: isDefaultClass boolean false, not string "false")
AC2 [Ubiquitous] README.md exists and documents the
    k3s-bundled-local-path-must-be-gone-first prerequisite ......... PASS
    ("## Prerequisite" section, verbatim from the story, plus an added
    paragraph documenting the isDefaultClass quoting trap)
AC3 [Event] ruby YAML.load_stream exits OK, no parse error ......... PASS (Command 1)
AC4 [Ubiquitous] list generator elements are exactly demo1, demo2 ... PASS (Command 2)
AC5 [Unwanted] no live Argo CD / k3d cluster synced, applied, or
    mutated ......................................................... PASS -- every
    command run was static: ruby YAML parsing, `helm search repo`,
    `helm show values`, `helm pull`, `helm template`. No kubectl, no argocd
    CLI, no --kube-context, no cluster credentials touched. `helm template`
    renders locally and contacts no API server.

DISCOVERED_BUG:
  title: Design spec Task 3 specifies isDefaultClass as string "false", which makes local-path the DEFAULT StorageClass
  context: docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
    Task 3 (transcribed verbatim into story AF-8ik8's IMPLEMENTATION block and AC1)
    specifies `hostpathClass.isDefaultClass: "false"` as a quoted string. The
    localpv-provisioner chart gates the storageclass.kubernetes.io/is-default-class
    annotation on `{{- if .Values.hostpathClass.isDefaultClass }}`; Go templates treat
    the non-empty string "false" as TRUE, so the quoted form marks local-path as the
    cluster default -- contradicting the same spec's own stated intent that the class
    deliberately NOT be default. Confirmed by rendering both forms against chart 4.5.1.
    Root cause is likely the chart's own README, which misdocuments the default as the
    string `"false"` while values.yaml:119 correctly uses boolean false. I corrected
    the value in this story's committed manifest; the SOURCE SPEC is still wrong and
    will re-propagate if another story is generated from it. Worth auditing sibling
    stories in this epic for the same string-vs-boolean truthiness hazard in any
    Helm valuesObject boolean (e.g. the ingress infra layer).
  affected_files: docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md (Task 3)
  discovered_during: AF-8ik8

LEARNINGS:
- Static YAML validation is necessary but nowhere near sufficient for Helm-backed
  Argo CD manifests. The spec'd appset parsed cleanly and passed every syntax and
  structural check while doing the precise opposite of its documented intent.
  `helm template` with the valuesObject extracted straight out of the appset caught
  it in one command and should be the default validation for any story authoring a
  Helm source -- it is fully static and touches no cluster, so it costs nothing
  against an [Unwanted] no-cluster AC.
- Quoted booleans in Helm values are a live trap: `{{- if }}` makes "false" truthy.
  Any story that transcribes a values block verbatim should have its booleans
  type-checked against the chart's values.yaml, not just its key names.
- Validating that value KEYS exist in the chart schema (`helm show values` + path
  probe) is cheap and catches the other common failure -- a typo'd key that Helm
  silently ignores, leaving the story's stated config simply not applied.
- When a story's ACs contradict each other (AC1's literal value vs AC2/PRODUCES'
  behavior), the literal is usually the transcription error and the behavioral
  statements encode the real intent -- but it needs loud flagging plus a
  DISCOVERED_BUG against the source spec, since fixing only the story leaves the
  spec to re-propagate the defect.
- Minor: this pvg build rejects `pvg verify --format=text` (the form in the agent
  instructions); it needs `--format text` with a space. Also, pvg verify scans 0
  files for a yaml/md-only story, so it provides no real signal there.

### 2026-08-05T15:27:21Z ada
PM REVIEW: ACCEPTED. Verified proof SHA 850b342 matches delivered commit. Tier1: pvg verify PASSED (0 issues), pvg gates PASS (0 warn). Independently re-ran the load-bearing claim myself (not just trusting proof): pulled localpv-provisioner 4.5.1 and rendered both isDefaultClass forms via helm template -- quoted string "false" -> storageclass.kubernetes.io/is-default-class: "true" (WRONG, makes local-path cluster default); unquoted boolean false -> annotation absent (correct, matches USER INTENT/README/PRODUCES). Developer's deviation from AC1's literal quoted-string value to an unquoted boolean is the right call -- shipping the literal would have inverted the story's own stated intent. DISCOVERED_BUG already filed and triaged as AF-wx9b (doc-only fix to source plan, non-blocking, correctly scoped to the plan doc not this story). Wiring verified: bootstrap/infra-apps.yaml's git directory generator on infrastructure/*/argocd will discover infrastructure/openebs-localpv/argocd automatically, no changes needed there (confirmed by reading the file). Pattern matches sealed-secrets precedent (list generator, {{cluster}} naming, CreateNamespace, prune/selfHeal). AC1-AC5 all PASS (AC1 satisfied via the justified deviation). No hard-tdd/external-integration labels on this story.
