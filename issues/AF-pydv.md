---
id: AF-pydv
title: "Add Taskfile cluster lifecycle tasks: create, delete, recreate, register-agent"
status: open
priority: 1
type: task
parent: AF-q1il
created_at: 2026-08-05T14:30:04Z
created_by: ada
updated_at: 2026-08-05T14:30:04Z
content_hash: "sha256:b15bac2c5427ead61cf31855b103cf7bec588d88b6735fb919a6f19b4a685e37"
blocked_by: [AF-4wcm]
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
of the CLI_ARGS_LIST bug class that already bit this repo once.

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


## History
- 2026-08-05T14:30:16Z dep_added: blocked_by AF-4wcm

## Links
- Parent: [[AF-q1il]]
- Blocked by: [[AF-4wcm]]

## Comments
