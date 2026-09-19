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
# shellcheck source=versions.env disable=SC1091
. ./versions.env
CURL_VERSION="${CFW_PACKAGE%_*}"
CFW_REV="${CFW_PACKAGE##*_}"

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
  name="curl_${CURL_VERSION}_windows_${arch}"
  mkdir -p "${work}/${name}"
  # curl.exe looks for the CA bundle beside itself; COPYING is the license.
  cp "${src}/bin/curl.exe" "${src}/bin/curl-ca-bundle.crt" "${src}/COPYING.txt" "${work}/${name}/"
  tar -czf "${out}/${name}.tar.gz" -C "$work" "$name"
  echo "✓ ${out}/${name}.tar.gz"
done
