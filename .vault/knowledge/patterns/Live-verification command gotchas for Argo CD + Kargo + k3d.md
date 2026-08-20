---
type: pattern
project: argo-fleet
status: active
actionable: pending
epic: AF-j5rz
created: 2026-08-20
---

# Live-verification command gotchas for the Argo CD + Kargo + k3d demo environment (AF-j5rz)

## Context
AF-j5rz's three human-gated live stories (AF-o0rw, AF-c17x, AF-4wkn) surfaced several environment- and command-level gotchas that cost re-work or produced misleading results the first time. Captured here so future live-verification runbooks in this repo don't rediscover them.

## Gotchas

- **`argocd appset generate`'s dry-run output can race ahead of the repo-server's own git refresh.** After a real Kargo promotion pushed a commit, the first `argocd appset generate ... -o json --grpc-web` render-diff capture returned a stale snapshot (matched the pre-promotion state). Recapturing ~45 seconds later returned the correct post-promotion render. Any before/after render-diff proof around a just-pushed commit should tolerate one stale capture and retry rather than treating a no-diff result as immediate proof of failure.
- **`kargo promote` needs `--freight-alias`, not `--freight`, when specifying a human-readable alias** (e.g. `veering-ibex`). `--freight` expects a Freight name/hash and returns a misleading 404 rather than a usage error when given an alias -- easy to misdiagnose as "the freight doesn't exist" when it's actually a flag-name mismatch.
- **Argo CD session tokens expire mid-session** and need re-login (`task argocd:login` in this repo's Taskfile) -- a stale-token error mid-runbook is not a sign of a broken instance.
- **k3d clusters need to be manually restarted** (`k3d cluster start <name>`) after a Docker Desktop restart, and **a k3d cluster's kubeconfig port changes on every restart** -- run `k3d kubeconfig merge --kubeconfig-merge-default` (or equivalent) after every restart, or `kubectl` commands against that context will fail with a stale-port connection error that looks like the cluster is down rather than just unreachable via a stale kubeconfig.
- **The `kargo` Argo CD "destination" is not a separate kubectl-reachable cluster at all** -- it's Akuity's own managed Kargo control-plane hosting (confirmed via `terraform output` showing `kargo_hostname` as a distinct `akuity.cloud` endpoint with `kargo_agent_ids` registered against demo1/demo2). Kargo objects (`Project`/`Warehouse`/`Stage`) must be inspected via the `kargo` CLI (`kargo get project/warehouse/stage`), never `kubectl --context kargo` -- there is no such kubeconfig context to begin with.

## Actionable guidance
- Any future runbook or human-gated story touching this shared instance should link this note (or fold its contents directly into the story's STEPS) rather than re-deriving these gotchas live under time pressure.
- Specifically: prefer `--freight-alias` by default in any `kargo promote` example/snippet written into a future story, and note the recapture-after-a-short-wait pattern explicitly in any render-diff-based promotion proof.
