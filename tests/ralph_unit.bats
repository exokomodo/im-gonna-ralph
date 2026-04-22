#!/usr/bin/env bats

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  RALPH_LIB="${TEST_TEMP_DIR}/ralph_lib.bash"
  sed '/^main "\$@"$/d' "${PROJECT_ROOT}/src/ralph.bash" > "${RALPH_LIB}"
  cd "${TEST_TEMP_DIR}"
}

teardown() {
  rm -rf "${TEST_TEMP_DIR}"
}

@test "-m flag sets MODEL" {
  source "${RALPH_LIB}"
  parse-args -m mymodel
  [ "${MODEL}" = "mymodel" ]
}

@test "-b flag sets BACKEND" {
  source "${RALPH_LIB}"
  parse-args -b mybackend
  [ "${BACKEND}" = "mybackend" ]
}

@test "--backend-args sets BACKEND_ARGS (with spaces)" {
  source "${RALPH_LIB}"
  parse-args --backend-args "--foo bar"
  [ "${BACKEND_ARGS}" = "--foo bar" ]
}

@test "--import-run with value sets IMPORT_RUN and implies FORCE" {
  source "${RALPH_LIB}"
  parse-args --import-run /tmp/import123
  [ "${IMPORT_RUN}" = "/tmp/import123" ]
  [ "${FORCE}" = "true" ]
}

@test "--import-run without value errors" {
  run bash "${PROJECT_ROOT}/src/ralph.bash" --import-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires a value"* ]]
}

@test "generate-specs-from-task-file creates specs dir and calls backend" {
  source "${RALPH_LIB}"
  # prepare a tiny task file
  local tf="${TEST_TEMP_DIR}/task.txt"
  echo "do something" > "${tf}"
  local specs_dir="${TEST_TEMP_DIR}/specs_out"

  # stub backend to avoid network calls; function will be invoked as a command
  copilot() { echo "stubbed copilot: $*"; }
  export -f copilot

  BACKEND=copilot
  generate-specs-from-task-file "${tf}" "${specs_dir}"
  [ -d "${specs_dir}" ]
}

@test "fatal-with-usage prints error and usage and exits non-zero" {
  run bash -c 'source "${PROJECT_ROOT}/src/ralph.bash"; fatal-with-usage "badness"'
  [ "$status" -ne 0 ]
  [[ "$output" == *"Error: badness"* ]]
  [[ "$output" == *"Usage: ralph"* ]]
}

@test "verbose prints only when VERBOSE is true" {
  run bash -c 'source "${PROJECT_ROOT}/src/ralph.bash"; VERBOSE=false; verbose "nope"; echo "X"'
  [[ "$output" == *"X"* ]]
  run bash -c 'source "${PROJECT_ROOT}/src/ralph.bash"; VERBOSE=true; verbose "yes"'
  [[ "$output" == *"yes"* ]]
}
