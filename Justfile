# This file is the project's own — add recipes below. Keep the import: it
# mounts every shared limen task under `just do ...`.
import '.limen/just/main.just'

# The FIRST recipe defined here becomes `just`'s default (until then, the
# shared default lists everything). The aggregates CI runs, for example:
lint: do::lint::default
fix: do::fix::default
test:

# Import + sigstore-verify the windows packages from curl-for-win, and
# repackage them into this repo's release layout (see README).
import-windows:
    ./import-windows.sh

# Build a posix leg (linux-amd64, linux-arm64, mac universal) with
# curl-for-win's machinery at the audited pin. Linux legs run in their
# digest-pinned debian container (podman or docker); mac needs a macOS host.
build-posix target:
    ./build-posix.sh {{ target }}
