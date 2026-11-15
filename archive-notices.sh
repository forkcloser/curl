#!/usr/bin/env bash
#
# Write licenses/NOTICES into the directory an archive is made from: the
# notices of the sources its curl links, as the sources state them.
#   archive-notices.sh <archive directory>
#   archive-notices.sh --parts <BUILD-MANIFEST.txt>
#
# licences.sh carries each library's own licence file, which is its project's
# summary and can be short of what the sources ask to be reproduced:
# LibreSSL's holds two texts and a sentence where its sources carry hundreds
# of notices of their own. notices.sh reads them out of the sources; this
# script gets it the sources.
#
# The same on every leg, the windows import included, which has no source
# tree: each library BUILD-MANIFEST.txt names is fetched from the url the
# manifest gives and verified against the sha256 curl-for-win itself builds
# from, its _versions.sh at CFW_COMMIT, read through git so that the commit
# id vouches for the file. The libraries are the manifest's, never typed: one
# this script has no directories for stops the build, so a library a later
# package links is read by someone before it ships. --parts prints the parts
# NOTICES must have for a manifest, for the smoke test to hold an archive to.

set -euo pipefail
export LC_ALL=C

cd "$(dirname "$0")"
# shellcheck source=versions.env
. ./versions.env

# directories_of <library>: the directories of its source tree that are
# linked into curl, "." for the tree's own files; "-" for a library that is
# data and has no source to read (its licence file is its whole statement).
# Nothing for a library not known here.
directories_of() {
  case "$1" in
    curl) echo "lib src include" ;;
    libressl) echo "crypto ssl include" ;;
    nghttp2 | nghttp3) echo "lib" ;;
    ngtcp2) echo "lib crypto" ;;
    libssh2) echo "src include" ;;
    brotli) echo "c" ;;
    zstd) echo "lib" ;;
    zlibng) echo ". arch" ;;
    libpsl) echo "src include" ;;
    psl | certdata) echo "-" ;;
    *) ;;
  esac
}

# libraries <manifest>: `<name> <version> <url>` of everything the curl
# links, curl included. A leading dot is the toolchain, and trurl is another
# program of the package, which this repository does not ship.
libraries() {
  awk '$1 !~ /^\./ && $1 != "trurl" && NF { print $1, $2, $3 }' "$1"
}

# part <library> <directory>: the heading of that directory's notices.
part() {
  if [ "$2" = . ]; then echo "$1"; else echo "$1 $2"; fi
}

if [ "${1:-}" = --parts ]; then
  while read -r name _ _; do
    dirs=$(directories_of "${name}")
    [ -n "${dirs}" ] || { echo "archive-notices.sh: no directories known for ${name}" >&2; exit 1; }
    [ "${dirs}" != - ] || continue
    for dir in ${dirs}; do part "${name}" "${dir}"; done
  done < <(libraries "${2:?a BUILD-MANIFEST.txt}")
  exit 0
fi

to=${1:?the archive directory}
manifest="${to}/BUILD-MANIFEST.txt"
[ -s "${manifest}" ] || { echo "archive-notices.sh: no BUILD-MANIFEST.txt in ${to}" >&2; exit 1; }

sources="build/sources"
mkdir -p "${sources}"

# curl-for-win's own pins, at the commit this repository tracks. Fetched by
# commit id into a repository of its own: git checks what it receives
# against that id.
pin="build/cfw-pin"
[ -d "${pin}" ] || git init --quiet --bare "${pin}"
git -C "${pin}" cat-file -e "${CFW_COMMIT}^{commit}" 2> /dev/null ||
  git -C "${pin}" fetch --quiet --depth 1 https://github.com/curl/curl-for-win "${CFW_COMMIT}"
git -C "${pin}" show "${CFW_COMMIT}:_versions.sh" > "${sources}/_versions.sh"

# pinned <NAME>_<FIELD>: the value _versions.sh exports under that name,
# read as text: the file is never run.
pinned() {
  sed -n "s/^export $1='\{0,1\}\([^']*\)'\{0,1\}\$/\1/p" "${sources}/_versions.sh"
}

pairs=()
while read -r name version url; do
  dirs=$(directories_of "${name}")
  [ -n "${dirs}" ] || { echo "archive-notices.sh: the package links ${name}, and this script does not know which of its directories to read" >&2; exit 1; }
  [ "${dirs}" != - ] || continue
  upper=$(printf '%s' "${name}" | tr '[:lower:]' '[:upper:]')
  sum=$(pinned "${upper}_HASH")
  [ -n "${sum}" ] || { echo "archive-notices.sh: curl-for-win ${CFW_COMMIT} pins no ${upper}_HASH" >&2; exit 1; }
  [ "$(pinned "${upper}_VER_")" = "${version}" ] || { echo "archive-notices.sh: the manifest has ${name} ${version}, curl-for-win ${CFW_COMMIT} pins $(pinned "${upper}_VER_")" >&2; exit 1; }
  tree="${sources}/${name}-${version}"
  if [ ! -f "${tree}/.verified-${sum}" ]; then
    file="${sources}/${name}-${version}.archive"
    curl --proto '=https' --tlsv1.2 -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o "${file}" "${url}"
    echo "${sum}  ${file}" | sha256sum -c - > /dev/null || { echo "archive-notices.sh: ${name} ${version}: sha256 mismatch against curl-for-win's pin" >&2; rm -f "${file}"; exit 1; }
    rm -rf "${tree}"
    mkdir -p "${tree}"
    tar -xf "${file}" -C "${tree}" --strip-components=1
    rm -f "${file}"
    touch "${tree}/.verified-${sum}"
  fi
  for dir in ${dirs}; do
    if [ "${dir}" = . ]; then pairs+=("$(part "${name}" .)=${tree}=1"); else pairs+=("$(part "${name}" "${dir}")=${tree}/${dir}"); fi
  done
  # What a source of this library names and leaves the terms of elsewhere:
  # written out in notices/, or taken from the library's own tree.
  case "${name}" in
    ngtcp2) pairs+=("PCG, of which ngtcp2 compiles a part:notices/pcg") ;;
    libssh2) pairs+=("PuTTY, from which libssh2 takes its Pageant code:notices/putty") ;;
    libpsl) pairs+=("Chromium, of which libpsl compiles a part:${tree}/src/LICENSE.chromium" "musl, from which libpsl takes a function:notices/musl") ;;
    *) ;;
  esac
done < <(libraries "${manifest}")
[ "${#pairs[@]}" -gt 0 ] || { echo "archive-notices.sh: ${manifest} names no library" >&2; exit 1; }

mkdir -p "${to}/licenses"
./notices.sh "${to}/licenses/NOTICES" "${pairs[@]}"
