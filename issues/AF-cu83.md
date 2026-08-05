---
id: AF-cu83
title: "Bug: terraform/clusters provider version unpinned after migration (v0.13.0 -> v0.14.0 float)"
status: closed
priority: 0
type: bug
labels: [discovered-by-pm, delivered, accepted]
parent: AF-q1il
created_at: 2026-08-05T15:22:58Z
created_by: ada
updated_at: 2026-08-05T15:39:46Z
content_hash: "sha256:9ade7cf9c399a066f6887d59927cb3225bc15d6e894db0eb651619b0c9d93ed8"
blocked_by: [AF-4wcm]
assignee: dev-AF-cu83
follows: [AF-8ik8, AF-qujb]
closed_at: 2026-08-05T15:39:37Z
close_reason: "Accepted: akuity/akp provider pinned to 0.13.0 via committed .terraform.lock.hcl, generated and checksum-verified by terraform init against the source stack's applied version; all 8 ACs verified independently (init/validate reproduced, byte-identical diff against akp-infra/03-clusters lock, git hygiene clean, no unrelated file changes). Single-platform (darwin_arm64) hash is acceptable as delivered -- matches source stack's own lock exactly and no Linux CI/operator currently exercises this stack; multi-platform locking deferred as documented future work, not a gap."
led_to: [AF-pydv]
---

## Description
Priority: P0 (bugs are always P0)

Description:
`terraform/clusters/` (migrated from `akp-infra/03-clusters` by AF-4wcm) has
no `.terraform.lock.hcl`, so a fresh `terraform init` resolves the newest
`akuity/akp` provider satisfying the floating `~> 0.10` constraint in
`providers.tf` instead of the version the source stack has real,
already-applied state pinned to. Pin the provider in the migrated stack the
same way the source stack pins it.

