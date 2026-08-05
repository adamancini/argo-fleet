---
id: AF-uw18
title: "Bug: cluster:register-agent fails on a fresh clone -- terraform/clusters/.kubeconfigs/ directory can never exist"
status: open
priority: 0
type: bug
labels: [discovered-by-dev]
parent: AF-q1il
created_at: 2026-08-05T15:54:11Z
created_by: ada
updated_at: 2026-08-05T15:54:11Z
content_hash: "sha256:542c59f0f159f5ec05db58d672066765218a9040d110b49c71c17f309c32522b"
blocked_by: [AF-pydv]
---

## Description
Priority: P0 (bugs are always P0)

Description:
`cluster:register-agent`'s first command is a plain shell `>` redirect
writing a kubeconfig into `terraform/clusters/.kubeconfigs/`, a directory
that is gitignored and therefore never exists on a fresh checkout. A shell
`>` redirect cannot create a missing parent directory, so on any fresh
clone `task cluster:register-agent -- <name>` fails immediately with a
shell "No such file or directory" error, before Terraform is ever
invoked.

DISCOVERED DURING:
AF-pydv (Add Taskfile cluster lifecycle tasks: create, delete, recreate,
register-agent, epic AF-q1il). The AF-pydv developer implemented
`cluster:register-agent` exactly as that story's AC2 required ("exact
`desc:` text and `cmds:` shown in IMPLEMENTATION" -- a verbatim
transcription of the design plan's Task 2 Step 6), so did not deviate to
fix this themselves; doing so would have violated their own story's AC2.
They filed this as a `DISCOVERED_BUG` in AF-pydv's delivery comment
instead. This triage turns that report into its own tracked, fixable
story.

SYMPTOMS:
- On a fresh clone of this repo, running
  `task cluster:register-agent -- <name>` fails on its first command with
  a shell redirection error resembling
  `bash: terraform/clusters/.kubeconfigs/<name>.yaml: No such file or
  directory` -- Terraform is never reached.
- `ls terraform/clusters/.kubeconfigs` returns "No such file or directory"
  on a fresh checkout, confirming the directory is genuinely absent, not
  just untracked-but-present.
- Nothing in `docs/`, `README.md`, or
  `terraform/clusters/terraform.tfvars.example` instructs an operator to
  `mkdir` this directory before running the task; the `.example` file only
  says kubeconfigs should be kept "under `.kubeconfigs/`", which reads as
  descriptive, not as a setup instruction.

EVIDENCE:
- `.gitignore` (repo root) contains the line
  `terraform/clusters/.kubeconfigs/` -- this directory is deliberately
  excluded from git (added by AF-4wcm, which migrated the Terraform stack
  and its gitignore hygiene from `akp-infra`).
- Git does not track empty directories regardless of `.gitignore` content,
  so even removing the gitignore line would not make this directory exist
  on a fresh clone -- nothing ever commits an empty directory.
- `Taskfile.yml`'s `cluster:register-agent` task (added by AF-pydv, not
  yet merged into `epic/AF-q1il` as of this bug's filing -- see the GOTCHA
  below for exactly where to find it) reads:
  ```yaml
    cluster:register-agent:
      desc: 'Export a cluster kubeconfig and apply its Argo CD/Kargo agent registration via Terraform. Usage: task cluster:register-agent -- <name>'
      cmds:
        - k3d kubeconfig get {{index .CLI_ARGS_LIST 0}} > {{.TERRAFORM_CLUSTERS_DIR}}/.kubeconfigs/{{index .CLI_ARGS_LIST 0}}.yaml
        - cd {{.TERRAFORM_CLUSTERS_DIR}} && terraform apply -target='module.cluster["{{index .CLI_ARGS_LIST 0}}"]'
  ```
  The first `cmds:` entry is a bare shell `>` redirect with no preceding
  directory creation.
- The same defective command (no `mkdir` step) is documented verbatim in
  `docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md`,
  Task 2 ("Taskfile cluster lifecycle tasks"), Step 6 ("Add
  `cluster:register-agent`"), currently at approximately line 650-655 on
  the `main` branch:
  ```yaml
    cluster:register-agent:
      desc: 'Export a cluster kubeconfig and apply its Argo CD/Kargo agent registration via Terraform. Usage: task cluster:register-agent -- <name>'
      cmds:
        - k3d kubeconfig get {{index .CLI_ARGS_LIST 0}} > {{.TERRAFORM_CLUSTERS_DIR}}/.kubeconfigs/{{index .CLI_ARGS_LIST 0}}.yaml
        - cd {{.TERRAFORM_CLUSTERS_DIR}} && terraform apply -target='module.cluster["{{index .CLI_ARGS_LIST 0}}"]'
  ```
  This is exactly the AF-wx9b/AF-8ik8/AF-9bc8 pattern already established
  in this epic: a defect in the source plan document will re-propagate
  into any future regeneration unless the plan document itself is also
  fixed, not just the implementation.

POSSIBLE CAUSES:
1. The design plan's Task 2 Step 6 (the source both AF-pydv's
   implementation and this evidence are transcribed from) never included a
   directory-creation step for `.kubeconfigs/` -- the omission originates
   in the plan document, not in AF-pydv's transcription of it.
