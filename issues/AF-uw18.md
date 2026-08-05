---
id: AF-uw18
title: "Bug: cluster:register-agent fails on a fresh clone -- terraform/clusters/.kubeconfigs/ directory can never exist"
status: closed
priority: 0
type: bug
labels: [discovered-by-dev, accepted]
parent: AF-q1il
created_at: 2026-08-05T15:54:11Z
created_by: ada
updated_at: 2026-08-05T16:16:08Z
content_hash: "sha256:3821feec4c448b034204cbca2417e14986eaf5437c74baf6a43a8f60490b6e99"
was_blocked_by: [AF-pydv]
assignee: dev-AF-uw18
follows: [AF-pydv, AF-vwvq]
closed_at: 2026-08-05T16:16:07Z
close_reason: "Accepted via pvg story accept"
led_to: [AF-cbot]
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
- 2026-08-05T15:54:18Z dep_added: blocked_by AF-pydv
- 2026-08-05T15:54:18Z dep_added: blocks AF-tqmb
- 2026-08-05T15:55:23Z dep_added: blocks AF-cbot
- 2026-08-05T16:02:31Z dep_removed: was_blocked_by AF-pydv
- 2026-08-05T16:10:24Z status: open -> in_progress
- 2026-08-05T16:10:24Z auto-follows: linked to predecessor AF-pydv
- 2026-08-05T16:10:24Z claimed by dev-AF-uw18
- 2026-08-05T16:12:59Z status: in_progress -> in_progress
- 2026-08-05T16:12:59Z auto-follows: linked to predecessor AF-vwvq
- 2026-08-05T16:16:07Z status: in_progress -> closed
- 2026-08-05T16:16:07Z dep_removed: no_longer_blocks AF-tqmb
- 2026-08-05T16:16:07Z dep_removed: no_longer_blocks AF-cbot

## Links
- Parent: [[AF-q1il]]
- Was blocked by: [[AF-pydv]]
- Follows: [[AF-pydv]], [[AF-vwvq]]
- Led to: [[AF-cbot]]

## Comments

### 2026-08-05T16:13:47Z ada
PROOF:

Commit SHA: 875209b316063bbb63912b8b795561a1ecfae943 (branch story/AF-uw18, pushed to origin)
Base: 66240b7 (epic/AF-q1il, with AF-pydv merged at 7f0aa98)
Working tree clean at time of verification (0 modified files).

