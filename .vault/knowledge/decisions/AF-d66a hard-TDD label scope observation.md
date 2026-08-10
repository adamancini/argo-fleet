---
type: decision
project: argo-fleet
status: active
actionable: pending
epic: AF-d66a
created: 2026-08-10
---

# AF-d66a had zero `hard-tdd`-labeled stories and zero PM rejections -- what that implies for label scope

## Observation
None of the 7 stories/bugs in this epic (AF-ogxu, AF-c8p4, AF-d3ax, AF-j4fp, AF-qmy9, AF-7u8n, AF-mnpo) carried a `hard-tdd` label. Labels actually used: `spike`, `walking-skeleton`, `capstone`, `accepted`, `delivered`. Every one of the 7 was accepted by PM review on its first submitted delivery -- zero rejections, zero reopen-with-notes cycles. (AF-j4fp had multiple **push** denials from the permission system over an authorization-provenance question, and AF-mnpo had a **concurrent-session stop**, but neither was a PM-Acceptor rejection of the work itself.)

## Why this is worth recording, not just noting as a clean epic
This repo is GitOps-manifest-only -- there is no unit-test suite and no red/green cycle in the conventional hard-TDD sense to apply to `.yaml` files. What substituted for it across all 7 stories was a **consistent, heavy evidence discipline** that the PM independently re-derived every time rather than trusting the developer's transcript:
- Render-diff proofs (`argocd appset generate` old-vs-new, byte-identical or itemized-different)
- Counterfactual/negative controls (a deliberately-wrong config proven to fail before trusting the fix)
- Live re-verification of claims via read-only tools (`mcp__argocd-akuity__*`, direct `kubectl`) rather than accepting the developer's own commands and output as sufficient
- Explicit "live vs rendered/dry-run" honesty labeling on every claim

This produced a de facto hard-TDD-equivalent rigor (proof before acceptance, adversarial re-verification, no trust-the-developer shortcuts) without the `hard-tdd` label or a testable-code substrate to hang it on.

## Actionable guidance for future backlog/label decisions
- Do NOT mechanically expand `hard-tdd` label scope to this repo's GitOps-manifest stories on the theory that "0 rejections means it's safe to loosen rigor" -- the low rejection rate is evidence the current non-hard-tdd discipline (mandatory render-diff proofs + independent PM re-verification, not a red/green unit test) is already working, not evidence that rigor can be relaxed.
- For a **future epic that introduces actual application code** to this repo (as opposed to pure manifests), `hard-tdd` should default ON rather than being evaluated fresh -- this epic's success came from a rigor discipline that hard-TDD formalizes for code; there is no reason to expect manifest-only rigor to transfer automatically to a codebase with real logic and branches.
- If a future GitOps-manifest epic starts showing PM rejections or live-verification surprises that a render-diff proof would have caught, that is the actual trigger to reconsider whether this repo's manifest-only stories need a formal `hard-tdd`-equivalent label (e.g. a `render-diff-required` label) rather than relying on story-text discipline alone.