DISCOVERED DURING:
AF-4wcm ("Migrate cluster/agent registration Terraform from akp-infra into
argo-fleet") -- surfaced during PM-Acceptor review as a non-blocking
OBSERVATION on an already-accepted, already-merged story. AF-4wcm's own
nine-file `KEY FILES`/`IMPLEMENTATION` list explicitly excludes
`.terraform.lock.hcl` (it's a generated init artifact, not a copyable
source file), so its absence is correct behavior for that story, not a
defect in it. This bug is the deliberate follow-up the PM-Acceptor's
adjudication comment on AF-4wcm flagged: "Unpinned provider
(.terraform.lock.hcl correctly excluded per file list) is legitimately out
of scope for this story and forwarded as a follow-up."

SYMPTOMS:
- `terraform/clusters/.terraform.lock.hcl` does not exist (confirmed via
  `ls terraform/clusters/`).
- `terraform/clusters/providers.tf` constrains `akuity/akp` to `~> 0.10`
  with no lock file to pin a specific patch/minor within that range:
  ```hcl
  required_providers {
    akp = {
      source  = "akuity/akp"
      version = "~> 0.10"
    }
  }
  ```
- The sibling source stack this repo was migrated from,
  `/Users/ada/src/github.com/adamancini/akp-infra/03-clusters/.terraform.lock.hcl`,
  pins `registry.terraform.io/akuity/akp` at `version = "0.13.0"` (confirmed
  by reading that file directly).
- Running `terraform init -backend=false` in `terraform/clusters/` today
  resolves and would lock `akuity/akp` v0.14.0 -- one minor version ahead of
  the source stack's real, currently-applied pin -- because nothing in the
  migrated stack constrains the resolution to v0.13.0.
- `terraform init -backend=false && terraform validate` passes cleanly
  against v0.14.0 today (AF-4wcm's own acceptance evidence confirms this),
  so this is not a currently-broken validation -- it is an unpinned
  provider that will silently float further every time `.terraform/` and
  the lock file get regenerated, until something (most likely
  AF-tqmb, "Recreate demo1/demo2...", the epic's human-gated release-gate
  story that runs real `terraform apply` against real infrastructure) runs
  `terraform init` again and locks in whatever the newest matching version
  happens to be at that moment, with no review of what changed in it.

EVIDENCE:
```
$ cat terraform/clusters/providers.tf
terraform {
  required_version = ">= 1.5"

  required_providers {
    akp = {
      source  = "akuity/akp"
      version = "~> 0.10"
    }
  }
}
```
```
$ grep -A1 'provider "registry.terraform.io/akuity/akp"' \
    /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/.terraform.lock.hcl
provider "registry.terraform.io/akuity/akp" {
  version     = "0.13.0"
```
```
$ ls terraform/clusters/*.lock.hcl
ls: terraform/clusters/*.lock.hcl: No such file or directory
```
AF-4wcm's own PM-acceptance comment (recorded on that closed, accepted
story): "OBSERVATION (not a blocker, no action taken -- out of scope):
akp-infra/03-clusters ships a `.terraform.lock.hcl` pinning akuity/akp
v0.13.0. It is not in this story's nine-file list, so I did not copy it.
Consequently a fresh `terraform init` here resolved v0.14.0 (the `~> 0.10`
constraint floats). Validation passes either way, but flagging so a
follow-up story can decide whether to pin ... before anyone runs
`terraform apply` against real infrastructure."

POSSIBLE CAUSES:
1. AF-4wcm correctly treated `.terraform.lock.hcl` as a generated init
   artifact rather than source code, so it was (correctly) never in scope
   for a byte-identical file-copy story -- the gap is structural (no story
   in the epic ever generates a lock file for the new location), not a
   copying mistake.
2. `providers.tf`'s `~> 0.10` constraint is inherited verbatim from the
   source stack (correct -- AF-4wcm's AC1/AC3 required byte-identical
   fidelity), but a version constraint alone never pins an exact resolved
   version; only a committed lock file does that. The source stack has a
   lock file; the migrated one does not yet.

CONFIG (if relevant):
Provider: `akuity/akp`, constraint `~> 0.10` (`terraform/clusters/providers.tf`).
Source-stack pin for comparison: `akuity/akp` `0.13.0`
(`akp-infra/03-clusters/.terraform.lock.hcl`). No credentials or live
backend required to reproduce or fix this -- `terraform init -backend=false`
against the existing `providers.tf` is sufficient; no
`terraform.tfvars` is needed to generate a provider lock file.

USER INTENT:
The person who will eventually run `terraform apply` against real,
currently-running infrastructure (AF-tqmb) needs the provider version that
apply uses to be the same, deliberately-chosen version reviewed today --
not whatever happens to be newest on the Terraform Registry the moment
`terraform init` is next invoked. A provider version bump between "this
was validated" and "this was applied to real clusters" is exactly the kind
of unreviewed behavior change pinning exists to prevent.

IMPLEMENTATION:
- Run `terraform init -backend=false` from `terraform/clusters/` (no
  `terraform.tfvars` present, no backend, no real credentials needed -- this
  matches AF-4wcm's own validation step 7, which already proved this
  command succeeds against the migrated stack).
- Prefer pinning to the same version the source stack uses,
  `akuity/akp` `0.13.0`, so the migrated stack's locked version matches
  what has real, currently-applied state behind it in `akp-infra/03-clusters`
  and what the epic's design intent assumes ("registering fresh from the
  new location" per AF-4wcm's Context -- fresh registration, not a fresh
  provider version). If `0.13.0` is no longer resolvable against the
  `~> 0.10` constraint by the time this story runs (deprecated/pulled from
  the registry), the next-best pin is whatever `terraform init` resolves
  today under the existing constraint -- record which version was chosen
  and why in this story's evidence.
- Commit the resulting `terraform/clusters/.terraform.lock.hcl`. Confirm it
  is not excluded by `.gitignore` first: current `.gitignore` (added by
  AF-4wcm) ignores `terraform/clusters/.terraform/`, `*.tfstate*`,
  `*.tfvars` (except `*.tfvars.example`), and `.kubeconfigs/` -- it does
  NOT ignore `.terraform.lock.hcl`, which is correct, since the lock file
  (unlike state, vars, and kubeconfigs) contains no secrets and must be
  committed for the pin to take effect for anyone else running
  `terraform init` against this stack, including AF-tqmb's operator.
