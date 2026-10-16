#!/usr/bin/env bash
#
# Build the linux (static, musl) and macOS (arm64) curl using curl-for-win's
# own build system at an audited pin (CFW_COMMIT) — the same machinery that
# produces the windows packages we import, so every platform shares one build
# lineage. macOS is arm64-only (a64), not universal: farcloser dropped Intel
# Mac support, so we don't ship an x86_64 slice.
#
# The linux legs run inside the debian image versions.env pins by digest, with
# apt from snapshot.debian.org at the pinned timestamp and the compiler from
# the LLVM release pins.yaml pins: this script fetches and verifies that
# release on the host, unpacks the tools the build invokes, and mounts them
# read-only at /opt/llvm; build-posix-container.sh provisions inside the
# image and runs their _build.sh. Every deviation from curl-for-win's own
# scripts is listed in UPSTREAM.md. The mac leg runs directly on a macOS
# machine (their script provisions its homebrew dependencies).
#
# The container runtime is `docker`, from the hermetic PATH like every other
# tool, on every host. The amd64 leg on an arm64 mac runs under Rosetta
# (--platform linux/amd64).
#
# Usage: build-posix.sh {linux-amd64|linux-arm64|mac-arm64}

set -euo pipefail

cd "$(dirname "$0")"
root="$(pwd -P)"
# shellcheck source=versions.env disable=SC1091
. ./versions.env
CURL_VERSION="${CFW_PACKAGE%_*}"
# The archives carry the release's version: the tag's (PACKAGE_VERSION,
# e.g. 8.22.0 or 8.22.0.1 for a rebuild of the same curl) or, by default, the
# pinned curl's. A tag that names another curl than the pin is refused.
package_version="${PACKAGE_VERSION:-${CURL_VERSION}}"
[ "${package_version}" = "${CURL_VERSION}" ] || [ "${package_version%.*}" = "${CURL_VERSION}" ] ||
  { echo "PACKAGE_VERSION ${package_version} is not the pinned curl ${CURL_VERSION} (${CURL_VERSION} or ${CURL_VERSION}.N)" >&2; exit 1; }
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

# llvm_toolchain <target>: the pinned LLVM release for the target, fetched
# and verified against pins.yaml, unpacked once per digest under build/llvm
# to the tools curl-for-win invokes (clang, lld, and the llvm- binutils it
# names: _build.sh's _BINUTILS_PREFIX and _BINCORE_PREFIX sites, _info-bin.sh)
# and clang's resource directory (its headers and compiler-rt). Prints the
# directory. The tarball is ~1.9 GB and unpacks to ~12 GB, almost all of it
# tools and static libraries no build here runs, so the members are selected
# from a listing first and the archive is read twice; what remains is ~750 MB,
# and CI caches it on the pin.
llvm_toolchain() {
  local name="llvm-$1" url sum version file dir list
  url="$(limen pins get "$name" url)"
  sum="$(limen pins get "$name" sha256)"
  version="$(limen pins get "$name" version)"
  dir="${root}/build/llvm/${name}-${sum}"
  if [ -f "${dir}/.unpacked" ]; then
    echo "$dir"
    return
  fi
  mkdir -p "${root}/build/llvm"
  file="${root}/build/llvm/${name}-${version}.tar.xz"
  if [ ! -f "$file" ]; then
    echo "fetching ${name} ${version}" >&2
    curl --proto '=https' --tlsv1.2 -fsSL --retry 5 --retry-delay 3 -o "${file}.part" "$url"
    mv "${file}.part" "$file"
  fi
  echo "${sum}  ${file}" | sha256sum -c - > /dev/null || {
    echo "${name}: sha256 mismatch against pins.yaml" >&2
    rm -f "$file"
    exit 1
  }
  rm -rf "$dir"
  mkdir -p "$dir"
  list="${dir}.members"
  # Files and symlinks only, never a directory member: tar extracts a named
  # directory with everything under it, which would bring the 12 GB back.
  tar -tvJf "$file" | grep -v '^d' | sed -E 's/^.* (LLVM-[^ /]+\/)/\1/; s/ -> .*$//' |
    grep -E '^[^/]+/(bin/(clang|clang-[0-9]+|clang\+\+|lld|ld\.lld|llvm-(ar|ranlib|nm|objcopy|strip|objdump|readobj|readelf))|lib/clang/.+)$' > "$list"
  tar -xJf "$file" -C "$dir" --strip-components=1 -T "$list"
  [ -x "${dir}/bin/clang" ] && [ -e "${dir}/bin/ld.lld" ] || {
    echo "${name}: no bin/clang and bin/ld.lld among the unpacked tools" >&2
    exit 1
  }
  rm -f "$list" "$file"
  touch "${dir}/.unpacked"
  echo "$dir"
}

work="build/cfw"
if [ ! -d "$work" ]; then
  git clone --quiet https://github.com/curl/curl-for-win "$work"
fi
git -C "$work" checkout --quiet "$CFW_COMMIT"

