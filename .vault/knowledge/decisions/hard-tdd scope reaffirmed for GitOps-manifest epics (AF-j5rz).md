---
type: decision
project: argo-fleet
status: active
actionable: pending
epic: AF-j5rz
created: 2026-08-20
---

# hard-tdd scope: AF-j5rz reaffirms exclusion for GitOps-manifest-only epics, and shows what actually substitutes for it

## Decision context
AF-j5rz's own epic body explicitly cited the prior epic's retro (`.vault/knowledge/decisions/AF-d66a hard-TDD label scope observation.md`) and deliberately labeled none of its 11 stories `hard-tdd`, reasoning that "rigor instead comes from render-diff proofs, negative controls, and independent re-verification." This epic is a second, independent data point on that decision, and it's a strong one: **this was the highest real-defect-rate epic in this repo's history (4 distinct production-consequential bug classes: digest/tag field, git-files param-path, OCI-source `chart:` field, and upstream image retirement, plus a missing onboarding step), and all of them were caught -- none reached a permanently broken state -- without any hard-tdd story.**

## What actually caught the bugs, in place of unit-test-style TDD
- The digest-vs-tag and param-path bugs were caught by a developer **reading the consumer chart's own template source** (`_imageSpecificationToImage.tpl`) and the generator's own documented param-exposure rule, then proving the fix with **counterfactual rendering** (rendering the wrong binding and watching a real tool reject it) plus a **machine-check across every real seeded file** -- none of which is "write a failing test first," because there is no executable code in this repo to unit-test, only manifests.
- The OCI `chart:` field bug was caught only by a **real Argo CD control plane's own admission-time validation**, live -- no amount of `helm template`/YAML static checking could have caught it, because the defect was in a schema Argo CD itself enforces at apply-time, not in Helm's rendering. This is a genuine limitation of static-only verification for this repo's manifest-only content, not a gap hard-tdd would have closed either (hard-tdd would still need the same live admission check to catch this class of bug).
- The image retirement bug was caught by a developer refusing to guess/fake a digest for an unresolvable image and escalating instead of silently working around it -- a discipline/process behavior, not a testing methodology.
- The static capstone (AF-vm0q) used **mutation-style self-validation** (deliberately reintroducing each of the 3 production bugs plus 11 others into a scratch copy and confirming a named assertion catches each) as its own rigor mechanism -- closer in spirit to hard-tdd's "prove the test can fail" discipline than to hard-tdd's "write the test before the code" discipline, and it caught two additional real defects in the test suite itself (a hard-coded count, a dotted-annotation-key parsing bug) that a simple "assertions pass" check would have missed.

## Actionable guidance
- **Continue excluding `hard-tdd` from GitOps-manifest-only stories in this repo.** Two epics in a row now show it isn't the mechanism that would have caught this repo's real defects, because there's no unit-testable code path for it to exercise.
- **Formalize the actual substitute discipline** (this epic makes a strong case for writing it up as its own convention, separate from this note): for any story binding a value produced by one component into a field consumed by another (Kargo Warehouse -> app-template, git-files generator -> template params), require (a) reading the consumer's actual template/schema source, not just the producer's docs, and (b) a counterfactual/negative-control render proving the wrong binding is rejected -- and for any spec validated by a live control plane rather than by rendering, require a live check as an explicit story gate, not an assumption that static passing implies live-valid.
- For any future capstone/static-verification story in this repo, keep requiring mutation-style self-validation (deliberate regression -> named-assertion-catches-it) as delivery evidence -- in this epic alone it caught two real defects in the verification code itself (a hard-coded magic number, a dotted-key parsing bug), which is exactly the failure mode a rubber-stamp "all green" run would hide.
