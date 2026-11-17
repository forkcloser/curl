#!/usr/bin/env bash
#
# The caps a build runs under, so that it never takes the whole machine it
# runs on: sourced by build-posix.sh.
#
#   BUILD_JOBS     parallel jobs of one make, ninja or cmake build (default 4)
#   BUILD_TIMEOUT  wall clock of a leg's build, as timeout(1) takes it (default 30m)
#   BUILD_CPUS     processors of the linux legs' container (default 4, or
#                  the host's count where it has fewer)
#   BUILD_MEMORY   its memory, in docker's units (default 8g)
#
# The mac leg has no container and macOS no limit a process can be held to:
# its memory is bounded by the job count alone.
#
#   build-caps.sh --test  runs this file's own test

build_jobs="${BUILD_JOBS:-4}"
build_timeout="${BUILD_TIMEOUT:-30m}"
# No more processors than the host has: docker refuses a container more.
build_host_cpus=$( (getconf _NPROCESSORS_ONLN || nproc) 2> /dev/null || echo 4)
build_cpus="${BUILD_CPUS:-$((build_host_cpus < 4 ? build_host_cpus : 4))}"
build_memory="${BUILD_MEMORY:-8g}"
case "${build_jobs}" in
  '' | *[!0-9]* | 0*)
    echo "BUILD_JOBS must be a whole number above 0, not '${build_jobs}'" >&2
    # Sourced or run, either way the build stops here.
    # shellcheck disable=SC2317 # exit is reached when the file is run
    return 2 2> /dev/null || exit 2
    ;;
  *) ;;
esac

# capped <command...>: the command, stopped when it outlasts BUILD_TIMEOUT.
# timeout is the pinned coreutils': it signals the command's whole process
# group, so a make's compilers go with it.
capped() {
  local status=0
  timeout "${build_timeout}" "$@" || status=$?
  [ "${status}" -ne 124 ] || echo "build-caps: stopped after ${build_timeout} (BUILD_TIMEOUT): $*" >&2
  return "${status}"
}

# job_caps: the job count, in the two names curl-for-win's build reads it
# by. CW_JOBS is its own, for make; its cmake builds pass no count, and ninja
# then takes every processor: CMAKE_BUILD_PARALLEL_LEVEL is the count
# `cmake --build` falls back to.
job_caps() {
  export CW_JOBS="${build_jobs}" CMAKE_BUILD_PARALLEL_LEVEL="${build_jobs}"
}

# capped_docker_run <arguments...>: docker run, sized. The time is the
# caller's to set inside the container; a container that ends with timeout's
# status is said to have been stopped.
capped_docker_run() {
  local status=0
  docker run --cpus "${build_cpus}" --memory "${build_memory}" "$@" || status=$?
  [ "${status}" -ne 124 ] || echo "build-caps: the container was stopped after ${build_timeout} (BUILD_TIMEOUT)" >&2
  return "${status}"
}

[ "${1:-}" = '--test' ] && [ "${BASH_SOURCE[0]}" = "$0" ] || return 0 2> /dev/null || exit 0

set -euo pipefail
cd "$(dirname "$0")"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
cases=0
# check <what> <got> <want>
check() {
  cases=$((cases + 1))
  [ "$2" = "$3" ] || { echo "build-caps: $1: got '$2', want '$3'" >&2; exit 1; }
}

