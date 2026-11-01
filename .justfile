# This file is the project's own — add recipes below. Keep the import: it
# mounts every shared limen task under `just do ...`.
import '.limen/just/main.just'

# The FIRST recipe defined here becomes `just`'s default (until then, the
# shared default lists everything).
lint: do::lint::default
fix: do::fix::default

# Basic sanity test of ONE built binary (build it first): it runs, reports the
# expected version, and does a TLS 1.3 handshake. Takes the leg (linux-amd64,
# linux-arm64, mac-arm64, windows-amd64, windows-arm64) — it can only be run on
# a matching runner, so CI executes it on each leg's own runner after building.
test leg:
    ./test-binary.sh {{ leg }}

# Import + sigstore-verify the windows packages from curl-for-win, and
# repackage them into this repo's release layout (see README).
build-windows:
    ./import-windows.sh

# Build a posix leg (linux-amd64, linux-arm64, mac-arm64) with curl-for-win's
# machinery at the audited pin. Linux legs run in their digest-pinned debian
# container under docker; mac-arm64 needs a macOS host. PACKAGE_VERSION names
# the archive (the tag's version, 8.22.0.1 for a rebuild); the default is the
# pinned curl's.
build-posix target:
    ./build-posix.sh {{ target }}

# The release assets' companions, per limen's signing and provenance policy
# (book/releasing.md): one SPDX JSON SBOM per archive by syft from the
# toolset, checksums.txt over the archives and the SBOMs, and cosign's
# keyless bundle over checksums.txt, signed with the workflow's OIDC identity
# and logged in Rekor. The release workflow's publish job runs it on the
# downloaded archives; a local run has no OIDC token and leaves checksums.txt
# unsigned, saying so. The directory is one inside the repository (dist, or
# under .build): the toolset's binaries resolve against the project's policy
# from the working directory, and the recipe does not leave it.
[doc('SBOM per archive, checksums.txt and its keyless cosign bundle, over a directory of archives')]
release-assets dir:
    #!/usr/bin/env bash
    set -euo pipefail
    dir='{{ dir }}'
    shopt -s nullglob
    archives=("$dir"/*.tar.gz)
    [ "${#archives[@]}" -gt 0 ] || { echo "release-assets: no archive in $dir" >&2; exit 1; }
    for archive in "${archives[@]}"; do
        SYFT_CHECK_FOR_APP_UPDATE=false SYFT_FILE_METADATA_CATALOGER_ENABLED=true \
            syft scan "file:$archive" --source-name "$(basename "$archive")" -o "spdx-json=$archive.sbom.json"
    done
    names=()
    for f in "$dir"/*.tar.gz "$dir"/*.sbom.json; do names+=("$(basename "$f")"); done
    (cd "$dir" && sha256sum -- "${names[@]}" > checksums.txt)
    if [ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]; then
        cosign sign-blob --yes --bundle "$dir/checksums.txt.sigstore.json" "$dir/checksums.txt"
    else
        echo "release-assets: no OIDC token, $dir/checksums.txt is not signed (a local run)"
    fi

# --- added by limen fix: the recipe the security workflow runs ---
security: do::security::default
