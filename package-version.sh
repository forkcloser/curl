#!/usr/bin/env bash
#
# Say whether a package version names the pinned release.
#   package-version.sh <release> <candidate>
# The release is the pinned curl's (8.23.0). A package is that, or a rebuild
# of it without a new curl (new libraries, a new curl-for-win revision): a
# fourth segment, a number from 1 and written one way, so that two tags never name
# one rebuild (8.23.0.1 and 8.23.0.01) and none sorts where it should not.
# Exit 0 when the candidate is one of those, 1 with a line on stderr when not.
#
#   package-version.sh --test
# The rule over its edges, each expected answer stated.
set -euo pipefail

names_release() {
  local release=$1 candidate=$2 rest
  case "${candidate}" in
    "${release}") return 0 ;;
    "${release}".*) rest=${candidate#"${release}".} ;;
    *) return 1 ;;
  esac
  case "${rest}" in
    '' | 0* | *[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

if [ "${1:-}" = --test ]; then
  failed=0
  while read -r want candidate; do
    if names_release 8.23.0 "${candidate}"; then got=accept; else got=refuse; fi
    [ "${got}" = "${want}" ] || { echo "package-version: '${candidate}' is ${got}ed, want ${want}" >&2; failed=1; }
  done <<'CASES'
accept 8.23.0
accept 8.23.0.1
accept 8.23.0.12
accept 8.23.0.10
refuse 8.23.0.
refuse 8.23.0.0
refuse 8.23.0.01
refuse 8.23.0.rc1
refuse 8.23.0.1.2
refuse 8.23.0.1x
refuse 8.23.0-1
refuse 8.23.00
refuse 8.24.0
refuse 8.22.0.2
refuse 8.23
refuse v8.23.0
refuse 8.23.0.1.
CASES
  # No candidate at all, and one with a space in it, which `read` above
  # cannot carry.
  if names_release 8.23.0 ''; then echo "package-version: the empty version is accepted" >&2; failed=1; fi
  if names_release 8.23.0 '8.23.0.1 '; then echo "package-version: a trailing space is accepted" >&2; failed=1; fi
  [ "${failed}" -eq 0 ] || exit 1
  echo "package-version: 19 cases as expected"
  exit 0
fi

release=${1:?the pinned curl, e.g. 8.23.0}
candidate=${2:?the package version}
names_release "${release}" "${candidate}" || {
  echo "the package version ${candidate} does not name the pinned release ${release} (${release}, or ${release}.N for a rebuild, N from 1)" >&2
  exit 1
}
