#!/usr/bin/env bash
#
# Make an archive that is the same bytes whenever it is made from the same
# files, at the same commit.
#   archive.sh <parent directory> <name> <archive to write>
# writes <parent directory>/<name>/ as <archive to write>, a .tar.gz.
#   archive.sh --test
# One tree made twice, every way a builder can differ, gives one archive.
#
# Left to itself tar records what differs from one run to the next and says
# nothing of the content: the order the directory listed its entries in, the
# time each file was written, the builder's user and group, and modes cut by
# the builder's umask. Each is fixed here, so two builds of one commit give
# one archive, and a release's checksums can be had again by building its tag.

set -euo pipefail

if [ "${1:-}" = --test ]; then
  # The same nine entries, made in two orders, at two times, under two
  # umasks, with two sets of modes that agree on what is executable.
  self=$0
  cases=$(mktemp -d)
  trap 'rm -rf "${cases}"' EXIT
  (
    umask 022
    mkdir -p "${cases}/one/pkg/licenses/zlib" "${cases}/one/pkg/licenses/brotli"
    printf 'binary\n' > "${cases}/one/pkg/curl"
    chmod 0755 "${cases}/one/pkg/curl"
    printf 'copying\n' > "${cases}/one/pkg/COPYING.txt"
    printf 'manifest\n' > "${cases}/one/pkg/BUILD-MANIFEST.txt"
    printf 'z\n' > "${cases}/one/pkg/licenses/zlib/LICENSE"
    printf 'b\n' > "${cases}/one/pkg/licenses/brotli/LICENSE"
  )
  (
    umask 077
    mkdir -p "${cases}/two/pkg/licenses/brotli"
    printf 'b\n' > "${cases}/two/pkg/licenses/brotli/LICENSE"
    mkdir -p "${cases}/two/pkg/licenses/zlib"
    printf 'z\n' > "${cases}/two/pkg/licenses/zlib/LICENSE"
    printf 'manifest\n' > "${cases}/two/pkg/BUILD-MANIFEST.txt"
    printf 'copying\n' > "${cases}/two/pkg/COPYING.txt"
    printf 'binary\n' > "${cases}/two/pkg/curl"
    chmod 0700 "${cases}/two/pkg/curl"
    touch -t 202001010101 "${cases}/two/pkg/curl" "${cases}/two/pkg/licenses" "${cases}/two/pkg"
  )
  failed=0
  SOURCE_DATE_EPOCH=1700000000 "${self}" "${cases}/one" pkg "${cases}/one.tar.gz"
  SOURCE_DATE_EPOCH=1700000000 "${self}" "${cases}/two" pkg "${cases}/two.tar.gz"
  cmp -s "${cases}/one.tar.gz" "${cases}/two.tar.gz" || { echo "archive.sh: one tree made two ways gives two archives" >&2; failed=1; }
  # What two trees of one builder cannot differ in, read from the archive:
  # the entries in the order of their names, whatever the directory gave,
  # and no owner but 0.
  tar -tzf "${cases}/one.tar.gz" > "${cases}/names"
  LC_ALL=C sort "${cases}/names" | cmp -s - "${cases}/names" || { echo "archive.sh: the entries are not in the order of their names" >&2; failed=1; }
  [ "$(grep -c . "${cases}/names")" = 9 ] || { echo "archive.sh: the archive does not hold the nine entries of the tree" >&2; failed=1; }
  tar -tvzf "${cases}/one.tar.gz" > "${cases}/listing"
  if awk '$2 != "0/0" { found = 1 } END { exit !found }' "${cases}/listing"; then echo "archive.sh: an entry has an owner other than 0/0" >&2; failed=1; fi
  # Another time is another archive: the time is the one given, not none.
  SOURCE_DATE_EPOCH=1700000001 "${self}" "${cases}/one" pkg "${cases}/later.tar.gz"
  ! cmp -s "${cases}/one.tar.gz" "${cases}/later.tar.gz" || { echo "archive.sh: the time given is not the time recorded" >&2; failed=1; }
  [ "${failed}" -eq 0 ] || exit 1
  echo "archive.sh: one tree, two ways, one archive"
  exit 0
fi

parent=${1:?the directory that holds the tree to archive}
name=${2:?the tree, which is also the name inside the archive}
out=${3:?the archive to write}

# The time of the commit being built, the same for everyone who builds it;
# SOURCE_DATE_EPOCH names another, as everywhere.
epoch="${SOURCE_DATE_EPOCH:-$(git -C "$(dirname "$0")" log -1 --format=%ct)}"
[ -n "${epoch}" ] || { echo "archive.sh: no commit time to date the archive with" >&2; exit 1; }

chmod -R u=rwX,go=rX "${parent:?}/${name:?}"
tar --sort=name --mtime="@${epoch}" --owner=0 --group=0 --numeric-owner -czf "${out}" -C "${parent}" "${name}"
