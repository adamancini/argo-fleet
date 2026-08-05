---
id: AF-pydv
title: "Add Taskfile cluster lifecycle tasks: create, delete, recreate, register-agent"
status: closed
priority: 1
type: task
parent: AF-q1il
created_at: 2026-08-05T14:30:04Z
created_by: ada
updated_at: 2026-08-05T16:02:32Z
content_hash: "sha256:028d66e09ab11efe1eec734d134bd4cab7007470f6365b233ccb301687a78a50"
was_blocked_by: [AF-4wcm]
assignee: dev-AF-pydv
follows: [AF-4wcm, AF-cu83, AF-qujb]
labels: [accepted]
closed_at: 2026-08-05T16:02:31Z
close_reason: "Accepted via pvg story accept"
led_to: [AF-uw18, AF-9bc8, AF-cbot]
---

## Description
Description:
Add four new `Taskfile.yml` tasks -- `cluster:create`, `cluster:delete`,
`cluster:recreate`, `cluster:register-agent` -- that wrap k3d cluster
lifecycle and the Terraform stack from AF-4wcm into repeatable, documented
commands. These are the exact commands the human-gated live-execution story
(the epic's release-gate story) runs; this story only authors and
statically validates them, it does not run them against a real cluster.

Context:
The repo already has a `Taskfile.yml` with one `vars:` block and three
`sealed-secrets:*` tasks (`generate-keypair`, `rotate-keypair`, `seal`).
Note the existing `CLUSTERS: k3d-demo1 k3d-demo2` var -- that is the full
kubectl CONTEXT name form, used only by the sealed-secrets tasks. The four
new tasks below take a BARE cluster name (`demo1`, not `k3d-demo1`) as
their argument, since that is what `k3d cluster create/delete` and
Terraform's `var.clusters` map (from AF-4wcm) both expect natively --
do not conflate the two forms when writing these tasks.

This repo has already hit a real bug in this exact area: commit
`c422094` ("Fix Task 2 Taskfile bugs: CLI_ARGS_LIST, rotate-keypair key
preservation, pipefail") fixed a `CLI_ARGS`/`CLI_ARGS_LIST` forwarding
problem in the `sealed-secrets:*` tasks. `cluster:recreate` avoids that
whole class of bug by inlining both k3d commands directly rather than
calling `cluster:delete`/`cluster:create` via nested `task:` invocations --
nested-task `CLI_ARGS_LIST` forwarding has not been exercised anywhere in
this repo and getting it wrong has already cost a real fix cycle once.

USER INTENT:
The person operating this repo needs `task cluster:<verb> -- <name>` to be
exactly as reliable and self-documenting as the existing
`sealed-secrets:*` tasks -- clear `desc:` text describing usage, arguments
passed correctly every time (bare name, not `k3d-` prefixed), and no repeat
of the CLI_ARGS_LIST bug class that already bit this repo once. Once this
story lands, a user can run `task cluster:create -- demo3` (or any new
cluster name) and get a correctly-configured k3d cluster without ever
typing a raw `k3d` or `terraform` command by hand.

IMPLEMENTATION:
Read the current `Taskfile.yml` first (reproduced in full below as of this
story's authoring, for reference -- do not treat this embedded copy as the
source of truth if the live file has since changed; re-read the live file
before editing):

```yaml
version: '3'

vars:
  KEYPAIR_DIR: '{{.ROOT_DIR}}/.sealed-secrets-keypair'
  KEYPAIR_CERT: '{{.KEYPAIR_DIR}}/tls.crt'
  KEYPAIR_KEY: '{{.KEYPAIR_DIR}}/tls.key'
  CLUSTERS: k3d-demo1 k3d-demo2

tasks:
  sealed-secrets:generate-keypair:
    ...
  sealed-secrets:rotate-keypair:
    ...
  sealed-secrets:seal:
    ...
```//(full existing task bodies are already in the live file -- leave them untouched)

Step 1: Add `TERRAFORM_CLUSTERS_DIR` to the existing `vars:` block,
alongside `KEYPAIR_DIR` etc.:
```yaml
  TERRAFORM_CLUSTERS_DIR: '{{.ROOT_DIR}}/terraform/clusters'
```

Step 2: Add `cluster:create`:
```yaml
  cluster:create:
    desc: 'Create a k3d cluster for use as an Akuity workload cluster, with the bundled Traefik and local-path-provisioner disabled. Usage: task cluster:create -- <name>'
    cmds:
      - |
        k3d cluster create {{index .CLI_ARGS_LIST 0}} \
          --k3s-arg "--disable=traefik@server:0" \
          --k3s-arg "--disable=local-storage@server:0"
```

Step 3: Add `cluster:delete`:
```yaml
  cluster:delete:
    desc: 'Delete a k3d cluster. Usage: task cluster:delete -- <name>'
    cmds:
      - k3d cluster delete {{index .CLI_ARGS_LIST 0}}
```

Step 4: Add `cluster:recreate` -- delete then create, BOTH k3d commands
inlined directly (not nested `task:` calls to the two tasks above), per the
CLI_ARGS_LIST-forwarding rationale in Context above:
```yaml
  cluster:recreate:
    desc: 'Delete and recreate a k3d cluster cleanly (no bundled Traefik/local-path). Usage: task cluster:recreate -- <name>'
    cmds:
      - k3d cluster delete {{index .CLI_ARGS_LIST 0}} 2>/dev/null || true
      - |
        k3d cluster create {{index .CLI_ARGS_LIST 0}} \
          --k3s-arg "--disable=traefik@server:0" \
          --k3s-arg "--disable=local-storage@server:0"
```

Step 5: Add `cluster:register-agent` -- exports a kubeconfig to the exact
path `terraform.tfvars` (from AF-4wcm) expects, then applies just that
cluster's Terraform module:
```yaml
  cluster:register-agent:
    desc: 'Export a cluster kubeconfig and apply its Argo CD/Kargo agent registration via Terraform. Usage: task cluster:register-agent -- <name>'
    cmds:
      - k3d kubeconfig get {{index .CLI_ARGS_LIST 0}} > {{.TERRAFORM_CLUSTERS_DIR}}/.kubeconfigs/{{index .CLI_ARGS_LIST 0}}.yaml
      - cd {{.TERRAFORM_CLUSTERS_DIR}} && terraform apply -target='module.cluster["{{index .CLI_ARGS_LIST 0}}"]'
```

Validation (static only -- do not run these tasks against a real cluster
in this story):
1. `ruby -ryaml -e "YAML.load_stream(File.read('Taskfile.yml'))" && echo OK`
   -- expect `OK`.
2. `task --list` -- expect output including the three existing
   `sealed-secrets:*` tasks PLUS `cluster:create`, `cluster:delete`,
   `cluster:recreate`, `cluster:register-agent`, each showing its `desc:`
   text.

KEY FILES:
- Modify: Taskfile.yml

CONSUMES:
- AF-4wcm: terraform/clusters/ -> Terraform root module, `for_each =
  var.clusters` keyed by cluster name
    spec: invoked as `terraform apply -target='module.cluster["<name>"]'`
      from within `terraform/clusters/`; `<name>` must be a key of
      `var.clusters` in `terraform.tfvars` (e.g. "demo1", "demo2") -- the
      exact bare-name strings `cluster:register-agent`'s
      `{{index .CLI_ARGS_LIST 0}}` passes.
    source: AF-4wcm PRODUCES block; cross-checked against
      docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
      Task 2 "Interfaces" section.

PRODUCES:
- Taskfile.yml -> four new tasks: `cluster:create -- <name>`,
  `cluster:delete -- <name>`, `cluster:recreate -- <name>`,
  `cluster:register-agent -- <name>`, plus the `TERRAFORM_CLUSTERS_DIR` var.
  These are the exact commands the epic's release-gate (human-executed live
  execution) story runs.

TESTING:
Static validation only (YAML syntax, `task --list` output) -- these tasks
wrap external commands (`k3d`, `terraform apply`) that mutate real
infrastructure and must never be exercised by an automated test in this
story or by any Developer/PM-Acceptor pair. Coverage requirement: both
commands in the IMPLEMENTATION "Validation" list must be run with their
actual output recorded as proof.

Acceptance Criteria:
1. [Ubiquitous] `Taskfile.yml`'s `vars:` block contains
   `TERRAFORM_CLUSTERS_DIR: '{{.ROOT_DIR}}/terraform/clusters'` alongside
   the existing `KEYPAIR_DIR`/`CLUSTERS` vars.
2. [Ubiquitous] `cluster:create`, `cluster:delete`, `cluster:recreate`,
   `cluster:register-agent` all exist with the exact `desc:` text and
   `cmds:` shown in IMPLEMENTATION.
3. [Ubiquitous] `cluster:recreate` inlines both `k3d cluster delete` and
   `k3d cluster create` directly -- it does NOT call `task:
   cluster:delete` or `task: cluster:create` as nested task invocations.
4. [Event] `ruby -ryaml -e "YAML.load_stream(...)"` against `Taskfile.yml`
   exits with `OK` and no YAML parse error.
5. [Event] `task --list` shows all seven tasks (three existing
   `sealed-secrets:*` plus the four new `cluster:*`), each with its
   `desc:` text visible.
6. [Unwanted] The three existing `sealed-secrets:*` tasks shall be
   unmodified by this story -- `git diff Taskfile.yml` shows only
   additions (the new var and four new tasks), no changes to existing
   task bodies.
7. [Unwanted] This story shall not run `k3d cluster create/delete/recreate`
   or `terraform apply` against any real cluster or state -- validation is
   limited to YAML syntax and `task --list` output.

MANDATORY SKILLS TO REVIEW:
None identified (Taskfile/go-task YAML; no project-specific skill covers
go-task in this repo).

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
- 2026-08-05T14:30:16Z dep_added: blocked_by AF-4wcm
- 2026-08-05T14:33:40Z dep_added: blocks AF-cbot
- 2026-08-05T15:15:12Z dep_removed: was_blocked_by AF-4wcm
- 2026-08-05T15:27:27Z status: open -> in_progress
- 2026-08-05T15:27:27Z auto-follows: linked to predecessor AF-4wcm
- 2026-08-05T15:27:27Z claimed by dev-AF-pydv
- 2026-08-05T15:29:45Z status: in_progress -> open
- 2026-08-05T15:39:37Z status: open -> in_progress
- 2026-08-05T15:39:37Z auto-follows: linked to predecessor AF-cu83
- 2026-08-05T15:45:40Z status: in_progress -> in_progress
- 2026-08-05T15:45:40Z auto-follows: linked to predecessor AF-qujb
- 2026-08-05T15:54:18Z dep_added: blocks AF-uw18
- 2026-08-05T16:02:31Z status: in_progress -> closed
- 2026-08-05T16:02:31Z dep_removed: no_longer_blocks AF-cbot
- 2026-08-05T16:02:31Z dep_removed: no_longer_blocks AF-uw18

## Links
- Parent: [[AF-q1il]]
- Was blocked by: [[AF-4wcm]]
- Follows: [[AF-4wcm]], [[AF-cu83]], [[AF-qujb]]
- Led to: [[AF-uw18]], [[AF-9bc8]], [[AF-cbot]]

## Comments

### 2026-08-05T15:29:46Z ada
loop: reset orphaned in_progress to open (no developer worktree found; prior session presumed dead)

### 2026-08-05T15:46:37Z ada
DELIVERED: AF-pydv -- Taskfile cluster lifecycle tasks

Commit: 7ae24dd1aafc7be9f68e6db5b13b68019c5be332 (branch story/AF-pydv, pushed to origin)
Files changed: Taskfile.yml (34 insertions, 0 deletions)

PROOF:

Pre-flight -- consumed dependency present:
  $ ls terraform/clusters/
  .terraform.lock.hcl  main.tf  modules/  outputs.tf  providers.tf
  templates/  terraform.tfvars.example  variables.tf
  (AF-4wcm merged at 50c8ab1 on epic/AF-q1il)

  $ git grep -n "cluster:create\|TERRAFORM_CLUSTERS_DIR" epic/AF-q1il -- Taskfile.yml
  (no output -- work not already landed on epic; safe to implement)

Validation command 1 of 2 (AC4) -- run at SHA 7ae24dd, clean tree:
  $ ruby -ryaml -e "YAML.load_stream(File.read('Taskfile.yml'))" && echo OK
  OK

Validation command 2 of 2 (AC5) -- run at SHA 7ae24dd, clean tree:
  $ task --list
  task: Available tasks for this project:
  * cluster:create:                        Create a k3d cluster for use as an Akuity workload cluster, with the bundled Traefik and local-path-provisioner disabled. Usage: task cluster:create -- <name>
  * cluster:delete:                        Delete a k3d cluster. Usage: task cluster:delete -- <name>
  * cluster:recreate:                      Delete and recreate a k3d cluster cleanly (no bundled Traefik/local-path). Usage: task cluster:recreate -- <name>
  * cluster:register-agent:                Export a cluster kubeconfig and apply its Argo CD/Kargo agent registration via Terraform. Usage: task cluster:register-agent -- <name>
  * sealed-secrets:generate-keypair:       Generate the shared Sealed Secrets RSA keypair and install it as the active key on every cluster in CLUSTERS.
  * sealed-secrets:rotate-keypair:         Rotate to a new shared keypair and re-seal every existing SealedSecret against it.
  * sealed-secrets:seal:                   Seal a plaintext secret. Usage: task sealed-secrets:seal -- <namespace> <name> <output-path> <key>=<value> [<key>=<value>...]

  7 of 7 tasks registered, each with desc text. Pass/fail: 2/2 required
  validation commands passed, 0 failed.

Additional non-mutating proof -- `task --dry` (go-task renders the command
plan and executes NOTHING). This is the direct evidence for the story's
stated USER INTENT that a BARE name is forwarded, not the k3d- prefixed
CONTEXT form:
  $ task --dry cluster:create -- demo3
  task: [cluster:create] k3d cluster create demo3 \
    --k3s-arg "--disable=traefik@server:0" \
    --k3s-arg "--disable=local-storage@server:0"
  $ task --dry cluster:delete -- demo3
  task: [cluster:delete] k3d cluster delete demo3
  $ task --dry cluster:recreate -- demo3
  task: [cluster:recreate] k3d cluster delete demo3 2>/dev/null || true
  task: [cluster:recreate] k3d cluster create demo3 \
    --k3s-arg "--disable=traefik@server:0" \
    --k3s-arg "--disable=local-storage@server:0"
  $ task --dry cluster:register-agent -- demo3
  task: [cluster:register-agent] k3d kubeconfig get demo3 > <ROOT>/terraform/clusters/.kubeconfigs/demo3.yaml
  task: [cluster:register-agent] cd <ROOT>/terraform/clusters && terraform apply -target='module.cluster["demo3"]'

  Confirms: bare `demo3` (not `k3d-demo3`) reaches every command;
  TERRAFORM_CLUSTERS_DIR interpolates; the -target='module.cluster["demo3"]'
  quoting survives templating intact.

AC7 negative proof -- no real infrastructure touched:
  $ k3d cluster list
  NAME    SERVERS   AGENTS   LOADBALANCER
  demo1   1/1       0/0      true
  demo2   1/1       0/0      true
  (no demo3 -- nothing created; demo1/demo2 pre-existing and untouched)
  $ ls terraform/clusters/.kubeconfigs
  ls: terraform/clusters/.kubeconfigs: No such file or directory
  (no kubeconfig written)
  No `terraform apply` was run; no tfstate exists or was modified.

pvg verify:
  $ pvg verify Taskfile.yml --format text
  VERIFY: PASSED (0 files scanned, 0 issues)
  (0 files scanned: pvg verify's source-file scanner does not cover YAML.
  Substantive validation for this story is the two commands above.)

Coverage: n/a in the line-coverage sense -- this story is a declarative
Taskfile change whose TESTING section mandates static validation only.
Both mandated validation commands were run with output recorded above,
which is the story's stated coverage requirement, plus the four --dry
renders and the AC7 negative proof.

Acceptance criteria verification:
| AC | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| 1 | vars: has TERRAFORM_CLUSTERS_DIR: '{{.ROOT_DIR}}/terraform/clusters' beside KEYPAIR_DIR/CLUSTERS | PASS | Taskfile.yml:8, added directly after CLUSTERS at line 7; see diff hunk @@ -5,6 +5,7 @@ |
| 2 | Four tasks exist with exact desc: and cmds: from IMPLEMENTATION | PASS | Taskfile.yml:83-114; desc text reproduced verbatim in `task --list` above; cmds byte-identical to the story's Steps 2-5 |
| 3 | cluster:recreate inlines both k3d commands, no nested `task:` calls | PASS | Taskfile.yml:105-111 -- two literal k3d cmds; `git grep -n "task: cluster:" Taskfile.yml` returns nothing. --dry shows both steps labelled [cluster:recreate], not [cluster:delete]/[cluster:create] |
| 4 | ruby YAML.load_stream exits OK, no parse error | PASS | Validation command 1 above -- printed OK, exit 0 |
| 5 | task --list shows all seven tasks with desc | PASS | Validation command 2 above -- 3 sealed-secrets:* + 4 cluster:*, all with desc |
| 6 | sealed-secrets:* unmodified; diff is additions only | PASS | `git diff --stat`: "1 file changed, 34 insertions(+)" -- zero deletions. `git diff -U0 \| grep -c '^-[^-]'` = 0 |
| 7 | No k3d create/delete/recreate or terraform apply against real cluster/state | PASS | AC7 negative proof above. Only read-only (`k3d cluster list`) and non-executing (`task --dry`) commands were used |

Wiring evidence: the wiring site is Taskfile.yml's own `tasks:` map -- go-task
registers each key as an invocable target. `task --list` IS the through-the-wiring
test: it exercises go-task's real parse+register path over the committed file
rather than inspecting the YAML in isolation. The `task --dry` renders go one
step further, exercising go-task's template engine and CLI_ARGS_LIST binding
end-to-end for all four tasks, stopping only short of exec. Downstream consumer
is the epic's human-executed release-gate story (AF-cbot), which invokes these
task names directly.

DISCOVERED_BUG:
  title: cluster:register-agent fails on first run -- terraform/clusters/.kubeconfigs/ is gitignored and never created
  context: |
    Implemented AF-pydv exactly as its AC2 mandates ("exact desc: text and
    cmds: shown in IMPLEMENTATION"), so I did NOT deviate to fix this. But the
    first cmd of cluster:register-agent is a shell redirect:
      k3d kubeconfig get <name> > {{.TERRAFORM_CLUSTERS_DIR}}/.kubeconfigs/<name>.yaml
    A `>` redirect cannot create missing parent directories. The directory
    terraform/clusters/.kubeconfigs/ does not exist in the repo and cannot
    ever exist in a fresh checkout: .gitignore line "terraform/clusters/.kubeconfigs/"
    excludes it, and git does not track empty directories regardless. I
    verified it is absent right now (ls -> No such file or directory).
    Nothing in docs/, README.md, or terraform/clusters/terraform.tfvars.example
    instructs an operator to mkdir it -- the .example only says kubeconfigs
    should be kept "under .kubeconfigs/". So on any fresh clone the task dies
    with "No such file or directory" before Terraform is ever reached.
    Likely fix: prepend `mkdir -p {{.TERRAFORM_CLUSTERS_DIR}}/.kubeconfigs`
    as the task's first cmd. That is a one-line change but it would contradict
    AF-pydv's AC2 verbatim-cmds requirement, so it needs its own story rather
    than a silent edit here. This will bite the epic's release-gate story
    (AF-cbot), which runs these exact commands live.
  affected_files: Taskfile.yml (cluster:register-agent), .gitignore, terraform/clusters/terraform.tfvars.example
  discovered_during: AF-pydv

LEARNINGS:
- `task --dry` is the right proof tool for Taskfile stories whose ACs forbid
  live execution. It runs go-task's real template engine and prints the exact
  command plan while executing nothing, so it proves argument forwarding
  (the bare-name-vs-k3d-prefix distinction that is this story's whole point)
  without touching infrastructure. Static YAML parsing alone could not have
  caught a CLI_ARGS_LIST templating mistake; `task --list` only proves
  registration, not correct interpolation.
- The story's warning about two coexisting name forms was well-founded and is
  a live trap in this file. `CLUSTERS: k3d-demo1 k3d-demo2` (kubectl CONTEXT
  form) sits four lines above the new tasks that require the BARE form. Anyone
  later tempted to make cluster:* iterate over CLUSTERS would silently produce
  `k3d cluster create k3d-demo1`. Worth a comment on the CLUSTERS var if a
  future story touches it.
- Inlining cluster:recreate rather than nesting `task:` calls costs six
  duplicated lines and buys certainty. I left an in-file comment citing
  c422094 so the duplication does not read as an oversight and get "cleaned
  up" into a nested call later.
- Appending the new tasks at end-of-file (rather than sorting cluster:* above
  sealed-secrets:*) made AC6 trivially provable: one clean hunk, 34
  insertions, 0 deletions. `task --list` sorts alphabetically anyway, so
  file order costs nothing in UX. Worth doing whenever an AC demands
  "additions only".
- Gotcha for the PM: `pvg verify` reports "0 files scanned" on a YAML-only
  change -- its scanner targets source files. That is a clean pass, not a
  skipped check; the real gate here is the two mandated validation commands.
