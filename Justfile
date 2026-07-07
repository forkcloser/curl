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
# container (podman or docker); mac-arm64 needs a macOS host.
build-posix target:
    ./build-posix.sh {{ target }}
