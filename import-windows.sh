#!/usr/bin/env bash
#
# Import the windows curl binaries from curl-for-win — the curl project's own
# reproducible-build channel (its windows packages are the official curl
# builds) — verifying each package's sigstore bundle against the VENDORED
# public key before repackaging into this repository's release layout.
#
# The key (cosign.pub.asc) was vendored from the pinned CFW_COMMIT and
# cross-checked against the copy embedded in curl-for-win's README at the
# same commit; bumping the pin re-runs that check (see README).

set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=versions.env
. ./versions.env
CURL_VERSION="${CFW_PACKAGE%_*}"
CFW_REV="${CFW_PACKAGE##*_}"
# The archives carry the release's version: the tag's (PACKAGE_VERSION,
# e.g. 8.22.0 or 8.22.0.1 for a rebuild of the same curl) or, by default, the
# pinned curl's. A tag that names another curl than the pin is refused.
package_version="${PACKAGE_VERSION:-${CURL_VERSION}}"
./package-version.sh "${CURL_VERSION}" "${package_version}"

out="build/dist"
mkdir -p "$out"

for arch in amd64 arm64; do
  case "$arch" in
    amd64) cpu='win64' ;;
    arm64) cpu='win64a' ;;
  esac

  pkg="curl-${CURL_VERSION}_${CFW_REV}-${cpu}-mingw.tar.xz"
  url="https://curl.se/windows/dl-${CURL_VERSION}_${CFW_REV}/${pkg}"
  work="build/import-${arch}"

  rm -rf "$work"
  mkdir -p "$work"

  echo "› fetching ${pkg}"
  curl --proto '=https' --tlsv1.2 -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o "${work}/${pkg}" "$url"
  curl --proto '=https' --tlsv1.2 -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o "${work}/${pkg}.sigstore" "${url}.sigstore"

  echo "› verifying sigstore bundle against the vendored key"
  cosign verify-blob --key cosign.pub.asc --bundle "${work}/${pkg}.sigstore" "${work}/${pkg}"

  tar -xJf "${work}/${pkg}" -C "$work"

  src="${work}/curl-${CURL_VERSION}_${CFW_REV}-${cpu}-mingw"
  name="curl_${package_version}_windows_${arch}"
  mkdir -p "${work}/${name}"
  # No CA bundle: curl-for-win stopped packaging one for windows, where this
  # build trusts the Windows certificate store. COPYING is the license.
  cp "${src}/bin/curl.exe" "${src}/COPYING.txt" "${work}/${name}/"
  # The libraries the binary links travel with it, each with its terms.
  ./licences.sh "${src}" "${work}/${name}"
  ./archive.sh "$work" "$name" "${out}/${name}.tar.gz"
  echo "✓ ${out}/${name}.tar.gz"
done
