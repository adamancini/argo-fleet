# argo-rollouts-crds — cluster-wide dependency, no promotion pipeline

Installs the [Argo Rollouts](https://argo-rollouts.readthedocs.io/) CRDs
(`AnalysisTemplate`, `AnalysisRun`, `ClusterAnalysisTemplate`, `Rollout`,
`Experiment`) at `v1.9.0` -- matching the version of the
`kargo-rollouts-<cluster>` analysis controller Akuity's self-hosted Kargo
agent already deploys per shard (`terraform/clusters/modules/cluster/main.tf`,
`akp_kargo_agent` with `akuity_managed = false`).

That controller runs with `--controllers=analysis`, ready to reconcile
`AnalysisRun`s, but the CRDs it watches aren't bundled with it. Per Kargo's
own Helm chart docs (`api.rollouts.integrationEnabled`), the Kargo API
server does a startup sanity check for these CRDs and silently disables the
Rollouts/verification integration if they're not found -- so any `Stage`
with a `spec.verification` block referencing an `AnalysisTemplate` is a
no-op without this.

## Ordering

`argocd.argoproj.io/sync-wave: "-1"` makes Argo CD sync this Application's
resources before wave-0 (default) Applications on the same cluster,
including any app's Kargo-managed `AnalysisTemplate` resources -- so the
CRDs land first, same rationale as `gateway-api-crds`.

## Job-based verification and agent hosting mode

Akuity's docs warn that "AnalysisTemplates/AnalysisRuns that use Kubernetes
Jobs will never complete if the agent is Akuity Platform-managed" -- that
doesn't apply here: this fleet's Kargo agents are explicitly self-hosted
(`akuity_managed = false`), which is required for and supports Job-based
verification providers.