- Remove the `.terraform/` provider-plugin cache directory before
  committing (already gitignored, but `terraform init` populates it
  locally and it should not be staged) -- same hygiene AF-4wcm's own
  acceptance evidence already called out ("Init artifacts (.terraform/,
  .terraform.lock.hcl) were removed before commit" was true for AF-4wcm
  only because it never ran init in the first place; this story DOES run
  init, so only `.terraform/` gets cleaned, and the lock file is the
  intended, committed output).
- No code changes to `providers.tf`, `main.tf`, `variables.tf`,
  `outputs.tf`, or any module file -- this story only adds one new,
  generated file.

KEY FILES:
- Create: terraform/clusters/.terraform.lock.hcl (generated by `terraform
  init -backend=false`, then committed)
- No modification to: terraform/clusters/providers.tf (constraint stays
  `~> 0.10` -- the fix is the lock file, not a tighter constraint)

CONSUMES:
- AF-4wcm: terraform/clusters/ -> Terraform stack with `required_providers
    { akp = { source = "akuity/akp", version = "~> 0.10" } }` in
    providers.tf.
    spec: `terraform init -backend=false` run from `terraform/clusters/`
      (no terraform.tfvars, no backend) succeeds today against this
      constraint per AF-4wcm's own AC7 evidence -- this story runs that
      exact command and commits its lock-file output instead of
      discarding it.
    source: AF-4wcm PRODUCES block (terraform/clusters/ -> Terraform stack,
      root module `for_each = var.clusters`) and AF-4wcm Acceptance
      Criterion 7.

PRODUCES:
- terraform/clusters/.terraform.lock.hcl -> committed provider lock file
  pinning `registry.terraform.io/akuity/akp` to a single resolved version
  (target: `0.13.0`, matching the source stack's real applied pin; record
  actual resolved version in evidence if registry availability forces a
  different one). Consumed by AF-tqmb's Step 2/3/4 `task cluster:recreate`
  / `task cluster:register-agent` invocations, which call `terraform apply`
  from this same `terraform/clusters/` directory and will now resolve the
  provider from this lock file instead of floating.

TESTING:
Default coverage: static validation only, no live cluster or credential
access required or performed.
- `terraform init -backend=false` succeeds and writes
  `.terraform.lock.hcl` with exactly one `provider
  "registry.terraform.io/akuity/akp"` block.
- `terraform validate` (no `terraform.tfvars` present) succeeds with
  "Success! The configuration is valid." -- same command AF-4wcm's AC7
  already proved passes; this story additionally confirms it still passes
  with the lock file present.
- `git status` after staging shows only `terraform/clusters/.terraform.lock.hcl`
  as new/changed -- no `.terraform/`, no `*.tfstate*`, no `*.tfvars`
  (non-`.example`), no `.kubeconfigs/` content staged.
- Record the exact resolved/locked version number as literal command
  output (not paraphrased) in the delivery evidence, since that number is
  this story's entire reason for existing.

Acceptance Criteria:
1. [Event] `terraform init -backend=false`, run from `terraform/clusters/`
   with no `terraform.tfvars` present and no real backend or credentials,
   creates `terraform/clusters/.terraform.lock.hcl`.
2. [Ubiquitous] The committed `.terraform.lock.hcl` contains exactly one
   `provider "registry.terraform.io/akuity/akp"` block with a single
   pinned `version`, satisfying the existing `~> 0.10` constraint in
   `providers.tf`.
3. [Ubiquitous] The pinned version matches the source stack's real applied
   pin, `0.13.0` (`akp-infra/03-clusters/.terraform.lock.hcl`), unless that
   exact version is no longer resolvable from the registry under the
   `~> 0.10` constraint -- in which case the story records, in its
   delivery evidence, which version was resolved instead and why 0.13.0
   was unavailable.
