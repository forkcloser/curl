# curl

First-party curl packages for the toolchain — one `curl` for every
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
  `_build.sh` at the same audited pin, run in our CI inside a debian image
  pinned by digest, with apt from snapshot.debian.org at a pinned timestamp
  and the compiler from a pinned LLVM release (`pins.yaml`, verified through
  LLVM's release attestation): every input to a build is a pin, and two runs
  of one commit see the same packages and the same compiler.
- **macOS (arm64)** — same machinery, `a64` flavor (arm64-only; Intel Mac
  support was dropped, so no x86_64 slice / universal binary), built with
  Apple's clang as curl-for-win builds its own mac packages.
  This leg's inputs are not all pins. The compiler, the SDK and the rest of
  Apple's toolchain are those of the Xcode (or Command Line Tools) the
  machine has selected, and whatever else the build runs from `/usr/bin` is
  the machine's too. `cmake` and `ninja` are pinned tools
  (`.hermetic/hermetic.yaml`). Homebrew's directory is not on the build's
  PATH; two of the machine's tools are, each by name: `gpg`, which checks
  the signatures of the sources, and `brew`, which curl-for-win's
  `_build.sh` asks for Homebrew's prefix. With that prefix `_build.sh`
  reaches a third by its path: where Homebrew holds `llvm`, its `llvm-strip`
  strips the static libraries curl is linked from, and where it does not
  they are left unstripped, as on CI's runner. Its `_ci-mac-homebrew.sh`, which
  installs `gnu-tar` and `jq` with Homebrew, is not run: the build uses this
  repository's pinned `gtar` and `jq`. The darwin curl of v8.23.0.1 and of the
  three CI builds compared with it is one binary; nothing holds that from
  one runner image to the next.

The pins live in `versions.env` (the upstream curl version, curl-for-win's
windows build revision, the curl-for-win commit — which is also the
provenance of the vendored key, so bumping it means re-auditing their scripts
and re-cross-checking the key — and the linux legs' image, suite and apt
snapshot) and in `pins.yaml` (the LLVM release). What this repository changes
about curl-for-win's own scripts is listed, whole, in `UPSTREAM.md`.

## Releasing

Tag `v<CURL_VERSION>` (or `v<CURL_VERSION>.<n>` for a rebuild without an
upstream bump — a 4th segment, never a `-suffix`: semver sorts `X.Y.Z-1`
*before* `X.Y.Z`). The release workflow builds/imports every leg, generates
GitHub Artifact Attestations for every archive (aqua verifies these on
install), and publishes with a `checksums.txt` for aqua's checksum pinning.

An archive is the same bytes whenever it is built from the same commit with
the same tools (`archive.sh`: entries sorted, the commit's time, owner 0).
Two CI runs of one commit give the same five archives, and
`PACKAGE_VERSION=<version> just build-windows` at the tag of a release after
v8.23.0.1, on linux or macOS, gives the two windows archives its
`checksums.txt` lists. A Windows host records other file modes, and so other
bytes for the same content.

Assets: `curl_<version>_{linux,windows}_{amd64,arm64}.tar.gz` plus
`curl_<version>_darwin_arm64.tar.gz` (no darwin/amd64), `<version>` the tag's
(the pinned curl's, with a fourth segment for a rebuild of the same curl), each
containing the `curl` binary, the curl `COPYING`, curl-for-win's
`BUILD-MANIFEST.txt` (the libraries that curl links, statically, and their
versions) and each of those libraries' licence under `licenses/<library>/`,
as curl-for-win's own package carries them (and, in the linux archives,
musl's own `COPYRIGHT` under `licenses/musl/`: the curl is static, so the C
library is in the binary, and curl-for-win's package has no licence for it;
in the windows ones, for the same reason, the MinGW-w64 runtime's notice
under `licenses/mingw-w64/`; the compiler's own runtime, LLVM's compiler-rt,
is linked in as well and has no file, since LLVM's exception to Apache 2.0
lifts the licence's notice conditions for what compiling embeds in a
program),
and `licenses/NOTICES`, the
notices those libraries' sources state, one of each: a project's licence
file is its summary and can be short of what its sources ask to be
reproduced (LibreSSL's is two texts and a sentence, where its sources carry
hundreds of notices of their own). `archive-notices.sh` fetches each source
the manifest names, verified against the hash curl-for-win itself builds
from, and `notices.sh` reads the notices out; terms it does not know stop
the build.

No archive carries a CA bundle as a file, and what a curl trusts is not the
same on every platform:

- **windows**: the Windows certificate store (`NativeCA` among the features
  `curl --version` prints, no `CAcert`). curl-for-win stopped packaging
  `curl-ca-bundle.crt` for windows with 8.23.0_3.
- **macOS**: the system's trust (`AppleSecTrust`). Nothing is embedded.
- **linux**: Mozilla's roots, inside the binary (curl's CA embed;
  `curl --dump-ca-embed` prints them). They are used unless something names
  others: `--cacert` or `--capath`, or one of `CURL_CA_BUNDLE`,
  `SSL_CERT_FILE` and `SSL_CERT_DIR` in the environment, which a host or a
  CI job may export for every program. They are the roots of the
  day curl-for-win pinned them and move only with a release of this
  repository: the linux archive's `BUILD-MANIFEST.txt` gives that day and
  the exact file on its `certdata` line (2026-11-13 at curl-for-win
  8.23.0_10). Their licence, MPL 2.0, is in the archive as curl-for-win's
  package carries it, `licenses/certdata/LICENSE.desktop`, a link to the
  text.

## Verifying a release

A release is the five archives, an SPDX SBOM beside each
(`<archive>.sbom.json`), `checksums.txt` over those ten files, and
`checksums.txt.sigstore.json`, cosign's keyless signature over it. Each
archive, each SBOM and `checksums.txt` has a GitHub Artifact Attestation,
signed by this repository's release workflow (the signature file has none:
it is itself what vouches for `checksums.txt`). The same command covers the
eleven:

