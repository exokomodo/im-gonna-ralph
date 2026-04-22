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

@test "-n flag with non-numeric value errors" {
  run bash -c "source \"${PROJECT_ROOT}/src/ralph.bash\"; parse-args -n abc"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be a positive integer"* ]]
}

@test "-f flag without value errors" {
  run bash "${PROJECT_ROOT}/src/ralph.bash" -f
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires a value"* ]]
}

@test "--sdd-model sets SDD_MODEL" {
  source "${RALPH_LIB}"
  parse-args --sdd-model testmodel
  [ "${SDD_MODEL}" = "testmodel" ]
}

@test "--no-sdd sets NO_SDD true" {
  source "${RALPH_LIB}"
  parse-args --no-sdd
  [ "${NO_SDD}" = "true" ]
}

@test "init adds .ralph to .gitignore when .gitignore exists" {
  # prepare a repo-like dir
  echo "node_modules" > .gitignore
  source "${RALPH_LIB}"
  init
  [ -d "$(pwd)/.ralph" ]
  grep -q "^.ralph$" .gitignore
}

@test "fatal prints error and exits non-zero" {
  run bash -c "source \"${PROJECT_ROOT}/src/ralph.bash\"; fatal \"boom\""
  [ "$status" -ne 0 ]
  [[ "$output" == *"Error: boom"* ]]
}