Pre-check: confirmed the fix had NOT already landed on epic/AF-q1il.
  `grep -n "mkdir" Taskfile.yml` -> only line 17 (`mkdir -p {{.KEYPAIR_DIR}}`, pre-existing sealed-secrets task).
  Both target files present in the worktree (AF-pydv's Taskfile.yml merged; plan doc present).

Diff (exactly 2 insertions, 0 deletions, 2 files):
```
 Taskfile.yml                                                             | 1 +
 .../plans/2026-08-05-cluster-lifecycle-and-ingress-storage.md            | 1 +
 2 files changed, 2 insertions(+)
```
Both added lines are identical: `      - mkdir -p {{.TERRAFORM_CLUSTERS_DIR}}/.kubeconfigs`
Taskfile.yml at line 113 (inside cluster:register-agent cmds:), plan doc at line 653 (Task 2 Step 6 fenced block).

Commands run (all five from the story's TESTING section), literal output:

[1] `ruby -ryaml -e "YAML.load_stream(File.read('Taskfile.yml'))" && echo OK`
```
OK
```

[2] `task --list` -- seven tasks, all desc: text unchanged:
```
* cluster:create:                        Create a k3d cluster for use as an Akuity workload cluster, with the bundled Traefik and local-path-provisioner disabled. Usage: task cluster:create -- <name>
* cluster:delete:                        Delete a k3d cluster. Usage: task cluster:delete -- <name>
* cluster:recreate:                      Delete and recreate a k3d cluster cleanly (no bundled Traefik/local-path). Usage: task cluster:recreate -- <name>
* cluster:register-agent:                Export a cluster kubeconfig and apply its Argo CD/Kargo agent registration via Terraform. Usage: task cluster:register-agent -- <name>
* sealed-secrets:generate-keypair:       Generate the shared Sealed Secrets RSA keypair and install it as the active key on every cluster in CLUSTERS.
* sealed-secrets:rotate-keypair:         Rotate to a new shared keypair and re-seal every existing SealedSecret against it.
* sealed-secrets:seal:                   Seal a plaintext secret. Usage: task sealed-secrets:seal -- <namespace> <name> <output-path> <key>=<value> [<key>=<value>...]
```
Additionally diffed this output byte-for-byte against a `task --list` baseline captured BEFORE the edit: result `IDENTICAL`. This is machine-checked evidence for AC3 and AC5, not an eyeball comparison.

[3] `task --dry cluster:register-agent -- demo3` -- three lines, mkdir FIRST:
```
task: [cluster:register-agent] mkdir -p <ROOT>/terraform/clusters/.kubeconfigs
task: [cluster:register-agent] k3d kubeconfig get demo3 > <ROOT>/terraform/clusters/.kubeconfigs/demo3.yaml
task: [cluster:register-agent] cd <ROOT>/terraform/clusters && terraform apply -target='module.cluster["demo3"]'
```
(<ROOT> = /Users/ada/src/github.com/adamancini/argo-fleet/.claude/worktrees/dev-AF-uw18). Re-run at the committed SHA with identical output.

[4] `git diff --stat` on Taskfile.yml -- 1 insertion, 0 deletions, confined to cluster:register-agent. See diff above.

[5] `git diff` on the plan document -- 1 insertion inside the Task 2 Step 6 fenced block, 0 unrelated changes. See diff above.

[6] `pvg verify Taskfile.yml docs/.../2026-08-05-cluster-lifecycle-and-ingress-storage.md --format text`
```
VERIFY: PASSED (0 files scanned, 0 issues)
exit=0
```
(0 files scanned: pvg verify's substance scanner does not cover .yml/.md, so it has no findings to report on this change. Recorded for completeness, not as coverage.)

AC verification table:

| AC | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| 1 | `mkdir -p {{.TERRAFORM_CLUSTERS_DIR}}/.kubeconfigs` is FIRST cmds: entry, immediately before the `k3d kubeconfig get ... >` redirect | PASS | Diff shows it inserted directly under `cmds:` at Taskfile.yml:113; `task --dry` [3] renders it first |
| 2 | desc: text and both pre-existing cmds: entries byte-identical to AF-pydv's delivery | PASS | `git diff` shows 0 deletions / 0 modified lines -- only a pure insertion. desc: unchanged in `task --list` [2] |
| 3 | cluster:create/delete/recreate and all three sealed-secrets:* unmodified | PASS | `git diff --stat` touches only the one task's cmds:; `task --list` byte-identical to pre-edit baseline |
| 4 | YAML parse exits OK, no parse error | PASS | [1] `OK` |
| 5 | `task --list` shows all seven tasks with original desc: | PASS | [2], seven tasks, diff vs baseline `IDENTICAL` |
| 6 | dry-run renders mkdir -> k3d redirect -> terraform apply in that exact order | PASS | [3], three lines in exactly that order |
| 7 | Plan doc Task 2 Step 6 fenced block gains the identical mkdir line | PASS | Diff hunk at plan doc line 650-655; added line is byte-identical to the Taskfile one |
| 8 | No real k3d cluster create/delete/recreate, no real `k3d kubeconfig get`, no terraform apply/plan | PASS | Only `--dry` used. Verified no side effect: `ls -d terraform/clusters/.kubeconfigs` -> "No such file or directory" AFTER the dry run, proving nothing executed. demo1/demo2 untouched |
| 9 | Root cause documented in the fix commit message | PASS | Commit 875209b body: shell `>` cannot create a missing parent dir; `.kubeconfigs/` is gitignored and git never commits an empty dir, so it never exists on a fresh clone |

Coverage: the story specifies "TESTING coverage requirement: default ... The five validation commands above are the coverage requirement in full." All five ran with literal output recorded above. There is no application code in this change (one Taskfile line + one doc line), so there is no unit-test coverage percentage to report -- static validation is the specified and complete coverage for this story.

Wiring: the changed line IS the wiring -- it is a cmds: entry in a task go-task actually executes. `task --dry cluster:register-agent -- demo3` exercises it through go-task's real task resolution and template rendering (not in isolation), which is what proves both that the task still parses/resolves and that the mkdir is ordered ahead of the redirect that depends on it. AF-tqmb will run this same command live.

Errors/warnings encountered: none. No test failures, no build warnings, no deprecation notices in any command output above.

LEARNINGS:
- The story's GOTCHA about branch placement was already resolved by the time I started: AF-pydv had landed on epic/AF-q1il (merge 7f0aa98) and the plan doc was present too, so both target files existed in a worktree cut from the epic. I still ran the "has this already landed?" grep first rather than trusting either the story text or the branch name -- worth keeping as a habit on this epic, where several stories have raced ahead of their own filed descriptions.
- Capturing `task --list` to a file BEFORE editing and then `diff`-ing the post-edit output against it turns AC3/AC5 from "I looked and it seemed the same" into machine-checked evidence for a few seconds of work. Recommend this baseline-capture pattern for any story whose ACs assert "X is unmodified".
- `task --dry` is genuinely side-effect-free: confirmed by checking that `terraform/clusters/.kubeconfigs` still did not exist after the dry run. That check is also the cleanest possible evidence for the AC8 "do not touch live infra" constraint -- the absent directory simultaneously proves the bug is real and that I did not paper over it by creating the dir by hand.
- The spec/plan-parity pattern (fix the implementation AND the source plan doc it was transcribed from) has now recurred across AF-wx9b, AF-8ik8, AF-9bc8 and this story. That is four occurrences of the same class of defect in one epic. The generative fix is upstream of any individual story: the plan doc under docs/superpowers/plans/ is being treated as a write-once artifact when it is in fact a live regeneration source. Worth a retro item on whether that doc should be regenerated from the implementation, or at least gain a note that it must be kept in sync.
- Root cause here is a general shell/git interaction worth remembering beyond this repo: a `>` redirect never creates parent directories, and git cannot track an empty directory regardless of .gitignore contents. Any gitignored output directory written to by a bare redirect is a fresh-clone failure waiting to happen -- the same shape could exist elsewhere in this Taskfile's future tasks.