2. `terraform/clusters/.kubeconfigs/` being gitignored (correctly, since it
   holds real kubeconfig client-certificate/key material -- see AF-4wcm)
   was conflated with "the directory will exist because Terraform's own
   gitignore hygiene creates it," which is not how gitignore or git's
   directory tracking works.

CONFIG (if relevant):
`TERRAFORM_CLUSTERS_DIR` (a `Taskfile.yml` var, added by AF-pydv) resolves
to `{{.ROOT_DIR}}/terraform/clusters`, i.e. `terraform/clusters` at the
repo root. `.kubeconfigs/` is a subdirectory of that path, gitignored via
the repo-root `.gitignore` line `terraform/clusters/.kubeconfigs/`.

GOTCHA -- where to find the two files this bug touches (same lesson AF-wx9b
already learned in this epic; re-stated here so this story's developer
does not repeat the investigation): `Taskfile.yml`'s `cluster:register-agent`
task exists only on branch `story/AF-pydv` as of this bug's filing --
AF-pydv is `delivered` but not yet merged into `epic/AF-q1il`, so a
worktree cut directly from `epic/AF-q1il` will NOT show this task in
`Taskfile.yml` yet. This bug's `blocked_by AF-pydv` dependency (see below)
exists specifically so this story starts only once AF-pydv's Taskfile.yml
changes have actually landed on the branch this story works from. Likewise,
`docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md`
lives on `main` (committed directly there, per commit `9cd3f16`, with an
unrelated follow-up fix at `ca7482e`) and is currently absent from
`epic/AF-q1il` entirely -- run `git log --all -- <path>` and
`git branch --contains <sha>` before assuming either file is missing or
already fixed, exactly as AF-wx9b's own LEARNINGS recorded.

CONSUMES:
- AF-pydv: Taskfile.yml -> `cluster:register-agent` task (`cmds:` list,
  `TERRAFORM_CLUSTERS_DIR` var)
    spec: current (buggy) task body reproduced verbatim in EVIDENCE above;
      this story consumes AF-pydv's landed Taskfile.yml as its starting
      point and modifies only the `cluster:register-agent` task's `cmds:`
      list.
    source: AF-pydv PRODUCES block ("Taskfile.yml -> four new tasks ...").

PRODUCES:
- Taskfile.yml -> `cluster:register-agent` task's `cmds:` list gains a new
  first entry, `mkdir -p {{.TERRAFORM_CLUSTERS_DIR}}/.kubeconfigs`, ahead
  of the existing `k3d kubeconfig get ... >` redirect and `terraform apply`
  commands. This is the exact command the epic's release-gate story
  (AF-tqmb) will run live.
- docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md
  -> Task 2, Step 6's `cluster:register-agent` YAML code block gains the
  same `mkdir -p` line, so a future regeneration from this plan does not
  reintroduce this exact bug.

IMPLEMENTATION (for reference -- the fix itself, not new design; nothing
here should be treated as inventing behavior beyond what AF-pydv's story
already specified minus the one missing line):

Fix 1 -- `Taskfile.yml`, `cluster:register-agent` task, prepend one `cmds:`
entry:
```yaml
  cluster:register-agent:
    desc: 'Export a cluster kubeconfig and apply its Argo CD/Kargo agent registration via Terraform. Usage: task cluster:register-agent -- <name>'
    cmds:
      - mkdir -p {{.TERRAFORM_CLUSTERS_DIR}}/.kubeconfigs
      - k3d kubeconfig get {{index .CLI_ARGS_LIST 0}} > {{.TERRAFORM_CLUSTERS_DIR}}/.kubeconfigs/{{index .CLI_ARGS_LIST 0}}.yaml
      - cd {{.TERRAFORM_CLUSTERS_DIR}} && terraform apply -target='module.cluster["{{index .CLI_ARGS_LIST 0}}"]'
```
Only the `mkdir -p` line is new; the `desc:` text and the two existing
`cmds:` entries are byte-identical to what AF-pydv delivered -- do not
alter them.

