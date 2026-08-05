---
id: AF-qujb
title: "Add gateway-api-crds infrastructure layer for demo1/demo2"
status: closed
priority: 1
type: task
parent: AF-q1il
created_at: 2026-08-05T14:32:18Z
created_by: ada
updated_at: 2026-08-05T15:33:51Z
content_hash: "sha256:64e10629bb2b7aaa9b1f47c8fc6947df593ef60e81f970f196f8ac772418ed09"
assignee: dev-AF-qujb
labels: [accepted]
closed_at: 2026-08-05T15:33:50Z
close_reason: "Byte-exact match to IMPLEMENTATION spec; sync-wave quoted as string (guards -1 int/string footgun); YAML validates OK; discovery wiring confirmed via bootstrap/infra-apps.yaml; README documents ordering/selfHeal. AC1-5 verified."
---

## Description
Description:
Add `infrastructure/gateway-api-crds/` -- an Argo CD ApplicationSet that
installs the Gateway API CRDs (`Gateway`, `HTTPRoute`, `GatewayClass`,
etc.) at the experimental channel, version `v1.5.1`, on every cluster.
Traefik's own Helm chart (AF-vwvq) does not install these CRDs itself; they
must exist before Traefik's chart can create its `Gateway` object.

Context:
Same repo pattern as AF-8ik8/AF-vwvq (`infrastructure/sealed-secrets/`'s
`list`-generator shape, verified by reading it directly), but the source
here is a plain git repo/path rather than a Helm chart repo -- the upstream
`kubernetes-sigs/gateway-api` project ships its CRDs as plain YAML under
`config/crd/experimental`, not as a Helm chart.

Version `v1.5.1` matches exactly what `fleet-infra` already uses for the
same CRDs on the real clusters (per the design spec) -- keeping the two
environments' CRD versions in lockstep avoids a real-cluster/demo-cluster
API-version drift that would make demo-tested manifests behave differently
once ported.

Ordering: this Application's resources carry
`argocd.argoproj.io/sync-wave: "-1"`, making Argo CD sync them before
wave-0 (default) Applications on the same cluster, including AF-vwvq's
`traefik-gateway`. This only controls sync order within a single Argo CD
sync operation, not creation order -- if `traefik-gateway` errors on its
first sync attempt because these CRDs aren't registered yet, Argo CD's
`selfHeal` retries it automatically once this Application succeeds. That
retry behavior is exercised for real only in the epic's human-gated
release-gate story, not in this story.

USER INTENT:
Anyone reading this repo's `infrastructure/` directory needs the CRD
dependency between `gateway-api-crds` and `traefik-gateway` to be legible
from the files themselves (the sync-wave annotation, the README's ordering
note) rather than something that only becomes apparent from an
undocumented sync failure the first time these Applications run together.
Once synced, this ApplicationSet emits one Application per cluster, and
the CRDs it installs are what makes `Gateway`/`HTTPRoute` objects
resolvable at all -- without them, a user can create an `HTTPRoute` but
the API server rejects it outright.

IMPLEMENTATION:
Create `infrastructure/gateway-api-crds/argocd/appset.yaml`:
```yaml
# One Application per cluster, installing the Gateway API CRDs (Gateway,
# HTTPRoute, GatewayClass, etc.) at the experimental channel -- the same
# version fleet-infra uses. Traefik's own chart doesn't install these; the
# traefik-gateway Application (infrastructure/traefik-gateway/) depends on
# them existing first.
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: gateway-api-crds
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: demo1
      - cluster: demo2
  template:
    metadata:
      name: 'gateway-api-crds-{{cluster}}'
      annotations:
        argocd.argoproj.io/sync-wave: "-1"
    spec:
      project: default
      source:
        repoURL: https://github.com/kubernetes-sigs/gateway-api.git
        targetRevision: v1.5.1
        path: config/crd/experimental
        directory:
          recurse: true
      destination:
        name: '{{cluster}}'
        namespace: default
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

Create `infrastructure/gateway-api-crds/README.md`:
```markdown
# gateway-api-crds — cluster-wide dependency, no promotion pipeline

