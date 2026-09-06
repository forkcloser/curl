# This file is the project's own — add recipes below. Keep the import: it
# mounts every shared limen task under `just do ...`.
import '.limen/just/main.just'

# ossein (farcloser's microVM container builder) wraps the linux legs of
# build-posix on macOS. It is not released yet, so it cannot be aqua-pinned
# like every other tool, and the hermetic PATH above hides any unpinned copy
# on purpose — so it is located explicitly, the way main.just captures
# BREW_BIN: an exported OSSEIN_BIN wins; otherwise the sibling checkout's
# `just build` output; otherwise the ambient PATH (captured here, above the
# hermetic override). Empty when absent — build-posix then fails with
# guidance. Replace with an aqua pin once ossein ships a release.
ossein_sibling := justfile_directory() / '../ossein/build/ossein'
export OSSEIN_BIN := env_var_or_default('OSSEIN_BIN', if path_exists(ossein_sibling) == 'true' { ossein_sibling } else { `command -v ossein || true` })

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
# container — ossein on macOS (OSSEIN_BIN above), podman on linux (CI);
# mac-arm64 needs a macOS host.
build-posix target:
    ./build-posix.sh {{ target }}
