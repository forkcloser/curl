# This file is the project's own — add recipes below. Keep the import: it
# mounts every shared limen task under `just do ...`.
import '.limen/just/main.just'

# The FIRST recipe defined here becomes `just`'s default (until then, the
# shared default lists everything). The aggregates CI runs, for example:
lint: do::lint::default
test:
