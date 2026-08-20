---
type: convention
project: argo-fleet
status: active
actionable: pending
epic: AF-j5rz
created: 2026-08-20
---

# New Kargo project onboarding checklist item was documented but never enforced as a story

## What happened
`AGENTS.md`'s own onboarding checklist explicitly calls out "new Kargo project -> new git write credentials for it" (`kargo create repo-credentials`) as a required step. Despite this, none of the 6 new Kargo projects this epic created (sonarr/radarr/lidarr/bazarr/prowlarr/seerr) had git write credentials registered -- unlike `akkoma`/`soju`, which already had per-project github-creds registered 14 days prior to this epic.

This was not caught by any static check, any developer story, or either of the earlier human-gated live-verification stories (AF-o0rw, AF-c17x) -- it was discovered only at AF-4wkn, the epic's final live-promotion proof, when `kargo promote`'s git-push step failed: `fatal: could not read Username for https://github.com: No such device or address`. The user registered credentials live and a second promotion attempt succeeded.

## Why it slipped through
No story in this epic's backlog had "register git write credentials for the N new Kargo projects" as an explicit acceptance criterion or task, even though the epic created 6 brand-new Kargo `Project` objects and `AGENTS.md` documents this as a required step for exactly that situation. The checklist existed; nothing in the backlog-authoring process cross-checked new-Kargo-project-creating stories against it.

## Actionable guidance
- **When Sr PM authors a backlog for any epic that creates one or more new Kargo `Project` objects, add an explicit story/AC for registering that project's git write credentials (`kargo create repo-credentials`)**, sourced directly from `AGENTS.md`'s onboarding checklist -- do not rely on a human-gated live story to surface the gap only when a real promotion is attempted.
- More generally: this repo's `AGENTS.md` onboarding checklist should be treated as a literal per-story or per-epic cross-check at backlog-authoring time for any epic that adds a new app/project/environment, not just background reading -- a checklist item that exists in a doc but isn't wired into backlog creation is equivalent to not existing, as this epic demonstrates.
