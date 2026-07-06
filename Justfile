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

# Build a posix leg (linux static-musl, mac universal) with curl-for-win's
# machinery at the audited pin. Meant for CI runners — the underlying entry
# scripts provision podman containers / homebrew packages.
build-posix target:
    ./build-posix.sh {{ target }}