# The job count reaches the build, and the container its size: an env and a
# docker that say what they were given.
mkdir "${work}/bin"
printf '#!/bin/sh\necho "docker $*"\n' > "${work}/bin/docker"
chmod 0755 "${work}/bin/docker"
# said <variable assignments, or none> -- <command...>: what the command printed.
said() {
  local set=()
  while [ "$1" != -- ]; do
    set+=("$1")
    shift
  done
  shift
  env -u BUILD_JOBS -u BUILD_CPUS -u BUILD_MEMORY -u CW_JOBS -u CMAKE_BUILD_PARALLEL_LEVEL \
    ${set[@]+"${set[@]}"} PATH="${work}/bin:${PATH}" bash -c '. ./build-caps.sh && "$@"' - "$@"
}
# shellcheck disable=SC2016 # the variables are the inner shell's to expand
jobs_seen='job_caps; echo "$CW_JOBS $CMAKE_BUILD_PARALLEL_LEVEL"; sh -c "echo \$CW_JOBS \$CMAKE_BUILD_PARALLEL_LEVEL"'
check 'the job count, by default' "$(said -- eval "${jobs_seen}" | tr '\n' ' ')" '4 4 4 4 '
check 'the job count, BUILD_JOBS=2' "$(said BUILD_JOBS=2 -- eval "${jobs_seen}" | tr '\n' ' ')" '2 2 2 2 '
host_cpus=$( (getconf _NPROCESSORS_ONLN || nproc) 2> /dev/null || echo 4)
check 'the container, by default' "$(said -- capped_docker_run --rm image)" "docker run --cpus $((host_cpus < 4 ? host_cpus : 4)) --memory 8g --rm image"
check 'the container, sized' "$(said BUILD_CPUS=2 BUILD_MEMORY=3g -- capped_docker_run --rm image)" 'docker run --cpus 2 --memory 3g --rm image'

# A job count that is not one stops the build before it starts.
for bad in 0 -1 many 04 ''; do
  status=0
  BUILD_JOBS="${bad}" bash -c '. ./build-caps.sh && echo went on' > "${work}/out" 2> /dev/null || status=$?
  if [ "${bad}" = '' ]; then
    # Empty is unset: the default.
    check 'BUILD_JOBS empty' "$(cat "${work}/out")" 'went on'
  else
    check "BUILD_JOBS=${bad} is refused" "${status}:$(cat "${work}/out")" '2:'
  fi
done

# A step that outlasts BUILD_TIMEOUT is stopped, says so, and takes what it
# started with it.
status=0
BUILD_TIMEOUT=1s bash -c '. ./build-caps.sh && capped sh -c "sleep 60 & echo \$! > \"$1\"; wait"' - "${work}/pid" 2> "${work}/err" || status=$?
check 'a step past BUILD_TIMEOUT' "${status}" 124
grep -q 'stopped after 1s (BUILD_TIMEOUT)' "${work}/err" || { echo "build-caps: a stopped step does not say so" >&2; exit 1; }
sleep 1
if kill -0 "$(cat "${work}/pid")" 2> /dev/null; then
  kill "$(cat "${work}/pid")"
  echo "build-caps: a stopped step left what it started running" >&2
  exit 1
fi
cases=$((cases + 2))
# A step within it keeps its own status.
status=0
bash -c '. ./build-caps.sh && capped sh -c "exit 7"' || status=$?
check 'a failing step keeps its status' "${status}" 7

# build-posix.sh starts its container through capped_docker_run alone, hands
# both legs the job count, and holds both to the time.
if grep -nE '(^|[^_a-z])docker run' build-posix.sh | grep -vE '^[0-9]+:[[:space:]]*#' > "${work}/bare"; then
  cat "${work}/bare" >&2
  echo "build-caps: build-posix.sh runs docker outside the caps" >&2
  exit 1
fi
[ "$(grep -c 'capped_docker_run' build-posix.sh)" -eq 1 ] || { echo "build-caps: build-posix.sh does not start its container through capped_docker_run" >&2; exit 1; }
[ "$(grep -c '^job_caps$' build-posix.sh)" -eq 1 ] || { echo "build-caps: build-posix.sh does not set the job count" >&2; exit 1; }
[ "$(grep -cE '(capped|timeout "\$\{build_timeout\}") ' build-posix.sh)" -ge 2 ] || { echo "build-caps: build-posix.sh does not hold both legs to BUILD_TIMEOUT" >&2; exit 1; }
cases=$((cases + 4))
echo "build-caps: ${cases} cases as expected"
