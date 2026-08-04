# sealed-secrets — cluster-wide dependency, no promotion pipeline

Installs the [Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
controller on every cluster in `argocd/appset.yaml`'s `list` generator
(`demo1`, `demo2`). Unlike everything under `apps/`, this has no Kargo
pipeline -- it's a singleton that needs to exist identically everywhere,
not something with distinct dev/staging/prod versions.

## Shared keypair

All clusters use the **same** RSA keypair rather than each controller
generating its own, so a SealedSecret sealed once decrypts on every
cluster running this controller -- including `annarchy.net`/
`staging.annarchy.net` once those eventually join. See the repo root
`Taskfile.yml`:

```bash
task sealed-secrets:generate-keypair   # one-time setup
task sealed-secrets:rotate-keypair     # if the key is ever compromised
task sealed-secrets:seal -- <namespace> <name> <output-path> <key>=<value>...
```

The private key lives at `.sealed-secrets-keypair/tls.key` locally
(gitignored) -- back it up out-of-band. Losing it means every existing
SealedSecret becomes permanently undecryptable.

## Why not each cluster generating its own key

The default behavior (each controller generates a cluster-specific
keypair on first start) would mean re-sealing every secret by hand when
`annarchy.net`/`staging.annarchy.net` eventually join this repo. Bringing
one shared key avoids that at the cost of a slightly larger blast radius
if the key is ever compromised -- acceptable here since these clusters are
environments for the same services, not isolation boundaries.
