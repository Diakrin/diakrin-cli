# Diakrin CLI releases

Public releases of the `diakrin` command-line interface. This repository holds release artifacts only; the source is built by Diakrin's release workflow.

## Install (macOS and Linux)

```sh
curl -fsSL https://diakrin.com/cli/install.sh | sh
```

Then sign in to your company's Diakrin:

```sh
diakrin auth login --host <your company address>
```

The command holds no access of its own. It does nothing until you sign in, and your company's Diakrin decides what you may do. Windows is not supported yet. More: <https://diakrin.com/cli>.

## What each release contains

- `diakrin-<version>-<os>-<arch>.tar.gz` for `darwin-arm64`, `darwin-x64`, `linux-x64` and `linux-arm64`. Each bundles the official Node.js runtime, so nothing else is needed.
- `SHA256SUMS`: checksums the installer enforces before unpacking anything.
- `SHA256SUMS.sigstore.json`: a Sigstore keyless signature over `SHA256SUMS`, made by the release workflow and recorded in the public Rekor log.
- `install.sh`, `VERSION`, `LICENSE`.

## Verify a release

```sh
cosign verify-blob SHA256SUMS --bundle SHA256SUMS.sigstore.json \
  --certificate-identity https://github.com/Diakrin/diakrin-platform/.github/workflows/cli-release.yml@refs/tags/cli-v<version> \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
sha256sum --check --ignore-missing SHA256SUMS
```

With `cosign` installed, the installer runs this check automatically. Set `DIAKRIN_REQUIRE_SIGNATURE=1` to make it mandatory.

## Licence and security

The CLI is licensed under [LICENSE](LICENSE). Report security issues to contact@diakrin.com.
