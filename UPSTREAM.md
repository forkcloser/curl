# Upstream

Repackaging of <https://github.com/curl/curl-for-win> (`main`), the curl project's own
reproducible-build system. The windows legs import its official packages; the posix legs
run its build system at the commit below.

- Built from: [`f478a7c`](https://github.com/curl/curl-for-win/commit/f478a7cc3c6f6bf00bf0745e3a55a129b8a5ec2b), curl-for-win 8.23.0_1, committed 2026-10-14 (`CFW_COMMIT` in `versions.env`)
- Reviewed through: the same commit, audited 2026-10-18. The seven commits since `9d77e31` move
  `_versions.sh` (curl 8.23.0 and its hash; llvm-mingw 20261006, the windows cross toolchain the
  imported packages are built with), drop the GitHub token `_dl.sh` forwarded to api.github.com,
  drop `brew update` from `_ci-mac-homebrew.sh` (not run here) and touch their own workflows; the
  six `bsd|mac)` stat sites and the five `mac) rm -f -P` sites below are where they were, and
  `cosign.pub.asc` is unchanged. Earlier audit: 2026-10-05 ([#41](https://github.com/forkcloser/curl/pull/41)).

A bump of `CFW_COMMIT` re-audits curl-for-win's scripts and every entry below; nothing
else about them is changed, in silence or otherwise. Each entry names where the change
is made and why; the scripts guard the mechanical ones with a count of the sites they
expect, so a bump that moves a site stops the build instead of half-patching it.

## Changes upstream does not have

| Change | Where | Here |
| --- | --- | --- |
| The linux legs are provisioned by pinned inputs, never by `_ci-linux-debian.sh` | `build-posix.sh`, `build-posix-container.sh` | https://github.com/forkcloser/curl/pull/64 |
| macOS takes the GNU `stat` branch | six `bsd\|mac)` sites in `curl.sh`, `_pkg.sh`, `_info-bin.sh`, `openssl.sh`, `_sign-code.sh` | [`8b648d1`](https://github.com/forkcloser/curl/commit/8b648d1) |
| The `rm -P` branches for macOS are removed | five `mac) rm -f -P --` sites in `_build.sh`, `_ul.sh` | [`8b648d1`](https://github.com/forkcloser/curl/commit/8b648d1) |

### The linux legs are provisioned here, not by `_ci-linux-debian.sh`

curl-for-win's `_ci-linux-debian.sh` installs the build's dependencies, the
toolchain included, from Debian testing's live archive: the `clang-22` that
builds a release is whichever one the archive carries that day. This
repository never runs that script. `build-posix.sh` starts the debian image
`versions.env` pins by digest (`BUILD_IMAGE`) and, inside it,
`build-posix-container.sh` points apt at snapshot.debian.org at the pinned
timestamp (`APT_SNAPSHOT`, signed by the image's own
`debian-archive-keyring`), installs `_ci-linux-debian.sh`'s package set for a
native `linux-musl` config minus `llvm-22 clang-22 lld-22 libclang-rt-22-dev`,
plus `libxml2` (the release `lld` links it), and runs `./_build.sh` as the
upstream script does last. The compiler is the LLVM release `pins.yaml` pins,
fetched and verified on the host and mounted read-only at `/opt/llvm`, with
`CW_CCSUFFIX` empty because the release tarball's tools are unsuffixed where
Debian's are `clang-22`. Nothing in `_build.sh` changes.

### `stat` flags on macOS

curl-for-win picks `stat`'s flags by uname (BSD `stat -f` on macOS), while
the hermetic PATH's coreutils are GNU on every platform. The macOS case is
sent down the GNU branch.

### `rm -P` on macOS

The branches that delete a signing or deploy key with BSD `rm -P`, which
uutils `rm` rejects and which has no effect on macOS anyway, are removed; the
plain `rm -f` after each case deletes the key.
