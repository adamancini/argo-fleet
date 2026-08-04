# Adding a cluster-wide infra dependency

Use this for anything that needs to run identically on every cluster and
has no per-app promotion pipeline -- a controller, an operator, a
cert-manager-style singleton. `sealed-secrets` is the current example.

## Steps

1. Create `infrastructure/<name>/argocd/appset.yaml`. Use a `list`
   generator with one element per cluster destination -- there's no
   per-cluster directory to discover, just a fixed, known set of clusters
   (currently `demo1`, `demo2`).
2. Write `infrastructure/<name>/README.md` explaining what it is, why every
   cluster needs it, and any bootstrap step required before the
   ApplicationSet can sync cleanly (e.g. `sealed-secrets` needs its shared
   keypair pre-created and labeled `active` before the controller starts,
   or it generates its own cluster-specific key instead).
3. If the dependency needs repeatable operational commands (key rotation,
   cert renewal, anything you'd otherwise hand-run and forget the exact
   flags for), add them to the root `Taskfile.yml` under a
   `<name>:<verb>` namespace, matching `sealed-secrets:generate-keypair`/
   `sealed-secrets:rotate-keypair`/`sealed-secrets:seal`.
4. No changes to `bootstrap/` -- `infra-apps.yaml` already discovers
   `infrastructure/*/argocd` automatically.

## Candidates already identified but deferred

- **cert-manager**: deferred until real domains exist for `akkoma`/`soju`
  -- no TLS to issue yet, so installing it now would just be an untested,
  unused dependency.
