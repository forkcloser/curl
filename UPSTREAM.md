# Deviations from curl-for-win

The posix legs run [curl-for-win](https://github.com/curl/curl-for-win)'s
build system at the commit `versions.env` pins (`CFW_COMMIT`), as audited.
This file is the whole list of what this repository changes about it, so a
bump of that pin re-audits exactly these and nothing is changed in silence.
Each entry names where the change is made and why; the scripts guard the
mechanical ones with a count of the sites they expect, so a bump that moves a
site stops the build instead of half-patching it.

## The linux legs are provisioned here, not by `_ci-linux-debian.sh`

`build-posix.sh`, `build-posix-container.sh`.

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

## `stat` flags on macOS

`build-posix.sh`; six `bsd|mac)` sites in `curl.sh`, `_pkg.sh`,
`_info-bin.sh`, `openssl.sh`, `_sign-code.sh`.

curl-for-win picks `stat`'s flags by uname (BSD `stat -f` on macOS), while
the hermetic PATH's coreutils are GNU on every platform. The macOS case is
sent down the GNU branch.

## `rm -P` on macOS

`build-posix.sh`; five `mac) rm -f -P --` sites in `_build.sh`, `_ul.sh`.

The branches that delete a signing or deploy key with BSD `rm -P`, which
uutils `rm` rejects and which has no effect on macOS anyway, are removed; the
plain `rm -f` after each case deletes the key.
