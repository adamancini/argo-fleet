# argo-fleet

GitOps repo for personal services managed by Argo CD + Kargo, migrating off
Flux (`fleet-infra`) one app at a time. Currently targets `demo1`/`demo2`
(the same Akuity-hosted Argo CD/Kargo instance used by `akp-platform`) as a
staging ground before the eventual move to the real `annarchy.net`/
`staging.annarchy.net` clusters.

## Layout

- `bootstrap/` — the one manifest you apply by hand
  (`bootstrap/platform-aoa.yaml`); everything else is discovered
  automatically from `infrastructure/*/argocd` and `apps/*/{argocd,kargo}`.
- `infrastructure/` — cluster-wide dependencies with no promotion pipeline
  (currently: Sealed Secrets).
- `apps/` — tenant apps, each with a full Kargo `dev → staging → prod`
  pipeline. See [`docs/onboarding.md`](docs/onboarding.md) for the pattern.
- `Taskfile.yml` — repeatable operational commands (`task --list`).

## Quickstart

1. `task sealed-secrets:generate-keypair` — generates the shared Sealed
   Secrets keypair used by every cluster in this repo (see
   [`infrastructure/sealed-secrets/README.md`](infrastructure/sealed-secrets/README.md)).
2. `argocd app create -f bootstrap/platform-aoa.yaml` — the only manifest
   applied by hand; bootstraps everything else.
3. Add Kargo git write credentials for each project (`akkoma`, `soju`) —
   same pattern as `akp-platform`'s `add-credentials.sh`.
4. Promote via the Kargo UI/CLI once Freight is discovered.
