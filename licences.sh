#!/usr/bin/env bash
#
# Carry a curl-for-win package's own account of what its curl links into the
# directory an archive is made from: BUILD-MANIFEST.txt, and each library's
# licence under licenses/<library>/.
#   licences.sh <unpacked curl-for-win package> <archive directory>
#   licences.sh --libraries <BUILD-MANIFEST.txt>
#
# The curl binary links its libraries statically, so the archive that ships it
# ships them, and their terms ask to travel with it. curl-for-win's package
# has them, one directory a library under dep/; this repository's archives
# took the binary and curl's COPYING and left them behind.
#
# The libraries are read from the package's manifest, never typed here: a
# library a later package adds either comes with its licence or stops the
# build. --libraries prints that list, for the smoke test to hold an archive
# to.
set -euo pipefail
export LC_ALL=C

# The manifest's lines are `<name> <version> [<url>]`. A leading dot is the
# toolchain. curl's own licence is the archive's COPYING.txt, and trurl is
# another program of the package, which this repository does not ship.
libraries() {
  awk '$1 !~ /^\./ && $1 != "curl" && $1 != "trurl" && NF { print $1 }' "$1"
}

if [ "${1:-}" = --libraries ]; then
  libraries "${2:?a BUILD-MANIFEST.txt}"
  exit 0
fi

package=${1:?an unpacked curl-for-win package}
to=${2:?the archive directory}
manifest="${package}/BUILD-MANIFEST.txt"
[ -s "${manifest}" ] || { echo "licences.sh: no BUILD-MANIFEST.txt in ${package}" >&2; exit 1; }

cp "${manifest}" "${to}/BUILD-MANIFEST.txt"
count=0
while read -r library; do
  found=0
  for file in "${package}/dep/${library}"/LICENSE* "${package}/dep/${library}"/LICENCE* "${package}/dep/${library}"/COPYING*; do
    [ -f "${file}" ] || continue
    mkdir -p "${to}/licenses/${library}"
    cp "${file}" "${to}/licenses/${library}/"
    found=1
  done
  [ "${found}" -eq 1 ] || { echo "licences.sh: the package links ${library} and carries no licence for it under dep/${library}" >&2; exit 1; }
  count=$((count + 1))
done < <(libraries "${manifest}")
[ "${count}" -gt 0 ] || { echo "licences.sh: ${manifest} names no library" >&2; exit 1; }

# musl is on a toolchain line of a linux package's manifest and is more than
# a tool: the curl is static, so the C library is in the binary. curl-for-win
# carries no licence for it; the text is musl's own COPYRIGHT, kept in this
# repository for the version the manifest names (ahead of the distribution's
# revision). Another version has no file here, and stops the build until
# someone has read that version's.
musl=$(awk '$1 == ".musl" { print $2 }' "${manifest}")
if [ -n "${musl}" ]; then
  text="$(cd "$(dirname "$0")" && pwd)/notices/musl-${musl%%-*}-COPYRIGHT"
  [ -s "${text}" ] || { echo "licences.sh: the package links musl ${musl%%-*}, and this repository has no ${text##*/}" >&2; exit 1; }
  mkdir -p "${to}/licenses/musl"
  cp "${text}" "${to}/licenses/musl/COPYRIGHT"
  count=$((count + 1))
fi

# The same of a windows package and the MinGW-w64 runtime, which its curl
# is statically linked against and whose own notice says a program so linked
# carries it. The runtime is the one llvm-mingw's release builds, at a commit
# of mingw-w64 its build script names: the text is kept by that release.
mingw=$(awk '$1 == ".llvm-mingw" { print $2 }' "${manifest}")
if [ -n "${mingw}" ]; then
  text="$(cd "$(dirname "$0")" && pwd)/notices/LICENSE-mingw-w64-runtime-llvm-mingw-${mingw}"
  [ -s "${text}" ] || { echo "licences.sh: the package is built with llvm-mingw ${mingw}, and this repository has no ${text##*/}" >&2; exit 1; }
  mkdir -p "${to}/licenses/mingw-w64"
  cp "${text}" "${to}/licenses/mingw-w64/COPYING.MinGW-w64-runtime.txt"
  count=$((count + 1))
fi
echo "licences: ${count} libraries, each with its licence"
