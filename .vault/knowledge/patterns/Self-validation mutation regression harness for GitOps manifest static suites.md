---
type: pattern
project: argo-fleet
status: active
actionable: pending
epic: AF-j5rz
created: 2026-08-20
---

# Self-validation (mutation-style) regression harness for static GitOps manifest suites

## Context
AF-vm0q, the epic's capstone, extended this repo's static-only Ruby e2e suite (`e2e/observability_test.rb`, no unit-test tooling exists for this manifest-only repo) with 439 new assertions across 6 sections. Simply writing assertions and watching them pass against the real manifests proves little on its own -- a suite full of vacuously-true checks looks identical to a suite full of load-bearing ones until you deliberately break something. This story's methodology, and two bugs it caught in itself, are worth reusing.

## The technique
For every assertion family meant to guard a specific known regression, introduce **exactly one** deliberate single-field defect into a scratch copy of the manifest, run the full suite, and require that the **specific named assertion** (not just "something failed") appears in the failure output -- then restore from git and re-confirm a clean `git status`. AF-vm0q ran 14 such regressions (renaming an app in one list only, deleting a `release.yaml`, hard-coding a `storageClassName`, reverting `digest:` back to `tag:`, reintroducing `overseerr`, reintroducing an `oci://`-prefixed repoURL with `chart:` removed, etc.) and recorded which assertion caught each one as delivery evidence.

Two things this caught that a pure line-count or "all assertions pass" check would have missed:
1. **A hard-coded magic number in the suite itself.** The first draft expected exactly `27` generated Application names against templates that produce `28`; the suite failed immediately against the *real* manifests. Rewriting it as a derived formula (`4 + apps * (1 + stages)`) removed the latent bug -- mutation-testing the suite surfaced a defect in the verification code, not the thing being verified.
2. **`dig_path`'s dot-splitting silently mis-parses dotted Kubernetes annotation keys.** The harness's path-digger splits on `.`, so `metadata.annotations.argocd.argoproj.io/sync-wave` fragments into four bogus segments and returns `nil` -- which reads as a *passing* absence check if the assertion is phrased the wrong way round. Every annotation this epic cares about (`argocd.argoproj.io/sync-wave`, `kargo.akuity.io/authorized-stage`) has dots in its key. Any existing `dig_path` call reaching for a dotted leaf key elsewhere in this suite is suspect and should be replaced with a helper that fetches the map and indexes it directly.

A related generalizable finding: **grepping raw text for a forbidden word false-positives on the comment that documents its absence** (`stages.yaml`'s own explanatory comment about *not* having a `verification`/`AnalysisTemplate` block trips a naive `grep -i verification`). Anchor text-level negative assertions to YAML key syntax (`/^\s*verification:/`) or assert on parsed/rendered structure instead of prose.

## Actionable guidance
- Any story adding permanent regression-guarding assertions to a static-only GitOps test suite should require, as delivery evidence, a table of deliberate single-field regressions with the specific assertion each one trips -- not just a final "all green" run. Precision matters: a regression that trips exactly one assertion (not a wall of unrelated failures) is itself evidence the suite pinpoints root cause rather than merely detecting *that* something broke.
- Audit any `dig_path`/similar dot-splitting path helper in this suite for calls against Kubernetes annotation or label keys (which routinely contain dots) -- these are a standing false-pass risk.
- When a negative assertion is a text grep, prefer anchoring to YAML key syntax over bare prose matching, especially in a codebase whose files carry heavy explanatory comments (this repo's established convention).