```sh
gh attestation verify curl_<version>_linux_amd64.tar.gz --repo packcloser/curl
```

The keyless signature over `checksums.txt`, for a verifier with cosign and
no `gh`:

```sh
cosign verify-blob checksums.txt --bundle checksums.txt.sigstore.json \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp '^https://github.com/packcloser/curl/\.github/workflows/release\.yaml@'
sha256sum -c --ignore-missing checksums.txt
```

`--ignore-missing` checks the files that are there; without it, every one of
the ten that was not downloaded is a failure.

## Version bumps

Renovate watches the curl.se download index directly (a custom HTML
datasource — the `dl-<version>_<rev>/` hrefs carry the package token) and
PRs bumps to `CFW_PACKAGE` in `versions.env`. CI runs the import on every
PR, so a bump can only go green if the package exists on curl.se *and* its
sigstore bundle verifies against the vendored key. Merging and tagging stay
human acts, as does `CFW_COMMIT` (bumping the build-script pin means
re-auditing the scripts and re-cross-checking the key — never automated).

**The two pins move together, on every bump.** `CFW_PACKAGE` is what the
windows legs import; `CFW_COMMIT` is the curl-for-win commit whose scripts the
linux and mac legs build with, and its `_versions.sh` names curl and every
library. A new curl version is a new commit, and so is a new package revision
of the same curl: each revision since the first is a library bump (8.23.0_1
to 8.23.0_9 moved LibreSSL, nghttp2, nghttp3, ngtcp2 and brotli). `CFW_PACKAGE`
moved alone would release a windows curl on the new libraries and a linux and
mac curl on the old ones, under one version.

So Renovate's pull request, which moves `CFW_PACKAGE` alone, is the notice of
a bump and never the bump: its linux and mac legs are red by construction.
`check-dependencies.sh` holds each package those legs build to the windows
package's `BUILD-MANIFEST.txt` and fails on a library at another version, as
the collection by version glob fails on another curl. The bump is a pull
request that moves both lines, `CFW_COMMIT` to the commit that built the
package (the one whose `_versions.sh` has that revision as `_REV`), with the
audit `UPSTREAM.md` records. Renovate cannot make it: no datasource maps a
package to its commit, and the audit is not its to do.

## Consuming these packages (aqua)

The release publishes GitHub Artifact Attestations for every archive, so a
consumer must verify them — a plain checksum pin would silently discard the
guarantee this repo exists to provide. This is the reference entry for a
consumer's local aqua registry: `github_artifact_attestations` is what makes
aqua verify the attestation on install, and the `checksum:` block adds the
committed-pin belt to the attestation's suspenders.

```yaml
- type: github_release
  repo_owner: packcloser
  repo_name: curl
  description: curl with dependable TLS 1.3, first-party build (packcloser/curl)
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
    signer_workflow: packcloser/curl/.github/workflows/release.yaml
  supported_envs:
    - darwin/arm64   # no darwin/amd64 — Intel Mac support was dropped
    - linux
    - windows
```

The authoritative copy of this entry belongs in limen's canonical
`.limen/aqua-registry.yaml` (so every repo inherits it through a limen
release), with the curl version pinned in each consumer's `aqua.yaml`; this
block is what that copy is derived from. Validated against v8.21.0 through
aqua on windows/amd64 and windows/arm64: checksum and attestation verify on
install, and `curl.exe` from aqua's `pkgs/` layout completes a verified TLS 1.3
request, trusting the Windows certificate store (it does the same with the
bundle beside it removed). One thing a windows consumer must get right: in a
runner's `shell: bash`, Git for Windows' own `/mingw64/bin/curl` sits ahead of
anything `GITHUB_PATH` appends, so the pinned curl only answers to `curl` when
aqua's bin is first on PATH (in POSIX form — a `C:/` entry splits at the colon
inside bash) or when called through the proxy by path.
