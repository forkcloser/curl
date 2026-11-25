# Upstream

Repackaging of <https://github.com/curl/curl-for-win> (`main`), the curl project's own
reproducible-build system. The windows legs import its official packages; the posix legs
run its build system at the commit below.

- Built from: [`55ebdc0`](https://github.com/curl/curl-for-win/commit/55ebdc042cc1c8dca6f1953ae128a2abec0d3db6), curl-for-win 8.23.0_10, committed 2026-11-24 (`CFW_COMMIT` in `versions.env`); its `_versions.sh` has `_REV` 10
- Reviewed through: the same commit, audited 2026-11-24. The 47 commits since `f21b050`:
  - `_versions.sh`: zstd 1.5.7 to 1.6.0, with its hash; curl stays 8.23.0, and so does every
    other library the curl links. zstd's changelog for 1.6.0 opens with its fixes to
    decompression: malformed data that exposed uninitialized memory, reads and writes out of
    bounds, uses after free. The root certificates: `CERTDATA_VER_` from 2026-11-05 (`30e59d4`)
    to 2026-11-13 (`8c60e75`), so the set of roots a linux consumer trusts moved again
    (`CURL_CA_EMBED`). llvm-mingw, which builds the windows packages, from 20261104 to
    20261117: its MinGW-w64 runtime is mingw-w64 at `41eb042`, where it was `ee9bd87`, and
    the runtime's notice is byte for byte the same at both (`notices/`, under the release's
    name).
  - `_dl.sh`: zstd comes from `github.com/meta/zstd`, the repository `facebook/zstd` now
    redirects to; the signing key it is checked against is the same.
  - `zstd.sh`, `zstd.patch`: the patch is gone, zstd 1.6.0 having what it carried (C++ is no
    longer required to configure the library). `ZSTD_LEGACY_SUPPORT=OFF` is no longer passed,
    the legacy formats being off by default in 1.6.0; the assembler gets the C flags
    (`CMAKE_ASM_FLAGS`) and the global assembler options, with `--no-warn-unused-cli` on
    trixie and `-Wno-unused-cli` elsewhere, as `curl.sh` has them.
  - `_sign-pkg-minisign.sh`: a seventh `bsd|mac)` stat site, the package's timestamp for a
    signature that comes out the same twice. It runs with a minisign key, which no build here
    has, and is patched with the other six.
  - `_build.sh`: `_ROOT`, the build's root, is exported; `-fno-semantic-interposition` and
    `-Wl,-Bsymbolic` for gcc builds of linux as for clang ones (the builds here are clang's);
    the gcc install root workaround for arm64 covers clang 23 (glibc builds, not built here).
  - `curl.sh`, `trurl.sh`: the map files lose the build root (`CW_MAP`, off for a `main`
    config such as the ones built here); `wcurl.bat` takes the reference timestamp (windows).
  - `libressl.sh`: `CMAKE_ASM_FLAGS` and `CMAKE_C_FLAGS` in the other order, the same values.
  - `certdata.sh`: the licence link beside the CA bundle's source is `https://mozilla.org/MPL/2.0/`.
  - `_ci-linux-debian.sh` (not run here, mirrored below): the default clang goes from 22 to
    23, and OpenSSL builds install `linux-libc-dev` where they installed the kernel headers
    by architecture; the package set `build-posix-container.sh` installs is unchanged. The
    linux legs here still compile with the LLVM 22 release `pins.yaml` holds.
  - The rest is BoringSSL, AWS-LC, OpenSSL and its patches, osslsigncode, `_bumper.sh`,
    `_peclean.py` (windows), a comment in `_sign-pkg-ssh.sh`, the version in their README's
    example commands, the debian images of their own CI and their workflows.

  The six earlier `bsd|mac)` stat sites and the five `mac) rm -f -P` sites below are where
  they were, and `cosign.pub.asc` is unchanged, the same key as the one in their README at
  this commit. Earlier audits: 2026-11-14 at `f21b050`, 2026-10-18 at `f478a7c`, 2026-10-05
  ([#41](https://github.com/forkcloser/curl/pull/41)).

A bump of `CFW_COMMIT` re-audits curl-for-win's scripts and every entry below; nothing
else about them is changed, in silence or otherwise. Each entry names where the change
is made and why; the scripts guard the mechanical ones with a count of the sites they
expect, so a bump that moves a site stops the build instead of half-patching it.

## Changes upstream does not have

| Change | Where | Here |
| --- | --- | --- |
| The linux legs are provisioned by pinned inputs, never by `_ci-linux-debian.sh` | `build-posix.sh`, `build-posix-container.sh` | https://github.com/forkcloser/curl/pull/64 |
| macOS takes the GNU `stat` branch | seven `bsd\|mac)` sites in `curl.sh`, `_pkg.sh`, `_info-bin.sh`, `openssl.sh`, `_sign-code.sh`, `_sign-pkg-minisign.sh` | [`8b648d1`](https://github.com/forkcloser/curl/commit/8b648d1) |
| The `rm -P` branches for macOS are removed | five `mac) rm -f -P --` sites in `_build.sh`, `_ul.sh` | [`8b648d1`](https://github.com/forkcloser/curl/commit/8b648d1) |

### The linux legs are provisioned here, not by `_ci-linux-debian.sh`

curl-for-win's `_ci-linux-debian.sh` installs the build's dependencies, the
toolchain included, from Debian testing's live archive: the `clang-23` that
builds a release is whichever one the archive carries that day. This
repository never runs that script. `build-posix.sh` starts the debian image
`versions.env` pins by digest (`BUILD_IMAGE`) and, inside it,
`build-posix-container.sh` points apt at snapshot.debian.org at the pinned
timestamp (`APT_SNAPSHOT`, signed by the image's own
`debian-archive-keyring`), installs `_ci-linux-debian.sh`'s package set for a
native `linux-musl` config minus `llvm-23 clang-23 lld-23 libclang-rt-23-dev`,
plus `libxml2` (the release `lld` links it), and runs `./_build.sh` as the
upstream script does last. The compiler is the LLVM release `pins.yaml` pins,
fetched and verified on the host and mounted read-only at `/opt/llvm`, with
`CW_CCSUFFIX` empty because the release tarball's tools are unsuffixed where
Debian's are `clang-23`. Nothing in `_build.sh` changes.

The suite differs too. The pinned image is Debian trixie, so the static linux
curl links trixie's musl, 1.2.5, where a build from Debian testing links
1.2.6. curl-for-win builds the same pairing, trixie and musl 1.2.5, in its own
`linux-musl-debian-stable-llvm` job.

### The mac leg runs `_build.sh`, not `_ci-mac-homebrew.sh`

curl-for-win's `_ci-mac-homebrew.sh` installs `gnu-tar` and `jq` with Homebrew
for this config and runs `./_build.sh`, with Homebrew's directory on the PATH:
the `cmake`, `ninja` and `gpg` of a build are whichever ones Homebrew has
there. This repository never runs that script. `build-posix.sh` runs
`./_build.sh` with `cmake` and `ninja` from the pinned tools
(`.hermetic/hermetic.yaml`), the pinned `gtar` and `jq`, and two of the
machine's tools reachable by name, `gpg` and `brew` (`_build.sh` calls
`brew --prefix` on a mac host). Under that prefix `_build.sh` takes
Homebrew's `llvm-strip` by its full path for the static libraries when
Homebrew holds `llvm`, and leaves them unstripped when it does not (CI's
runner has none), as it does under upstream's script. Nothing in `_build.sh`
changes.

### `stat` flags on macOS

curl-for-win picks `stat`'s flags by uname (BSD `stat -f` on macOS), while
the hermetic PATH's coreutils are GNU on every platform. The macOS case is
sent down the GNU branch.

### `rm -P` on macOS

The branches that delete a signing or deploy key with BSD `rm -P`, which
uutils `rm` rejects and which has no effect on macOS anyway, are removed; the
plain `rm -f` after each case deletes the key.
