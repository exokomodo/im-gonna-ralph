#!/usr/bin/env bats

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

  # Create a sourceable copy of ralph.bash with `main "$@"` removed
  RALPH_LIB="${TEST_TEMP_DIR}/ralph_lib.bash"
  sed '/^main "\$@"$/d' "${PROJECT_ROOT}/src/ralph.bash" > "${RALPH_LIB}"

  cd "${TEST_TEMP_DIR}"
  mkdir -p .ralph
  echo "sample task" > .ralph/tasks
}

teardown() {
  rm -rf "${TEST_TEMP_DIR}"
}

@test "usage exits 0 with -h" {
  run bash "${PROJECT_ROOT}/src/ralph.bash" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ralph"* ]]
}

@test "unknown subcommand exits non-zero" {
  run bash "${PROJECT_ROOT}/src/ralph.bash" bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown subcommand: bogus"* ]]
}

@test "init creates .ralph directory" {
  rm -rf .ralph
  # Need a .gitignore for init to append to
  touch .gitignore
  source "${RALPH_LIB}"
  run init
  [ "$status" -eq 0 ]
  [ -d ".ralph" ]
}

@test "init appends .ralph to .gitignore" {
  rm -rf .ralph
  echo "node_modules" > .gitignore
  source "${RALPH_LIB}"
  run init
  [ "$status" -eq 0 ]
  grep -q "^.ralph$" .gitignore
}

@test "init skips .gitignore entry if already present" {
  rm -rf .ralph
  printf "node_modules\n.ralph\n" > .gitignore
  source "${RALPH_LIB}"
  run init
  [ "$status" -eq 0 ]
  # Count occurrences — should still be exactly 1
  count=$(grep -c "^.ralph$" .gitignore)
  [ "$count" -eq 1 ]
}

@test "-n flag rejects non-integer" {
  run bash "${PROJECT_ROOT}/src/ralph.bash" -n abc
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be a positive integer"* ]]
}

@test "-f flag sets task file" {
  source "${RALPH_LIB}"
  parse-args -f myfile.txt
  [ "${TASK_FILE}" = "myfile.txt" ]
}

@test "main exits 0 if .done file exists" {
  mkdir -p .ralph
  touch .ralph/.done
  run bash "${PROJECT_ROOT}/src/ralph.bash"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Task already completed"* ]]
}

@test "main with --force removes .done file and continues" {
  mkdir -p .ralph
  touch .ralph/.done
  echo "sample task" > .ralph/tasks
  # --force removes .done, then main will fail because copilot is not available.
  # We just verify .done was removed.
  run bash "${PROJECT_ROOT}/src/ralph.bash" --force
  [ ! -f ".ralph/.done" ]
}

@test "--no-sdd flag is parsed correctly" {
  source "${RALPH_LIB}"
  parse-args --no-sdd
  [ "${NO_SDD}" = "true" ]
}

@test "-s flag sets SPECS_DIR" {
  source "${RALPH_LIB}"
  parse-args -s /tmp/myspecs
  [ "${SPECS_DIR}" = "/tmp/myspecs" ]
}

@test "generate-specs subcommand sets GENERATE_SPECS_ONLY" {
  source "${RALPH_LIB}"
  parse-args generate-specs
  [ "${GENERATE_SPECS_ONLY}" = "true" ]
}

@test "init creates .ralph/specs directory" {
  rm -rf .ralph
  touch .gitignore
  source "${RALPH_LIB}"
  run init
  [ "$status" -eq 0 ]
  [ -d ".ralph/specs" ]
}

@test "SDD mode detected when specs dir has .md files" {
  source "${RALPH_LIB}"
  mkdir -p .ralph/specs
  echo "## Overview" > .ralph/specs/001-test.md
  # SDD_MODE should be false initially
  [ "${SDD_MODE}" = "false" ]
  # After detection logic: simulate what main does
  if [[ -d "${DEFAULT_SPECS_DIR}" && "${NO_SDD}" != true ]]; then
    SPECS_DIR="${DEFAULT_SPECS_DIR}"
    SDD_MODE=true
  fi
  [ "${SDD_MODE}" = "true" ]
  [ "${SPECS_DIR}" = "${DEFAULT_SPECS_DIR}" ]
}

@test "ralph-loop writes iteration file" {
  source "${RALPH_LIB}"
  VERBOSE=false
  IMPORT_RUN=""
  ITERATIONS=1

  local iter_dir="${TEST_TEMP_DIR}/.ralph/run1"
  mkdir -p "${iter_dir}"

  # Stub copilot to avoid real calls
  copilot() { echo "stub output"; }
  export -f copilot

  DONE_FILE="${TEST_TEMP_DIR}/.ralph/.done"
  touch "${DONE_FILE}"

  run ralph-loop 1 "${TEST_TEMP_DIR}/.ralph/tasks" "${iter_dir}"
  [ -f "${iter_dir}/iteration_1.txt" ]
}