Installs the [Gateway API](https://gateway-api.sigs.k8s.io/) CRDs
(`Gateway`, `HTTPRoute`, `GatewayClass`, etc.) at the experimental channel,
version `v1.5.1` -- the same version
[fleet-infra](https://github.com/adamancini/fleet-infra) uses. Traefik's own
Helm chart doesn't install these CRDs itself; `traefik-gateway`
(`infrastructure/traefik-gateway/`) needs them present before it can create
its `Gateway` object.

## Ordering

`argocd.argoproj.io/sync-wave: "-1"` makes Argo CD sync this Application's
resources before wave-0 (default) Applications on the same cluster,
including `traefik-gateway` -- so the CRDs land first. This only controls
sync order within a single Argo CD sync operation; it doesn't block
`traefik-gateway` from being *created* first, only from *syncing
successfully* first. If `traefik-gateway` errors on its first sync attempt
because the CRDs aren't registered yet, Argo CD's `selfHeal` will retry it
automatically once this Application succeeds -- no manual intervention
needed, just a one-time delay on the very first sync after the epic's
release-gate story recreates the clusters.
```

Validation (static only -- no cluster is touched by this story):
`ruby -ryaml -e "YAML.load_stream(File.read('infrastructure/gateway-api-crds/argocd/appset.yaml'))" && echo OK`
-- expect `OK`.

KEY FILES:
- Create: infrastructure/gateway-api-crds/argocd/appset.yaml
- Create: infrastructure/gateway-api-crds/README.md

PRODUCES:
- infrastructure/gateway-api-crds/argocd/appset.yaml -> ApplicationSet
  `gateway-api-crds` (namespace `argocd`), `list` generator with elements
  `demo1`/`demo2`, templating Applications named
  `gateway-api-crds-{{cluster}}` (sync-wave `-1`) that install the
  `Gateway`/`HTTPRoute`/`GatewayClass` CRDs from
  `https://github.com/kubernetes-sigs/gateway-api.git` at `v1.5.1`,
  path `config/crd/experimental`, into namespace `default` on each
  cluster. Consumed by AF-vwvq's `traefik-gateway` Application, which
  needs these CRDs registered before its chart's `Gateway` object can
  reconcile.
  source: docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
  Task 5 (verbatim); discovered automatically by the existing
  `bootstrap/infra-apps.yaml` git-directory generator (verified by reading
  that file directly -- no change needed there).

CONSUMES:
None -- this story has no upstream dependency within this backlog. It
consumes only pre-existing repo state (`bootstrap/infra-apps.yaml`'s
discovery mechanism), verified directly by reading that file during story
authoring, not produced by any story in this epic.

TESTING:
Static validation only (YAML syntax). No cluster is touched. The
sync-wave/selfHeal retry ordering documented in the README is exercised
for real only in the epic's human-gated release-gate story, not in this
story.

Acceptance Criteria:
1. [Ubiquitous] `infrastructure/gateway-api-crds/argocd/appset.yaml` exists
   with content matching IMPLEMENTATION exactly, including
   `targetRevision: v1.5.1`, `path: config/crd/experimental`, and the
   `argocd.argoproj.io/sync-wave: "-1"` annotation on the template metadata.
2. [Ubiquitous] `infrastructure/gateway-api-crds/README.md` exists and
   documents the sync-wave ordering and expected one-time selfHeal retry.
3. [Event] `ruby -ryaml -e "YAML.load_stream(...)"` against the appset.yaml
   exits with `OK` and no YAML parse error.
4. [Ubiquitous] `spec.source.targetRevision` is exactly `v1.5.1`, matching
   the version `fleet-infra` already uses (per the epic body's
   ARCHITECTURE INTEGRATION section) -- not a newer or older tag.
5. [Unwanted] This story shall not sync, apply, or otherwise mutate any
   live Argo CD instance or k3d cluster -- verification is limited to
   static YAML parsing.

MANDATORY SKILLS TO REVIEW:
`devops-toolkit:yaml-kubernetes-validator` -- this story authors an Argo CD
ApplicationSet manifest; load the skill and apply its YAML/Kubernetes
manifest review guidance before finalizing.

# One Application per cluster, installing the Gateway API CRDs (Gateway,
# HTTPRoute, GatewayClass, etc.) at the experimental channel -- the same
# version fleet-infra uses. Traefik's own chart doesn't install these; the
# traefik-gateway Application (infrastructure/traefik-gateway/) depends on
# them existing first.
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: gateway-api-crds
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: demo1
      - cluster: demo2
  template:
    metadata:
      name: 'gateway-api-crds-{{cluster}}'
      annotations:
        argocd.argoproj.io/sync-wave: "-1"
    spec:
      project: default
      source:
        repoURL: https://github.com/kubernetes-sigs/gateway-api.git
        targetRevision: v1.5.1
        path: config/crd/experimental
        directory:
          recurse: true
      destination:
        name: '{{cluster}}'
        namespace: default
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

Create `infrastructure/gateway-api-crds/README.md`:
```markdown
# gateway-api-crds — cluster-wide dependency, no promotion pipeline

Installs the [Gateway API](https://gateway-api.sigs.k8s.io/) CRDs
(`Gateway`, `HTTPRoute`, `GatewayClass`, etc.) at the experimental channel,
version `v1.5.1` -- the same version
[fleet-infra](https://github.com/adamancini/fleet-infra) uses. Traefik's own
Helm chart doesn't install these CRDs itself; `traefik-gateway`
(`infrastructure/traefik-gateway/`) needs them present before it can create
its `Gateway` object.

## Ordering

`argocd.argoproj.io/sync-wave: "-1"` makes Argo CD sync this Application's
resources before wave-0 (default) Applications on the same cluster,
including `traefik-gateway` -- so the CRDs land first. This only controls
sync order within a single Argo CD sync operation; it doesn't block
`traefik-gateway` from being *created* first, only from *syncing
successfully* first. If `traefik-gateway` errors on its first sync attempt
because the CRDs aren't registered yet, Argo CD's `selfHeal` will retry it
automatically once this Application succeeds -- no manual intervention
needed, just a one-time delay on the very first sync after the epic's
release-gate story recreates the clusters.
```

Validation (static only -- no cluster is touched by this story):
`ruby -ryaml -e "YAML.load_stream(File.read('infrastructure/gateway-api-crds/argocd/appset.yaml'))" && echo OK`
-- expect `OK`.

KEY FILES:
- Create: infrastructure/gateway-api-crds/argocd/appset.yaml
- Create: infrastructure/gateway-api-crds/README.md

PRODUCES:
- infrastructure/gateway-api-crds/argocd/appset.yaml -> ApplicationSet
  `gateway-api-crds` (namespace `argocd`), `list` generator with elements
  `demo1`/`demo2`, templating Applications named
  `gateway-api-crds-{{cluster}}` (sync-wave `-1`) that install the
  `Gateway`/`HTTPRoute`/`GatewayClass` CRDs from
  `https://github.com/kubernetes-sigs/gateway-api.git` at `v1.5.1`,
  path `config/crd/experimental`, into namespace `default` on each
  cluster. Consumed by AF-vwvq's `traefik-gateway` Application, which
  needs these CRDs registered before its chart's `Gateway` object can
  reconcile.
  source: docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
  Task 5 (verbatim); discovered automatically by the existing
  `bootstrap/infra-apps.yaml` git-directory generator (verified by reading
  that file directly -- no change needed there).

CONSUMES:
None -- this story has no upstream dependency within this backlog. It
consumes only pre-existing repo state (`bootstrap/infra-apps.yaml`'s
discovery mechanism), verified directly by reading that file during story
authoring, not produced by any story in this epic.

TESTING:
Static validation only (YAML syntax). No cluster is touched. The
sync-wave/selfHeal retry ordering documented in the README is exercised
for real only in the epic's human-gated release-gate story, not in this
story.

Acceptance Criteria:
1. [Ubiquitous] `infrastructure/gateway-api-crds/argocd/appset.yaml` exists
   with content matching IMPLEMENTATION exactly, including
   `targetRevision: v1.5.1`, `path: config/crd/experimental`, and the
   `argocd.argoproj.io/sync-wave: "-1"` annotation on the template metadata.
2. [Ubiquitous] `infrastructure/gateway-api-crds/README.md` exists and
   documents the sync-wave ordering and expected one-time selfHeal retry.
3. [Event] `ruby -ryaml -e "YAML.load_stream(...)"` against the appset.yaml
   exits with `OK` and no YAML parse error.
4. [Ubiquitous] `spec.source.targetRevision` is exactly `v1.5.1`, matching
   the version `fleet-infra` already uses (per the epic body's
   ARCHITECTURE INTEGRATION section) -- not a newer or older tag.
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
- 2026-08-05T14:33:41Z dep_added: blocks AF-cbot
- 2026-08-05T14:49:10Z status: open -> in_progress
- 2026-08-05T14:49:10Z claimed by dev-AF-qujb
- 2026-08-05T14:54:56Z status: in_progress -> in_progress
- 2026-08-05T15:33:50Z status: in_progress -> closed
- 2026-08-05T15:33:50Z dep_removed: no_longer_blocks AF-cbot

## Links
- Parent: [[AF-q1il]]

## Comments

### 2026-08-05T14:55:34Z ada
DELIVERED: AF-qujb -- Add gateway-api-crds infrastructure layer for demo1/demo2

Commit: dc41db5ef075e0fd02e17e19135655ea67840b86 (branch story/AF-qujb, pushed to origin)
Files: infrastructure/gateway-api-crds/argocd/appset.yaml (new, 36 lines)
       infrastructure/gateway-api-crds/README.md (new, 22 lines)
Working tree clean at this SHA (0 modified files).

PROOF:

1) Story validation command, verbatim, at dc41db5:
   $ ruby -ryaml -e "YAML.load_stream(File.read('infrastructure/gateway-api-crds/argocd/appset.yaml'))" && echo OK
   OK
   (exit 0, no YAML parse error)

2) Byte-exact conformance to the story's IMPLEMENTATION blocks. Rather than
   eyeball the transcription, I extracted the fenced ```yaml and ```markdown
   blocks straight out of `pvg issues show AF-qujb --json` and diffed:
   $ diff expected-appset.yaml infrastructure/gateway-api-crds/argocd/appset.yaml
   IDENTICAL (byte-exact)   [1036 bytes extracted]
   $ diff expected-README.md infrastructure/gateway-api-crds/README.md
   IDENTICAL (byte-exact)   [1187 bytes extracted]

