---
type: pattern
project: argo-fleet
status: active
actionable: pending
epic: AF-d66a
created: 2026-08-10
---

# `argocd appset generate` render-diff is a strong, cheap primitive for proving GitOps changes are no-ops

## Context
Across AF-ogxu, AF-c8p4, AF-d3ax, AF-j4fp, and AF-mnpo, the epic repeatedly needed to answer "does this manifest change actually change what gets deployed?" without a unit-test suite (this is a pure GitOps manifest repo). The same technique answered that question every time, cheaply and conclusively.

## The technique
`argocd appset generate <file.yaml> -o json --grpc-web` is a server-side dry-run RPC: it renders an ApplicationSet's generator against the **real, live cluster inventory** and returns the resulting `Application` specs, without ever creating, updating, or deleting anything. Because it never persists, any "no leftovers" acceptance criterion is satisfied **by construction**, not by cleanup discipline.

Render BOTH the old and new version of a file and diff the full JSON output (not just names/destinations -- the entire rendered spec):

```bash
argocd appset generate infrastructure/sealed-secrets/argocd/appset.yaml@HEAD    -o json --grpc-web > old.json
argocd appset generate infrastructure/sealed-secrets/argocd/appset.yaml@story/X -o json --grpc-web > new.json
diff -u old.json new.json   # byte-identical => the change is a true no-op
```

This turned "this generator migration should be a no-op" from an assertion into a proof across all 5 pre-existing infra apps in one pass (AF-c8p4), and was reused identically to validate AF-mnpo's `ignoreDifferences` fix and AF-d3ax's chart-config choices.

## Complementary techniques used alongside it in this epic
- **Positive/negative controls**: e.g. rendering a deliberately-wrong bare `clusters: {}` (no selector) as a counterfactual to prove the selector is load-bearing, not decorative -- confirms the test can fail, not just that it happens to pass.
- **Necessity+sufficiency proof for `ignoreDifferences`**: `jqPathExpressions` compile to `del(<expr>)` server-side (`util/argo/normalizers/diff_normalizer.go`); running that exact `del()` against a live object offline and diffing against the git spec proves a proposed ignore-list is neither too narrow (misses real defaulting) nor too broad (masks real drift) before ever touching a live cluster.
- **Live-vs-rendered honesty statements**: when the tracked branch has not yet merged, say so explicitly and label every claim as "live" vs "rendered/dry-run" rather than letting a render-time proof pass as a live-state claim (AF-7u8n's capstone did this rigorously; worth requiring by default).

## Actionable guidance
- Reach for `argocd appset generate` (or the `mcp__argocd-akuity__*` MCP tools where available) as the default verification tool for ANY ApplicationSet template/generator change in this repo, before reaching for a real `kubectl apply`.
- When a change is claimed to be a no-op, require the render-diff proof (or an equivalent byte-level comparison) as delivery evidence, not just "I reviewed the diff and it looks equivalent."
- Note the tool's own JSON-shape footgun: `argocd appset generate -o json` emits a bare object for a single result and an array for multiple -- a naive `jq 'if type=="array"'` guard can silently misreport a single-result branch as an error. Guard both shapes explicitly (this cost AF-ogxu a wasted cycle).
