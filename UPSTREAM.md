# Upstream

Repackaging of <https://github.com/curl/curl-for-win> (`main`), the curl project's own
reproducible-build system. The windows legs import its official packages; the posix legs
run its build system at the commit below.

- Built from: [`f21b050`](https://github.com/curl/curl-for-win/commit/f21b0503e7266a3dbf880b9e2c2eb49b4ff5dd6e), curl-for-win 8.23.0_9, committed 2026-11-11 (`CFW_COMMIT` in `versions.env`); its title says 8.23.0_8, its `_versions.sh` has `_REV` 9
- Reviewed through: the same commit, audited 2026-11-14. The 99 commits since `f478a7c`:
  - `_versions.sh`: LibreSSL 4.3.3 to 4.4.1, nghttp2 1.70.0 to 1.71.0, nghttp3 1.18.0 to 1.19.0,
    ngtcp2 1.25.0 to 1.26.0, brotli 1.2.0 to 1.2.1 (upstream's title names a CVE fix), c-ares
    1.34.8 to 1.34.9, zlib 1.3.2 to 1.4 and the public suffix list, each with its hash; curl
    stays 8.23.0. And the root certificates: `CERTDATA_VER_` from 2026-09-08 (`f6dd015`) to
    2026-11-05 (`30e59d4`). The linux curl embeds the bundle made from that file
    (`CURL_CA_EMBED`, set where the target is neither mac nor windows), so the set of roots a
    linux consumer trusts moved with this bump.
  - `_dl.sh`: the windows packages no longer carry a CA bundle (`certdata` is left out for
    `win` as it was for `mac`), and `certdata.txt` comes from mozilla/nss, not the Firefox tree.
  - `curl.patch`, new, applied to curl's sources on every platform: `mk-ca-bundle.pl`, and in
    `lib/vtls/openssl.c` a filter in `ossl_win_load_store`, windows-only code.
  - `curl.sh`: LDAP is no longer disabled on macOS (the system's library); `CURL_DISABLE_SRP`
    and `-lpthread` go; `--no-warn-unused-cli` stays on trixie, `-Wno-unused-cli` elsewhere.
  - `_build.sh`: `-Werror=unused-cli` for every CMake run, `-Wno-dev` kept on trixie; the macOS
    deployment target from 10.14 to 11.00; the C++ flags and header paths now set for
    BoringSSL and AWS-LC builds alone (not built here); `pip` for windows builds on a mac host.
  - `_ci-linux-debian.sh` (not run here, mirrored below): `linux-headers` only for OpenSSL
    builds; `build-posix-container.sh` drops it.
  - The rest is BoringSSL, AWS-LC, OpenSSL, c-ares, libssh, trurl and their own workflows.

  The six `bsd|mac)` stat sites and the five `mac) rm -f -P` sites below are where they were, and
  `cosign.pub.asc` is unchanged. Earlier audits: 2026-10-18 at `f478a7c`, 2026-10-05
  ([#41](https://github.com/forkcloser/curl/pull/41)).

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

The suite differs too. The pinned image is Debian trixie, so the static linux
curl links trixie's musl, 1.2.5, where a build from Debian testing links
1.2.6. curl-for-win builds the same pairing, trixie and musl 1.2.5, in its own
`linux-musl-debian-stable-llvm` job.

### `stat` flags on macOS

curl-for-win picks `stat`'s flags by uname (BSD `stat -f` on macOS), while
the hermetic PATH's coreutils are GNU on every platform. The macOS case is
sent down the GNU branch.

### `rm -P` on macOS

The branches that delete a signing or deploy key with BSD `rm -P`, which
uutils `rm` rejects and which has no effect on macOS anyway, are removed; the
plain `rm -f` after each case deletes the key.