3) Parsed-field assertions (16/16 PASS, 0 FAIL):
   apiVersion=argoproj.io/v1alpha1        kind=ApplicationSet
   metadata.name=gateway-api-crds         metadata.namespace=argocd
   generators[0].list.elements=[{cluster: demo1},{cluster: demo2}]
   template.metadata.name=gateway-api-crds-{{cluster}}
   sync-wave annotation="-1"              sync-wave value type=String (not Integer)
   source.repoURL=https://github.com/kubernetes-sigs/gateway-api.git
   source.targetRevision=v1.5.1           source.path=config/crd/experimental
   directory.recurse=true
   destination.name={{cluster}}           destination.namespace=default
   syncPolicy.automated.prune=true        syncPolicy.automated.selfHeal=true

4) Repo-wide YAML parse (blast-radius diligence): 25/25 files parse, 0 failures.
   Change is purely additive (two new files), so no existing file could regress,
   but the full sweep confirms it. Nothing skipped.

5) Discovery wiring verified against the real generator glob in
   bootstrap/infra-apps.yaml (path: infrastructure/*/argocd):
     infrastructure/gateway-api-crds/argocd -> Application infra-gateway-api-crds
     infrastructure/sealed-secrets/argocd   -> Application infra-sealed-secrets
   PASS -- the new directory is picked up with no change to infra-apps.yaml,
   as the story predicted.

6) $ pvg verify <both files> --format text
   VERIFY: PASSED (0 files scanned, 0 issues)   exit=0
   Honest caveat: pvg verify scans source files and does not scan .yaml/.md,
   so "0 files scanned" means it asserted nothing here. The real quality
   evidence is items 1-5, not this line.

AC verification table:
| AC | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| 1 | appset.yaml exists, matches IMPLEMENTATION exactly incl. targetRevision v1.5.1, path config/crd/experimental, sync-wave "-1" annotation | PASS | byte-exact diff (proof 2); 16/16 field assertions (proof 3) |
| 2 | README.md exists, documents sync-wave ordering and one-time selfHeal retry | PASS | byte-exact diff (proof 2); README "## Ordering" section covers sync-order-vs-creation-order and the automatic selfHeal retry |
| 3 | ruby YAML.load_stream exits OK, no parse error | PASS | proof 1 (verbatim story command, exit 0) |
| 4 | spec.source.targetRevision is exactly v1.5.1 | PASS | proof 3, parsed value "v1.5.1" -- not a range, not newer/older |
| 5 | Must NOT sync/apply/mutate any live Argo CD or k3d cluster | PASS | no kubectl/argocd/k3d/helm/task invocation in this session; every command run was ruby YAML parsing, git, diff, ls/find, pvg. Verification was static only |

WIRING: This ApplicationSet is not hand-mounted -- it is discovered by the
pre-existing bootstrap/infra-apps.yaml git-directory generator, which globs
infrastructure/*/argocd. Proof 5 exercises that exact glob against the real
committed bootstrap file and shows the new path resolving to Application
infra-gateway-api-crds. That is the wiring site, verified through the real
generator config rather than asserted.

LEARNINGS:
- Extracting the story's fenced code blocks programmatically from
  `pvg issues show --json` and diffing byte-for-byte is strictly better than
  transcribing them by hand when an AC says "matching IMPLEMENTATION exactly."
  It converts a subjective claim into a mechanical one and costs one command.
- Gotcha worth guarding: the sync-wave annotation MUST stay a quoted string.
  Unquoted, YAML parses "-1" as an Integer and Kubernetes rejects the manifest
  because annotation values must be strings. I added an explicit type assertion
  (sync-wave is String) so a future reformat that drops the quotes fails loudly
  rather than at apply time on a live cluster.
- This story's body is duplicated verbatim (the IMPLEMENTATION/AC/PRODUCES
  section appears twice, and there is a stray unmatched ``` fence between the
  copies). Harmless here because both copies are identical and I anchored on
  the first fenced block, but anyone diffing story text should know. Flagging
  as a possible Sr-PM story-generation artifact, not a content problem.
- pvg verify is a no-op on YAML/Markdown-only stories (0 files scanned). For
  manifest stories the meaningful gate is parse + field assertions + the
  generator-glob discovery check, not pvg verify's exit code.
- The infrastructure/*/argocd convention means a new infra layer needs zero
  bootstrap edits -- worth checking the glob rather than assuming, since a
  path typo would silently produce an Application that never appears.
