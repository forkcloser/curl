# curl

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
- **macOS (arm64)** — same machinery, `a64` flavor (arm64-only; farcloser
  dropped Intel Mac support, so no x86_64 slice / universal binary).

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

Assets: `curl_<version>_{linux,windows}_{amd64,arm64}.tar.gz` plus
`curl_<version>_darwin_arm64.tar.gz` (no darwin/amd64), each
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

Manual bump, when needed: edit `CFW_PACKAGE`, run `just build-windows` to
prove it, then commit, tag, push.

Note the coupling: curl-for-win's tree hardcodes the curl version it builds,
so a **curl version bump needs both pins moved together** — `CFW_PACKAGE`
(Renovate's PR) *and* `CFW_COMMIT` (the human audit). A mismatch cannot ship:
the posix legs collect artifacts by version glob and fail loudly when the
pinned scripts built something other than `CFW_PACKAGE` says.

## Consuming these packages (aqua)

The release publishes GitHub Artifact Attestations for every archive, so a
consumer must verify them — a plain checksum pin would silently discard the
guarantee this repo exists to provide. This is the reference entry for a
consumer's local aqua registry: `github_artifact_attestations` is what makes
aqua verify the attestation on install, and the `checksum:` block adds the
committed-pin belt to the attestation's suspenders.

```yaml
- type: github_release
  repo_owner: forkcloser
  repo_name: curl
  description: curl with dependable TLS 1.3, first-party build (forkcloser/curl)
  asset: curl_{{trimV .Version}}_{{.OS}}_{{.Arch}}.tar.gz
  format: tar.gz
  files:
    # The binary sits in a versioned subdirectory inside the archive.
    - name: curl
      src: curl_{{trimV .Version}}_{{.OS}}_{{.Arch}}/curl
  overrides:
    - goos: windows
      files:
        - name: curl
          src: curl_{{trimV .Version}}_{{.OS}}_{{.Arch}}/curl.exe
  checksum:
    type: github_release
    asset: checksums.txt
    algorithm: sha256
  github_artifact_attestations:
    signer_workflow: forkcloser/curl/.github/workflows/release.yaml
  supported_envs:
    - darwin/arm64   # no darwin/amd64 — Intel Mac support was dropped
    - linux
    - windows
```

The authoritative copy of this entry belongs in limen's canonical
`.limen/aqua-registry.yaml` (so every repo inherits it through a limen
release), with the curl version pinned in each consumer's `aqua.yaml`; this
block is what that copy is derived from. Validate it against the **first** cut
release before relying on it — in particular that `curl.exe` on windows
resolves `curl-ca-bundle.crt` (shipped beside it in the archive) from aqua's
install layout.
