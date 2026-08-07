---
id: AF-7u8n
title: "Verify the observability stack end-to-end across the fleet"
status: open
priority: 1
type: task
labels: [capstone]
parent: AF-d66a
created_at: 2026-08-07T15:06:17Z
created_by: ada
updated_at: 2026-08-07T15:06:17Z
content_hash: "sha256:c9671019e47b25cc8d12c4da1ce1693115a11197caea088f72cd0357f3b448e6"
---

## Description
Description:
End-to-end acceptance check for the whole epic: confirm Prometheus + Grafana + Alertmanager are running and healthy on every registered workload cluster, Grafana is reachable externally with real (sealed-secret) credentials, Prometheus's storage is bound and actually collecting metrics, and all 5 migrated infra apps plus the new kube-prometheus-stack app remain healthy under the new generator convention -- as one demoable pass, not five separate spot-checks.

Context:
This is the epic's capstone: it does not introduce new code, it proves the whole epic actually delivers what was asked -- "add Grafana and Prometheus to our infrastructure dependencies for all clusters," reachable, with the generator migration applied consistently. Everything it verifies was already built by the other 5 stories in this epic; this story's only job is to run the fleet-wide check and record the result, catching anything that passed its own story's narrower verification but breaks when everything is combined (e.g., the generator migration accidentally affecting the new kube-prometheus-stack app, or the Grafana HTTPRoute breaking after a later change to one of the 5 migrated files).

USER INTENT:
The user's original ask ends with "just get the stack running and reachable" -- this story is the concrete proof that happened, across the whole fleet, not just in isolation per-story. It also re-confirms the 5 pre-existing infra apps (sealed-secrets, traefik-gateway, gateway-api-crds, openebs-localpv, argo-rollouts-crds) are still healthy after their generator migration -- the user was explicit that this migration must not silently break anything that was already working.

IMPLEMENTATION:
1. `argocd app list` (or `mcp__argocd-akuity__list_applications` if available in the executing environment): confirm every infra `Application` -- `sealed-secrets-*`, `traefik-gateway-*`, `gateway-api-crds-*`, `openebs-localpv-*`, `argo-rollouts-crds-*`, `kube-prometheus-stack-*` -- is `Synced`/`Healthy` on both `demo1` and `demo2` (or whatever cluster set the confirmed generator discovers at verification time).
2. `kubectl get pvc -n monitoring` on both clusters: Prometheus's PVC is `Bound`.
3. Open Prometheus's own UI (`kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090`, browse `/targets`) and confirm at least the in-cluster targets (kube-state-metrics, node-exporter, Prometheus itself) show as `UP` -- this is the concrete proof that "just running" actually means collecting real metrics, not just that pods exist.
4. Run the exact `curl`/Host-header command documented in the HTTPRoute story's delivery notes against both `demo1` and `demo2`, confirm Grafana's login page returns, then log in with the sealed-secret credentials from the kube-prometheus-stack story and confirm the built-in Prometheus datasource shows data (e.g. the default "Grafana / Prometheus" or any bundled dashboard rendering real metrics, without creating any NEW dashboard -- viewing what the chart ships by default is sufficient and stays within this epic's "no custom dashboards" scope).
5. Record the full pass/fail result, with the actual commands run and their output, as this story's delivery evidence.

KEY FILES:
None modified -- this is a verification-only story. Reference: every file produced by the other stories in this epic.

OUT OF SCOPE:
- Fixing anything found broken -- if this story finds a regression, it reopens/blocks on the relevant upstream story rather than silently patching it here, so the fix gets proper story-level acceptance review.
- Any new functionality -- this story adds nothing; it only verifies.

DIFF BUDGET:
0 files changed.

CONSUMES:
- (spike story id): decision record -> confirmed generator convention (verification baseline)
- (migration story id): 5 migrated appset.yaml files -> Synced/Healthy status expected
- (kube-prometheus-stack story id): kube-prometheus-stack appset.yaml + SealedSecret -> Synced/Healthy status, bound PVC, working Grafana login expected
- (HTTPRoute story id): grafana-httproute.yaml -> documented curl verification command, expected to still pass
- (docs story id): docs/infra-dependencies.md -> confirmed to match actual repo state (spot-check, not a runtime dependency)

PRODUCES:
None (verification-only; result recorded as this issue's own comment/notes, not a repo artifact).

TESTING:
This entire story IS the testing/verification pass -- see IMPLEMENTATION above. No further test plan beyond what's listed there.

Acceptance Criteria:
1. [Ubiquitous] All 6 infra Applications (5 migrated + kube-prometheus-stack) are `Synced`/`Healthy` on every cluster the confirmed generator discovers.
2. [Ubiquitous] Prometheus's PVC is `Bound` on every cluster.
3. [Event] Prometheus's `/targets` page shows in-cluster scrape targets as `UP`.
4. [Event] Grafana's documented external-reachability command still succeeds, and logging in with the sealed-secret credentials succeeds.
5. [Event] Grafana's bundled default dashboard/datasource renders real metrics data (not an empty/error panel).
6. [Unwanted] No custom dashboard, alerting rule, or storage-sizing change is introduced as part of this verification story.
7. Any regression found is recorded and linked back to the responsible upstream story, not silently fixed here.

MANDATORY SKILLS TO REVIEW:
devops-toolkit:akp-platform

## Acceptance Criteria


## Design


## Notes


## History


## Links
- Parent: [[AF-d66a]]

## Comments
