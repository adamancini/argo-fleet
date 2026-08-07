# Adding a cluster-wide infra dependency

Use this for anything that needs to run identically on every cluster and
has no per-app promotion pipeline -- a controller, an operator, a
cert-manager-style singleton. `sealed-secrets` is the current example.

## Steps

1. Create `infrastructure/<name>/argocd/appset.yaml`. Use a `clusters`
   generator so cluster targeting is discovered rather than hardcoded --
   there's no per-cluster directory to discover, and a third workload
   cluster then needs no file edits:

   ```yaml
   generators:
   - clusters:
       selector:
         matchExpressions:
         - key: akuity.io/argo-cd-cluster-name
           operator: NotIn
           values: [in-cluster, kargo]
   ```

   The selector is mandatory. A bare `clusters: {}` also matches
   `in-cluster` (the Akuity control plane, which only permits the
   `argocd` namespace) and `kargo`, silently broadening the app's
   targeting -- confirmed against the live instance, not theoretical.
   Template `{{name}}` for both `metadata.name` and
   `spec.destination.name`. Do not use `{{server}}`: on this
   Akuity-hosted instance it resolves to an internal proxy URL such as
   `http://cluster-demo1:8001`, not a reachable API server endpoint.
   `infrastructure/sealed-secrets/argocd/appset.yaml` is the worked
   example.
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