Fix 2 -- `docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md`,
Task 2, Step 6: apply the identical one-line addition to the fenced YAML
block (currently at approximately line 650-655 on `main`), so the plan
document and the implementation stay in sync -- this is the same
spec/plan-parity fix pattern AF-wx9b already applied to Task 3 elsewhere in
this same plan document (commit `ca7482e`, "Fix plan Task 3: isDefaultClass
must be an unquoted boolean, not \"false\""). Re-read the live file before
editing -- do not assume the line number above is still exact once AF-wx9b's
and AF-9bc8's own edits have landed.

TESTING:
Static validation only, matching AF-pydv's own testing convention for this
Taskfile -- these `cluster:*` tasks wrap external commands (`k3d`,
`terraform apply`) that mutate real infrastructure and must never be
exercised by an automated test in this story. No live cluster or Terraform
state is touched; no credentials are needed.

Validation commands (run all, record literal output as proof):
1. `ruby -ryaml -e "YAML.load_stream(File.read('Taskfile.yml'))" && echo OK`
   -- expect `OK`.
2. `task --list` -- expect the same seven tasks as before (three
   `sealed-secrets:*`, four `cluster:*`), each with its `desc:` text
   unchanged.
3. `task --dry cluster:register-agent -- demo3` -- expect THREE rendered
   lines in this exact order: `mkdir -p <ROOT>/terraform/clusters/.kubeconfigs`,
   then `k3d kubeconfig get demo3 > <ROOT>/terraform/clusters/.kubeconfigs/demo3.yaml`,
   then `cd <ROOT>/terraform/clusters && terraform apply -target='module.cluster["demo3"]'`.
   This is the direct evidence that the fix actually orders the mkdir
   before the redirect that needs it.
4. `git diff --stat` on `Taskfile.yml` -- expect exactly one line added,
   zero lines removed, confined to the `cluster:register-agent` task.
5. `git diff` on the plan document -- expect exactly one line added inside
   the Task 2 Step 6 fenced block, zero unrelated changes.

TESTING coverage requirement: default (this is a one-line Taskfile
addition plus a matching one-line doc fix; there is no application code to
unit-test). The five validation commands above are the coverage
requirement in full -- do not claim this story complete without every one
of their literal outputs recorded.

Acceptance Criteria:
1. [Ubiquitous] `Taskfile.yml`'s `cluster:register-agent` task's `cmds:`
   list has `mkdir -p {{.TERRAFORM_CLUSTERS_DIR}}/.kubeconfigs` as its
   first entry, immediately before the existing `k3d kubeconfig get ... >`
   redirect.
2. [Ubiquitous] The task's `desc:` text and its two pre-existing `cmds:`
   entries (`k3d kubeconfig get ...`, `terraform apply ...`) are
   byte-identical to what AF-pydv delivered -- unchanged except for the
   one new line ahead of them.
3. [Unwanted] The other three `cluster:*` tasks (`cluster:create`,
   `cluster:delete`, `cluster:recreate`) and all three `sealed-secrets:*`
   tasks shall be unmodified by this story.
4. [Event] `ruby -ryaml -e "YAML.load_stream(File.read('Taskfile.yml'))"`
   exits with `OK` and no YAML parse error, run after the fix.
5. [Event] `task --list` shows all seven tasks, each with its original
   `desc:` text, run after the fix.
6. [Event] `task --dry cluster:register-agent -- demo3` renders the
   `mkdir -p` line before the `k3d kubeconfig get` redirect line, before
   the `terraform apply` line, in that exact order.
7. [Ubiquitous]
   `docs/superpowers/plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md`'s
   Task 2 Step 6 fenced YAML block for `cluster:register-agent` is updated
   with the identical `mkdir -p {{.TERRAFORM_CLUSTERS_DIR}}/.kubeconfigs`
   line, so a future regeneration from this plan does not reintroduce this
   bug.
8. [Unwanted] This story shall not run `k3d cluster create/delete/recreate`,
   `k3d kubeconfig get` for real, or `terraform apply`/`terraform plan`
   against any real cluster or state -- validation is limited to YAML
   syntax, `task --list`, and `task --dry` output, exactly as AF-pydv's own
   TESTING section required for the same file.
9. Root cause documented in the fix commit message: a shell `>` redirect
   cannot create a missing parent directory, and
   `terraform/clusters/.kubeconfigs/` is gitignored and never committed as
   an empty directory, so it never exists on a fresh clone.

MANDATORY SKILLS TO REVIEW:
None identified (Taskfile/go-task YAML plus a matching Markdown doc edit;
no project-specific skill covers go-task in this repo, consistent with
AF-pydv's own MANDATORY SKILLS entry).

## Acceptance Criteria


## Design


## Notes


## History
- 2026-08-05T15:54:18Z dep_added: blocked_by AF-pydv

## Links
- Parent: [[AF-q1il]]
- Blocked by: [[AF-pydv]]

## Comments