# curl-for-win picks stat's flags by uname (BSD `stat -f` on macOS), while the
# hermetic PATH's coreutils are GNU on every platform. Send macOS down the GNU
# branch of its six `bsd|mac)` stat cases. The files are restored first so a
# rerun patches pristine copies, and any other count stops the build: a
# CFW_COMMIT bump that moves these cases must not leave them half-patched.
cfw_stat_files=(curl.sh _pkg.sh _info-bin.sh openssl.sh _sign-code.sh)
git -C "$work" checkout --quiet "$CFW_COMMIT" -- "${cfw_stat_files[@]}"
cfw_stat_sites=$(cd "$work" && cat "${cfw_stat_files[@]}" | grep -c 'bsd|mac)' || true)
if [ "$cfw_stat_sites" -ne 6 ]; then
  echo "curl-for-win ${CFW_COMMIT} has ${cfw_stat_sites} 'bsd|mac)' cases in ${cfw_stat_files[*]}, not the 6 this patch expects" >&2
  exit 1
fi
for f in "${cfw_stat_files[@]}"; do
  sed -i.orig 's/bsd|mac)/bsd)/' "$work/$f"
  rm "$work/$f.orig"
done

# Its five `mac)` branches that delete a signing or deploy key call BSD
# `rm -P`, which uutils rm rejects and which has no effect on macOS anyway;
# the plain `rm -f` after each case deletes the key. The branches go, under
# the same restore-then-count guard.
cfw_rm_files=(_build.sh _ul.sh)
git -C "$work" checkout --quiet "$CFW_COMMIT" -- "${cfw_rm_files[@]}"
cfw_rm_sites=$(cd "$work" && cat "${cfw_rm_files[@]}" | grep -c 'mac) *rm -f -P --' || true)
if [ "$cfw_rm_sites" -ne 5 ]; then
  echo "curl-for-win ${CFW_COMMIT} has ${cfw_rm_sites} 'mac) rm -f -P' cases in ${cfw_rm_files[*]}, not the 5 this patch expects" >&2
  exit 1
fi
for f in "${cfw_rm_files[@]}"; do
  sed -i.orig '/mac) *rm -f -P --/d' "$work/$f"
  rm "$work/$f.orig"
done

if [ "$kind" = 'linux' ]; then
  case "$BUILD_IMAGE" in
    *@sha256:*) ;;
    *) echo "refusing to build from an image that is not digest-pinned: ${BUILD_IMAGE}" >&2; exit 1 ;;
  esac
  llvm="$(llvm_toolchain "$target")"
  # The container script rides in a read-only mount of its own, apart from
  # the curl-for-win tree, which stays theirs.
  mkdir -p build/container
  cp build-posix-container.sh build/container/
  (
    cd "$work"
    export CW_CONFIG="$config"
    export CW_REVISION="$CFW_REV"
    export DEBIAN_SUITE APT_SNAPSHOT

    # Unsized, the build gets the whole machine; BUILD_CPUS and BUILD_MEMORY
    # (docker's units) are overrides only.
    runtime=(docker run --rm --platform "$platform")
    [ -z "${BUILD_CPUS:-}" ] || runtime+=(--cpus "$BUILD_CPUS")
    [ -z "${BUILD_MEMORY:-}" ] || runtime+=(--memory "$BUILD_MEMORY")

    # The tree mounted at its own path, CW_* env passed through, as in their
    # own workflow; the toolchain and the script read-only beside it.
    "${runtime[@]}" --volume "$(pwd):$(pwd)" --workdir "$(pwd)" \
      --volume "${llvm}:/opt/llvm:ro" \
      --volume "${root}/build/container:/opt/forkcloser:ro" \
      --env-file <(env | grep -aE '^(CW_|DO_NOT_TRACK|DEBIAN_SUITE=|APT_SNAPSHOT=)') \
      "$BUILD_IMAGE" \
      bash /opt/forkcloser/build-posix-container.sh
  )
else
  # curl-for-win's mac script provisions its build dependencies with brew,
  # which the hermetic PATH hides. The .justfile exports BREW_BIN, captured
  # from the ambient PATH for exactly this; its directory is appended for this
  # leg only, behind the pinned tools.
  brew="${BREW_BIN:-$(command -v brew || true)}"
  [ -n "$brew" ] || { echo "no brew (BREW_BIN is empty): curl-for-win's mac leg needs homebrew" >&2; exit 1; }
  (cd "$work" && PATH="$PATH:$(dirname "$brew")" CW_CONFIG="$config" CW_REVISION="$CFW_REV" sh -c ./_ci-mac-homebrew.sh)
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
  pkgroot="$(dirname "$(dirname "$bin")")"

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

  name="curl_${package_version}_${goos}_${arch}"
  mkdir -p "build/${name}"
  cp "$bin" "${pkgroot}/COPYING.txt" "build/${name}/"
  tar -czf "${out}/${name}.tar.gz" -C build "$name"
  echo "✓ ${out}/${name}.tar.gz"
done

[ "$found" = 1 ] || { echo "no curl-${CURL_VERSION}*-${pkgos}.tar.xz produced under ${work}" >&2; exit 1; }
