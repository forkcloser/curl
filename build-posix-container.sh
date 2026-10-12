#!/usr/bin/env bash
#
# The linux legs' half of build-posix.sh that runs INSIDE the pinned debian
# image: provision the build the way curl-for-win's _ci-linux-debian.sh does,
# with the two differences that make it hermetic (UPSTREAM.md), then run
# their _build.sh as that script does last. apt installs from
# snapshot.debian.org at the pinned timestamp, so every package is the one
# the pin names; the compiler is the pinned LLVM release build-posix.sh
# mounted at /opt/llvm, not Debian's clang-NN.
#
# Inputs, from build-posix.sh's env-file: DEBIAN_SUITE, APT_SNAPSHOT, and the
# CW_* variables curl-for-win reads. The working directory is the curl-for-win
# tree, mounted at its own host path.

set -euo pipefail

suite="${DEBIAN_SUITE:?the apt suite of the image, e.g. trixie}"
snapshot="${APT_SNAPSHOT:?a snapshot.debian.org timestamp, e.g. 20261003T204240Z}"

case "$(uname -m)" in
  x86_64)  headers='linux-headers-amd64' ;;
  aarch64) headers='linux-headers-arm64' ;;
  *) echo "no linux leg builds on $(uname -m)" >&2; exit 1 ;;
esac

# library/debian ships the keyring the sources below are signed by; another
# image flavor would fail at apt's signature check with a less useful message.
[ -f /usr/share/keyrings/debian-archive-keyring.gpg ] || {
  echo "no /usr/share/keyrings/debian-archive-keyring.gpg in the image: not a library/debian image" >&2
  exit 1
}

export DEBIAN_FRONTEND=noninteractive
rm -f /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources
cat > /etc/apt/sources.list.d/debian.sources <<SOURCES
Types: deb
URIs: http://snapshot.debian.org/archive/debian/${snapshot}
Suites: ${suite}
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
SOURCES
# A snapshot's Release file carries a Valid-Until that has passed.
cat > /etc/apt/apt.conf.d/00snapshot <<CONF
Acquire::Check-Valid-Until "false";
Acquire::Retries "5";
CONF

apt-get --option Dpkg::Use-Pty=0 --yes --quiet update
# _ci-linux-debian.sh's set for a native linux-musl config, minus the
# llvm/clang/lld/libclang-rt packages the mounted toolchain replaces, plus
# libxml2, which the release lld links against.
apt-get --option Dpkg::Use-Pty=0 --yes --quiet install --no-install-suggests --no-install-recommends \
  curl ca-certificates git gpg gpg-agent patch rsync make cmake ninja-build \
  zip xz-utils time jq secure-delete \
  checksec musl musl-dev "${headers}" python3 libxml2

export PATH="/opt/llvm/bin:${PATH}"
# _build.sh appends CW_CCSUFFIX to every tool name (clang${CW_CCSUFFIX}); the
# release tarball's are bare, where _ci-linux-debian.sh would set '-22'.
export CW_CCSUFFIX=''
echo ">> toolchain: $(clang --version | head -n 1)"

./_build.sh
