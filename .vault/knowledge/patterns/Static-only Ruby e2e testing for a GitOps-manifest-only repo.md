---
type: pattern
project: argo-fleet
status: active
actionable: pending
epic: AF-d66a
created: 2026-08-10
---

# Static-only Ruby e2e testing for a GitOps-manifest-only repo, self-validated by mutation

## Context
`argo-fleet` had zero e2e test tooling and zero CI before this epic. The epic's completion gate required an e2e test, but there is no application code, no test framework, and (critically) no cluster available in CI on the critical path. `e2e/observability_test.rb` (150 assertions, 9 sections) is the resulting pattern -- worth reusing for the next epic's completion gate rather than re-deriving.

## Why "e2e" means static-only here
This is a pure GitOps manifest repo: Argo CD ApplicationSets and plain Kubernetes YAML. "End to end" is redefined as: assert the committed manifests describe a coherent, deployable system, end to end -- including the **cross-file contracts** that only otherwise break at runtime (e.g. the Grafana HTTPRoute's backend Service name matching what the chart's `helm.releaseName` actually derives, or its `parentRef` matching the Gateway name the Traefik chart actually creates). Every one of those cross-file contracts is statically decidable from the YAML; the test decides them without a live cluster.

## Why Ruby, specifically, and not shell
Two hard constraints converged on Ruby, not preference:
1. `pvg verify --check-e2e` only scans recognized source-file extensions -- a `.sh` file is invisible to that gate regardless of path or name, so a shell script literally cannot satisfy the epic completion gate.
2. This repo has zero test tooling installed and no lockfile/dependency-management convention for one. A test that needs `yq`/`jq`/PyYAML is a test that silently stops running on a machine that lacks them. Ruby ships with `YAML` and `JSON` in its standard library on both a stock macOS workstation and a stock CI runner, so the test has **zero external dependencies**.

## Structural choices worth reusing
- **Accumulate-and-report, not fail-fast**: every assertion runs regardless of earlier failures, so one CI run surfaces the whole blast radius instead of just the first broken thing.
- **Glob-discovered expected-set, not hard-coded file list**: `EXPECTED_INFRA_APPS` cross-checks that the glob discovers exactly the expected set, so a new infra dependency (or a silently deleted one) is caught by the same test that checks generator consistency -- the glob can't quietly degrade into vacuous success.
- **Semantic assertions over exact-match where the exact value is expected to grow**: the selector check asserts `NotIn` + "contains both in-cluster and kargo" rather than exact array equality, so excluding a third cluster later is not a spurious failure.
- **Cross-file contract section as the highest-value section**: section 6 (HTTPRoute backend name vs chart releaseName, HTTPRoute parentRef vs Gateway name/namespace, ignoreDifferences target vs actual HTTPRoute name/namespace, SealedSecret key names vs chart-referenced key names) is exactly the class of bug that a single-file lint/schema check cannot catch and that this epic's live verification stories (AF-j4fp, AF-7u8n, AF-mnpo) had to discover by hand, repeatedly, against real clusters.
- **Unbuffered stdout/stderr** (`$stdout.sync = $stderr.sync = true`): Ruby line-buffers stdout only when it's a TTY, so a CI redirect of both streams to one file can interleave a buffered PASS with an unbuffered FAIL mid-line, corrupting a line-oriented log scrape. Sync both explicitly.

## Self-validation technique: mutation testing the test itself
Before trusting the suite, 25 deliberate single-field regressions were each introduced against a scratch copy of the manifests and each confirmed caught by the expected assertion (not just "some assertion failed" -- the specific one). This is the cheap, low-ceremony version of mutation testing and is the right bar for "does this test suite actually work" when there is no coverage tool for YAML assertions. Worth requiring as a matter of course for any future static/structural test suite in this repo.

## Actionable guidance
- Reuse `e2e/observability_test.rb`'s harness (assert helpers, `dig_path`, `doc`/`raw` caching) as the base for the next epic's completion-gate e2e test rather than writing a new one from scratch -- extend it with a new section, don't fork it.
- Any future epic that introduces a new infra dependency or cross-file contract should add both a positive assertion AND a stray/regression guard (see e2e section 9's "no cluster-bound objects under the wrong glob" check) -- single-direction assertions miss the "someone added something they shouldn't have" class of regression.
- Require the mutation-testing self-check (or an equivalent) as delivery evidence any time a new static/structural test file is added, not just "150 assertions, all green."
