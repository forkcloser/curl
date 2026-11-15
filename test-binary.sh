#!/usr/bin/env bash
#
# Basic sanity test of ONE built curl archive: it runs, reports the expected
# version, and completes a TLS 1.3 handshake — the reason this repository exists.
#
# Takes the leg (the SAME token the build/CI matrix uses) rather than
# auto-detecting: a binary can only be executed on its matching os/arch, and
# windows/arm64 in particular cannot be detected from git-bash — its userland
# reports x86_64 under emulation, which would silently test the amd64 binary
# and leave arm64 unexercised. CI runs this on the leg's own runner right
# after building it, so the archive is native and executable there.

set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=versions.env
. ./versions.env
curl_version="${CFW_PACKAGE%_*}"
# The archive carries the release's version (PACKAGE_VERSION, the tag's), by
# default the pinned curl's, as the build scripts name it.
package_version="${PACKAGE_VERSION:-${curl_version}}"

case "${1:-}" in
  linux-amd64)   goos='linux'   goarch='amd64' exe='curl' ;;
  linux-arm64)   goos='linux'   goarch='arm64' exe='curl' ;;
  mac-arm64)     goos='darwin'  goarch='arm64' exe='curl' ;;
  windows-amd64) goos='windows' goarch='amd64' exe='curl.exe' ;;
  windows-arm64) goos='windows' goarch='arm64' exe='curl.exe' ;;
  *) echo "usage: test-binary.sh {linux-amd64|linux-arm64|mac-arm64|windows-amd64|windows-arm64}" >&2; exit 2 ;;
esac

name="curl_${package_version}_${goos}_${goarch}"
archive="build/dist/${name}.tar.gz"
[ -f "$archive" ] || { echo "no archive to test: ${archive} (build it first)" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
tar -xzf "$archive" -C "$work"
bin="${work}/${name}/${exe}"
chmod +x "$bin" 2>/dev/null || true

echo "› $("$bin" --version | head -n1)"

# 1. Right tool, right version (trailing space pins the exact version, not a prefix).
"$bin" --version | head -n1 | grep -qF "curl ${curl_version} " \
  || { echo "version mismatch (want ${curl_version})" >&2; exit 1; }

# 2. TLS 1.3 — this repository's whole reason for existing. --tlsv1.3 sets the FLOOR,
# so a completed, verified request proves 1.3 was negotiated. The CA trust
# store is the host's to provide (not shipped here).
"$bin" --tlsv1.3 --silent --show-error --fail --output /dev/null https://github.com

# 3. The archive says what its curl links, and carries each library's terms:
# the manifest curl-for-win wrote, and for every library it names a licence
# under licenses/<library>/. The list is the manifest's, so a library a later
# package links cannot ship without its file.
manifest="${work}/${name}/BUILD-MANIFEST.txt"
[ -s "${manifest}" ] || { echo "no BUILD-MANIFEST.txt in the archive" >&2; exit 1; }
[ -s "${work}/${name}/COPYING.txt" ] || { echo "no COPYING.txt in the archive" >&2; exit 1; }
libraries=0
while read -r library; do
  found=''
  for file in "${work}/${name}/licenses/${library}"/*; do
    [ -s "${file}" ] && found=1
  done
  [ -n "${found}" ] || { echo "the archive links ${library} and carries no licence for it" >&2; exit 1; }
  libraries=$((libraries + 1))
done < <(./licences.sh --libraries "${manifest}")
[ "${libraries}" -gt 0 ] || { echo "the archive's manifest names no library" >&2; exit 1; }
# And what the binary itself reports linking is in that manifest: its TLS
# library, by the name curl prints.
"$bin" --version | head -n1 | grep -q 'LibreSSL/' || { echo "curl no longer reports LibreSSL: revisit this check" >&2; exit 1; }
grep -q '^libressl ' "${manifest}" || { echo "the manifest does not name libressl, which curl reports linking" >&2; exit 1; }

echo "✓ smoke ${1}: curl ${curl_version} runs · version OK · TLS 1.3 OK · ${libraries} libraries, each with its licence"
