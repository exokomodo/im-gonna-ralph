#!/usr/bin/env bats

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  cd "${TEST_TEMP_DIR}"
  mkdir -p .ralph
  echo "sample task" > .ralph/tasks
}

teardown() {
  # If a test failed, print .ralph logs to help debugging
  if [ "$BATS_TEST_RUNNING" = "" ]; then
    # not running inside bats runner
    :
  fi
  if [ -d ".ralph" ]; then
    echo "--- .ralph contents ---"
    find .ralph -type f -maxdepth 3 -print -exec sed -n '1,200p' {} \; || true
  fi
  rm -rf "${TEST_TEMP_DIR}"
}

@test "e2e: init then run completes task via backend stub" {
  # Ensure a clean start
  touch .gitignore

  # Create a simple backend that creates the top-level DONE file
  mkdir -p bin
  cat > bin/backend_complete.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
# create overall DONE file to indicate task completion
mkdir -p ./.ralph
echo "Agent: completed" > ./.ralph/agent_output.txt
touch ./.ralph/DONE
exit 0
SH
  chmod +x bin/backend_complete.sh

  export BACKEND="${TEST_TEMP_DIR}/bin/backend_complete.sh"
  export BACKEND_ARGS=""

  # Run init subcommand then run main; init uses init function when sourced, so run the script directly for main run
  run bash "${PROJECT_ROOT}/src/ralph.bash" init
  [ "$status" -eq 0 ]
  [ -d ".ralph" ]

  run bash "${PROJECT_ROOT}/src/ralph.bash" --no-sdd -n 3
  [ "$status" -eq 0 ]
  [ -f ".ralph/DONE" ]
  # iteration logs should exist
  iter_dir=$(find .ralph -maxdepth 1 -type d | sort | tail -n1)
  [ -n "$iter_dir" ]
}

@test "e2e: spec-driven mode recovers on second attempt" {
  mkdir -p .ralph/specs
  # create a spec that expects a DONE file to be created
  cat > .ralph/specs/010-e2e-recover.md <<'MD'
## Overview
A spec that only completes on the second backend invocation.

## Acceptance Criteria
- Fails first attempt, succeeds on second and creates .DONE
MD

  # Backend that only creates DONE on second invocation
  mkdir -p bin
  cat > bin/backend_e2e_count.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
COUNT_FILE=".backend_e2e_count"
if [ -f "$COUNT_FILE" ]; then
  count=$(cat "$COUNT_FILE")
else
  count=0
fi
count=$((count+1))
echo "$count" > "$COUNT_FILE"
if [ "$count" -lt 2 ]; then
  echo "Attempt $count: incomplete"
  exit 0
else
  mkdir -p ./.ralph/specs
  echo "Attempt $count: completed"
  touch ./.ralph/specs/010-e2e-recover.DONE
  exit 0
fi
SH
  chmod +x bin/backend_e2e_count.sh

  export BACKEND="${TEST_TEMP_DIR}/bin/backend_e2e_count.sh"
  export BACKEND_ARGS=""

  # Allow multiple iterations so agent runs twice
  run bash "${PROJECT_ROOT}/src/ralph.bash" -s .ralph/specs -n 3
  [ "$status" -eq 0 ]
  [ -f ".ralph/specs/010-e2e-recover.DONE" ]
}
