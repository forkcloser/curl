#!/usr/bin/env bash
#
# Hold a package this repository built to the dependencies of the windows
# package it imports: one release is one curl with one set of libraries on
# every platform.
#   check-dependencies.sh <BUILD-MANIFEST.txt of the built package> [<the windows package's>]
#
# The windows legs import curl-for-win's package at CFW_PACKAGE; the posix
# legs build with curl-for-win's scripts at CFW_COMMIT, whose _versions.sh
# names the libraries. The two pins are separate lines of versions.env, and
# every package revision since the first of a curl version is a library bump:
# CFW_PACKAGE moved alone gives a windows curl on the new libraries and a
# posix one on the old, under one version. This fails that build.
#
# Without a second argument the windows package's manifest is fetched from
# curl.se and verified as import-windows.sh verifies the package.

set -euo pipefail

built=${1:?the BUILD-MANIFEST.txt of the built package}
windows=${2:-}

cd "$(dirname "$0")"
# shellcheck source=versions.env disable=SC1091
. ./versions.env

if [ -z "${windows}" ]; then
  pkg="curl-${CFW_PACKAGE}-win64-mingw"
  url="https://curl.se/windows/dl-${CFW_PACKAGE}/${pkg}.tar.xz"
  work="build/check-dependencies"
  rm -rf "${work}"
  mkdir -p "${work}"
  curl --proto '=https' --tlsv1.2 -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o "${work}/${pkg}.tar.xz" "${url}"
  curl --proto '=https' --tlsv1.2 -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o "${work}/${pkg}.tar.xz.sigstore" "${url}.sigstore"
  cosign verify-blob --key cosign.pub.asc --bundle "${work}/${pkg}.tar.xz.sigstore" "${work}/${pkg}.tar.xz" > /dev/null
  tar -xJf "${work}/${pkg}.tar.xz" -C "${work}" "${pkg}/BUILD-MANIFEST.txt"
  windows="${work}/${pkg}/BUILD-MANIFEST.txt"
fi

# A manifest line is `<name> <version> [<url>]`. The names that begin with a
# dot are the toolchain, which differs by platform; a library one platform
# links and the other does not (the CA bundle's source, on linux alone) is
# in one manifest only. What both name must be at one version.
failed=0
compared=0
while read -r name version _; do
  case "${name}" in '' | .*) continue ;; esac
  theirs=$(awk -v name="${name}" '$1 == name { print $2 }' "${windows}")
  [ -n "${theirs}" ] || continue
  compared=$((compared + 1))
  if [ "${theirs}" != "${version}" ]; then
    echo "${name}: built ${version}, the windows package ${CFW_PACKAGE} has ${theirs}" >&2
    failed=1
  fi
done < "${built}"

if [ "${compared}" -eq 0 ]; then
  echo "${built} and ${windows} name no library in common: not two curl-for-win manifests" >&2
  exit 1
fi
if [ "${failed}" -ne 0 ]; then
  echo "CFW_COMMIT ${CFW_COMMIT} does not build what CFW_PACKAGE ${CFW_PACKAGE} is: move the two pins together (README, \"Version bumps\")" >&2
  exit 1
fi
echo "✓ ${compared} libraries at the versions of the windows package ${CFW_PACKAGE}"
