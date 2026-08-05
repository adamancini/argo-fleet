---
id: AF-cu83
title: "Bug: terraform/clusters provider version unpinned after migration (v0.13.0 -> v0.14.0 float)"
status: in_progress
priority: 0
type: bug
labels: [discovered-by-pm, delivered]
parent: AF-q1il
created_at: 2026-08-05T15:22:58Z
created_by: ada
updated_at: 2026-08-05T15:34:02Z
content_hash: "sha256:41577107a258f7f7579e02eebbfc2c48e60819e99e457cf19b0ad308cc39ed40"
blocked_by: [AF-4wcm]
blocks: [AF-tqmb]
assignee: dev-AF-cu83
follows: [AF-8ik8, AF-qujb]
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


## History
- 2026-08-05T15:23:06Z dep_added: blocked_by AF-4wcm
- 2026-08-05T15:23:07Z dep_added: blocks AF-tqmb
- 2026-08-05T15:30:27Z status: open -> in_progress
- 2026-08-05T15:30:27Z auto-follows: linked to predecessor AF-8ik8
- 2026-08-05T15:30:27Z claimed by dev-AF-cu83
- 2026-08-05T15:34:02Z status: in_progress -> in_progress
- 2026-08-05T15:34:02Z auto-follows: linked to predecessor AF-qujb

## Links
- Parent: [[AF-q1il]]
- Blocks: [[AF-tqmb]]
- Blocked by: [[AF-4wcm]]
- Follows: [[AF-8ik8]], [[AF-qujb]]

## Comments
