#!/usr/bin/env bash
#
# Build the linux (static, musl) and macOS (arm64) curl using curl-for-win's
# own build system at an audited pin (CFW_COMMIT) — the same machinery that
# produces the windows packages we import, so every platform shares one build
# lineage. macOS is arm64-only (a64), not universal: farcloser dropped Intel
# Mac support, so we don't ship an x86_64 slice.
#
# The linux legs run inside the debian container curl-for-win pins (by
# digest, via their _versions.sh): their _ci-linux-debian.sh expects to BE in
# debian — the container wrapper lives in the caller, exactly as in their own
# workflow. The mac leg runs directly on a macOS machine (their script
# provisions its homebrew dependencies).
#
# Which container runtime wraps the linux legs depends on the host:
#   linux  — podman, as on the CI runners.
#   macOS  — docker, from the hermetic PATH like every other tool.
# Both take the same flags, so the invocation differs only in the head. The
# amd64 leg on an arm64 mac runs under Rosetta (--platform linux/amd64).
#
# Usage: build-posix.sh {linux-amd64|linux-arm64|mac-arm64}

set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=versions.env disable=SC1091
. ./versions.env
CURL_VERSION="${CFW_PACKAGE%_*}"
# The package build-revision (the _N in CFW_PACKAGE) — curl-for-win's
# CW_REVISION. Feeding it here makes the posix packages carry the SAME rev
# token as the imported windows ones (one lineage, consistent naming); it is a
# filename component only, never embedded in the binary. NOT the commit: the
# git checkout already pins the code.
CFW_REV="${CFW_PACKAGE##*_}"

# Not `${1:?...}`: a literal `}` in the message terminates the expansion early
# and the trailing brace leaks into the value.
target="${1:-}"
if [ -z "$target" ]; then
    echo "usage: build-posix.sh {linux-amd64|linux-arm64|mac-arm64}" >&2
    exit 2
fi

case "$target" in
  # The leading 'main' token is the branch marker curl-for-win's config
  # parser expects; the arch token (x64/a64) scopes the build to the job's
  # native arch — a bare 'linux-musl' config means ALL arches, cross-built
  # through qemu.
  linux-amd64) config='main-linux-musl-x64' kind='linux' pkgos='linux' platform='linux/amd64' ;;
  linux-arm64) config='main-linux-musl-a64' kind='linux' pkgos='linux' platform='linux/arm64' ;;
  mac-arm64)   config='main-mac-a64'        kind='mac'   pkgos='macos' platform='' ;;
  *)           echo "unknown target: $target" >&2; exit 1 ;;
esac

work="build/cfw"
if [ ! -d "$work" ]; then
  git clone --quiet https://github.com/curl/curl-for-win "$work"
fi
git -C "$work" checkout --quiet "$CFW_COMMIT"

if [ "$kind" = 'linux' ]; then
  # Mirror their workflow: digest-pinned debian image from _versions.sh, the
  # tree mounted at its own path, CW_* env passed through. Both runtimes take
  # the same docker-shaped flags, so the invocation differs only in the head.
  (
    cd "$work"
    export CW_CONFIG="$config"
    export CW_REVISION="$CFW_REV"
    # shellcheck source=/dev/null
    . ./_versions.sh
    image="${OCI_IMAGE_DEBIAN_TESTING:?_versions.sh did not provide the pinned image}"
    case "$image" in
      *@sha256:*) ;;
      *) echo "refusing to build from an image that is not digest-pinned: ${image}" >&2; exit 1 ;;
    esac

    runtime=()
    case "$(uname -s)" in
      Darwin)
        # Unsized, the build gets the whole machine; OSSEIN_CPUS and
        # OSSEIN_MEMORY (docker's units) are overrides only.
        runtime=(docker run --rm --platform "$platform")
        [ -z "${OSSEIN_CPUS:-}" ] || runtime+=(--cpus "$OSSEIN_CPUS")
        [ -z "${OSSEIN_MEMORY:-}" ] || runtime+=(--memory "$OSSEIN_MEMORY")
        ;;
      *)
        runtime=(podman run --rm)
        ;;
    esac

    "${runtime[@]}" --volume "$(pwd):$(pwd)" --workdir "$(pwd)" \
      --env-file <(env | grep -aE '^(CW_|DO_NOT_TRACK)') \
      "$image" \
      sh -c ./_ci-linux-debian.sh
  )
else
  (cd "$work" && CW_CONFIG="$config" CW_REVISION="$CFW_REV" sh -c ./_ci-mac-homebrew.sh)
fi

# Collect: their packages are curl-<version>[_rev]-<cpu>-<os>.tar.xz in the
# work tree. Glob rather than hardcode the exact names; each package becomes
# one of our per-arch archives.
out="build/dist"
mkdir -p "$out"

found=0
for pkg in "$work"/curl-"${CURL_VERSION}"*-"$pkgos".tar.xz; do
  [ -e "$pkg" ] || continue
  found=1

  extract="build/extract-$target-$(basename "$pkg" .tar.xz)"
  rm -rf "$extract"
  mkdir -p "$extract"
  tar -xJf "$pkg" -C "$extract"

  bin="$(find "$extract" -type f -name curl -path '*/bin/*' | head -n 1)"
  [ -n "$bin" ] || { echo "no curl binary inside $(basename "$pkg")" >&2; exit 1; }
  root="$(dirname "$(dirname "$bin")")"

  # Map their package cpu token to our arch name. No universal case: mac is
  # built a64-only (see the config above), so every package is single-arch.
  arch=''
  case "$pkg" in
    *-x86_64-*)              arch='amd64' ;;
    *-aarch64-* | *-arm64-*) arch='arm64' ;;
    *) echo "unrecognized cpu token in $(basename "$pkg")" >&2; exit 1 ;;
  esac

  goos='linux'
  [ "$pkgos" = 'macos' ] && goos='darwin'

  name="curl_${CURL_VERSION}_${goos}_${arch}"
  mkdir -p "build/${name}"
  cp "$bin" "${root}/COPYING.txt" "build/${name}/"
  tar -czf "${out}/${name}.tar.gz" -C build "$name"
  echo "✓ ${out}/${name}.tar.gz"
done

[ "$found" = 1 ] || { echo "no curl-${CURL_VERSION}*-${pkgos}.tar.xz produced under ${work}" >&2; exit 1; }