4. [Event] `terraform validate` (no `terraform.tfvars` present) succeeds
   with "Success! The configuration is valid." after the lock file is
   added, with literal command output recorded as proof.
5. [Unwanted] This story shall not modify `providers.tf`'s `~> 0.10`
   version constraint, `main.tf`, `variables.tf`, `outputs.tf`, or any file
   under `terraform/clusters/modules/`.
6. [Unwanted] This story shall not read, copy, modify, or commit
   `akp-infra/03-clusters/terraform.tfstate`,
   `akp-infra/03-clusters/terraform.tfstate.backup`, or any
   `akp-infra/03-clusters/terraform.tfvars` (non-`.example`) file, and
   shall not run `terraform apply`, `terraform plan` against a real
   backend, or read `AKUITY_API_KEY_ID`/`AKUITY_API_KEY_SECRET`.
7. [Unwanted] `git status` after staging this story's changes shall show
   no file matching `*.tfstate*`, a bare `*.tfvars` (non-`.example`),
   `.terraform/`, or anything under `.kubeconfigs/` -- confirmed via
   `git status` output recorded as proof.
8. [Ubiquitous] `terraform/clusters/.terraform.lock.hcl` is staged and
   committed to git (it is not listed in `.gitignore` and must not be
   added there -- unlike state/vars/kubeconfigs, the lock file carries no
   secrets and must be shared so `terraform init` is reproducible for
   every future operator, including AF-tqmb's).

MANDATORY SKILLS TO REVIEW:
None identified (Terraform provider lock-file generation via `terraform
init -backend=false`; no project-specific skill covers Terraform/HCL in
this repo).

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
- 2026-08-05T15:23:06Z dep_added: blocked_by AF-4wcm
- 2026-08-05T15:23:07Z dep_added: blocks AF-tqmb
- 2026-08-05T15:30:27Z status: open -> in_progress
- 2026-08-05T15:30:27Z auto-follows: linked to predecessor AF-8ik8
- 2026-08-05T15:30:27Z claimed by dev-AF-cu83
- 2026-08-05T15:34:02Z status: in_progress -> in_progress
- 2026-08-05T15:34:02Z auto-follows: linked to predecessor AF-qujb
- 2026-08-05T15:39:37Z status: in_progress -> closed
- 2026-08-05T15:39:37Z dep_removed: no_longer_blocks AF-tqmb

## Links
- Parent: [[AF-q1il]]
- Blocked by: [[AF-4wcm]]
- Follows: [[AF-8ik8]], [[AF-qujb]]
- Led to: [[AF-pydv]]

## Comments

### 2026-08-05T15:35:05Z ada
DELIVERED: AF-cu83 -- akuity/akp provider pinned to 0.13.0 via committed lock file

Commit: 64f96629648a9938a056e1acc8a3bbf9859eafea (branch story/AF-cu83, pushed to origin)
Files changed: 1 file, +24 lines -- terraform/clusters/.terraform.lock.hcl (new, generated)
Environment: Terraform v1.15.8 on darwin_arm64

PROOF:

--- Step 1: literal AC1 command, no lock file present (confirms the float) ---
$ cd terraform/clusters && terraform init -backend=false
Initializing modules...
- cluster in modules/cluster

Initializing provider plugins...
- Finding akuity/akp versions matching "~> 0.10"...
- Installing akuity/akp v0.14.0...
- Installed akuity/akp v0.14.0 (self-signed, key ID 14B9D2131E732E01)
...
Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!

  => Reproduces the reported bug exactly: unpinned, resolves v0.14.0, one minor
     ahead of the source stack's real applied pin.

--- Step 2: pin to the source stack's applied version, re-init ---
$ rm -rf .terraform .terraform.lock.hcl
$ cp /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/.terraform.lock.hcl ./.terraform.lock.hcl
$ terraform init -backend=false
Initializing modules...
- cluster in modules/cluster

Initializing provider plugins...
- Reusing previous version of akuity/akp from the dependency lock file
- Installing akuity/akp v0.13.0...
- Installed akuity/akp v0.13.0 (self-signed, key ID 14B9D2131E732E01)
...
Terraform has been successfully initialized!

  => v0.13.0 IS still resolvable from the registry under the existing `~> 0.10`
     constraint, so AC3's primary target was met -- no fallback version needed.
     Terraform installed and checksum-verified the 0.13.0 package against the
     lock's hashes (init would have failed on a hash mismatch), so the committed
     lock is a terraform-validated artifact, not a hand-edited file.

--- Step 3: lock file content verification (AC2, AC3) ---
$ diff /Users/ada/src/github.com/adamancini/akp-infra/03-clusters/.terraform.lock.hcl ./.terraform.lock.hcl
(no output -- byte-identical to the source stack's lock)

$ grep -c '^provider "' .terraform.lock.hcl
1

$ grep -n 'version\|constraints' .terraform.lock.hcl
5:  version     = "0.13.0"
6:  constraints = "~> 0.10"

  LOCKED VERSION: registry.terraform.io/akuity/akp = 0.13.0
  Exactly one provider block. Constraint recorded as `~> 0.10` (unchanged).

--- Step 4: terraform validate with lock present, no terraform.tfvars (AC4) ---
$ ls terraform.tfvars
ls: terraform.tfvars: No such file or directory

$ terraform validate
Success! The configuration is valid.

--- Step 5: git hygiene (AC7, AC8) ---
$ rm -rf .terraform
$ ls -a terraform/clusters
.  ..  .terraform.lock.hcl  main.tf  modules  outputs.tf  providers.tf
templates  terraform.tfvars.example  variables.tf

$ git add terraform/clusters/.terraform.lock.hcl && git status --porcelain
A  terraform/clusters/.terraform.lock.hcl

$ git diff --cached --stat
 terraform/clusters/.terraform.lock.hcl | 24 ++++++++++++++++++++++++
 1 file changed, 24 insertions(+)

  Exactly one staged path. No *.tfstate*, no bare *.tfvars, no .terraform/,
  nothing under .kubeconfigs/. Lock file is not in .gitignore and was not
  added there (verified against the AF-4wcm .gitignore block, unmodified).

--- Step 6: reproducibility re-run at the committed SHA (64f9662) ---
$ terraform init -backend=false
- Reusing previous version of akuity/akp from the dependency lock file
- Installing akuity/akp v0.13.0...
- Installed akuity/akp v0.13.0 (self-signed, key ID 14B9D2131E732E01)
Terraform has been successfully initialized!
$ terraform validate
Success! The configuration is valid.
$ rm -rf .terraform && git status --porcelain
(empty -- working tree clean)

  => The committed state now pins deterministically: the same command that
     resolved v0.14.0 in Step 1 resolves v0.13.0 in Step 6. This is the
     behavior AF-tqmb's operator needs.

--- pvg verify ---
$ pvg verify terraform/clusters/.terraform.lock.hcl --format text
VERIFY: PASSED (0 files scanned, 0 issues)
exit=0
  (0 files scanned: pvg verify's substance/stub heuristics do not apply to
   generated .hcl lock artifacts; no issues reported.)

--- Pre-flight: already-landed check ---
$ git log epic/AF-q1il --oneline -n 20   # AF-4wcm merged at 50c8ab1, AF-8ik8 at fca5308
$ git ls-tree -r epic/AF-q1il --name-only | grep -i lock
(no match -- no lock file on the epic branch; work was genuinely not landed)

ACCEPTANCE CRITERIA VERIFICATION:

| AC | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| 1 | `terraform init -backend=false` from terraform/clusters/, no tfvars/backend/creds, creates .terraform.lock.hcl | PASS | Step 1 -- "Terraform has created a lock file .terraform.lock.hcl". No terraform.tfvars present (Step 4), no backend (-backend=false), no AKUITY_* credentials read. |
| 2 | Lock contains exactly one `provider "registry.terraform.io/akuity/akp"` block with a single pinned version satisfying `~> 0.10` | PASS | Step 3 -- block count 1; `version = "0.13.0"`; `constraints = "~> 0.10"`; 0.13.0 satisfies `~> 0.10`. |
| 3 | Pinned version matches source stack's 0.13.0 (else record substitute + why) | PASS | Step 2/3 -- 0.13.0 resolved and installed successfully; byte-identical `diff` against akp-infra/03-clusters/.terraform.lock.hcl. No fallback needed. |
| 4 | `terraform validate` (no tfvars) succeeds with literal "Success! The configuration is valid." after lock added | PASS | Step 4 and Step 6 -- exact string reproduced twice, pre- and post-commit. |
| 5 | No modification to providers.tf constraint, main.tf, variables.tf, outputs.tf, or modules/ | PASS | Step 5 -- `git status --porcelain` shows a single `A` (add) line, zero `M` lines. Commit diffstat: 1 file changed, 24 insertions, 0 deletions. |
| 6 | No read/copy/modify/commit of akp-infra tfstate/tfstate.backup/tfvars; no apply, no real-backend plan, no AKUITY_API_KEY_* read | PASS | Only file read from akp-infra was `03-clusters/.terraform.lock.hcl` (explicitly cited in the story's own EVIDENCE and IMPLEMENTATION sections). Commands run were limited to `terraform init -backend=false`, `terraform validate`, `terraform version`, and git/ls/grep/diff. No `terraform apply`, no `terraform plan`, no credential env vars referenced. |
| 7 | `git status` after staging shows no *.tfstate*, bare *.tfvars, .terraform/, or .kubeconfigs/ content | PASS | Step 5 -- single staged path `terraform/clusters/.terraform.lock.hcl`; `.terraform/` removed before staging; post-commit tree clean (Step 6). |
| 8 | Lock file staged and committed to git; not added to .gitignore | PASS | Commit 64f9662, pushed to origin/story/AF-cu83. .gitignore untouched (zero modified files in the commit) and does not match `.terraform.lock.hcl` -- only `terraform/clusters/.terraform/`, `*.tfstate*`, `*.tfvars` (minus `.example`), `.kubeconfigs/`. |

Zero errors, zero warnings across all commands. No DISCOVERED_BUG findings.

LEARNINGS:
- The float was real and already one minor ahead: a bare `terraform init` here
  resolved v0.14.0 while the source stack's applied state sits on v0.13.0.
  Catching this before AF-tqmb runs `terraform apply` against live demo1/demo2
  is exactly the window the story was created for -- an unpinned provider is
  invisible until the moment it silently is not.
- Pinning to a specific older version without touching the version constraint is
  best done by seeding the source stack's lock file and letting `terraform init`
  install and checksum-verify it, rather than hand-writing hashes. Terraform
  reports "Reusing previous version ... from the dependency lock file" and fails
  loudly on any hash mismatch, so the committed artifact is terraform-validated.
  Using `-upgrade`, or temporarily tightening the constraint in providers.tf,
  would both have been wrong (the former re-floats, the latter violates AC5).
- The resulting lock is byte-identical to akp-infra/03-clusters', which is the
  strongest possible evidence for AC3 -- worth doing the `diff` explicitly rather
  than just grepping the version line.
- Platform caveat for future operators: the lock carries one `h1:` hash
  (darwin_arm64) plus the full set of registry `zh:` hashes. A Linux operator's
  `terraform init` will verify against the `zh:` entries and succeed, but will
  append its own `h1:` line, producing a small lock-file diff. This matches the
  source stack's behavior exactly, so it was left as-is; if the epic later grows
  Terraform CI on linux_amd64, running
  `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` would
  pre-populate both and eliminate the churn.
- `pvg verify` reports "0 files scanned" for generated `.hcl` artifacts -- it has
  no substance heuristics for them. Clean exit here means "nothing to check", not
  "content reviewed"; the real gate for this story is `terraform validate` plus
  the lock-content assertions.
