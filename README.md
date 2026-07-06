# build-curl

First-party curl packages for the farcloser toolchain — one `curl` for every
platform, pinned and verified through aqua like everything else. Exists
because the baseline requires a curl with dependable TLS 1.3 everywhere, and
no single trustworthy upstream channel covers all our platforms (see
`book/tooling.md` in [limen](https://github.com/farcloser/limen), "Tools
without upstream binaries").

Everything traces to [curl-for-win](https://github.com/curl/curl-for-win),
the curl project's own reproducible-build system:

- **windows (amd64, arm64)** — *imported, not built*: curl-for-win's windows
  packages are the official curl builds. CI downloads them from curl.se,
  verifies each sigstore bundle against the **vendored** `cosign.pub.asc`,
  and repackages. The key was vendored from the pinned commit and
  cross-checked against the copy embedded in their README at that commit.
- **linux (amd64, arm64)** — static (musl) builds produced by curl-for-win's
  build scripts at the same audited pin, run in our CI.
- **macOS (universal → amd64 + arm64)** — same machinery, `macuni` flavor.

All pins live in `versions.env`: the upstream curl version, curl-for-win's
windows build revision, and the curl-for-win commit (which is also the
provenance of the vendored key — bumping it means re-auditing their scripts
and re-cross-checking the key).

## Releasing

Tag `v<CURL_VERSION>` (or `v<CURL_VERSION>.<n>` for a rebuild without an
upstream bump — a 4th segment, never a `-suffix`: semver sorts `X.Y.Z-1`
*before* `X.Y.Z`). The release workflow builds/imports every leg, generates
GitHub Artifact Attestations for every archive (aqua verifies these on
install), and publishes with a `checksums.txt` for aqua's checksum pinning.

Assets: `curl_<version>_{darwin,linux,windows}_{amd64,arm64}.tar.gz`, each
containing the `curl` binary (plus `curl-ca-bundle.crt` on windows, where
curl expects the CA bundle beside the executable) and the curl `COPYING`.

## Version bumps

Renovate watches the curl.se download index directly (a custom HTML
datasource — the `dl-<version>_<rev>/` hrefs carry the package token) and
PRs bumps to `CFW_PACKAGE` in `versions.env`. CI runs the import on every
PR, so a bump can only go green if the package exists on curl.se *and* its
sigstore bundle verifies against the vendored key. Merging and tagging stay
human acts, as does `CFW_COMMIT` (bumping the build-script pin means
re-auditing the scripts and re-cross-checking the key — never automated).

Manual bump, when needed: edit `CFW_PACKAGE`, run `just import-windows` to
prove it, then commit, tag, push.
