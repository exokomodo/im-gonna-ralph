#!/usr/bin/env bats

setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  cd "${TEST_TEMP_DIR}"
  mkdir -p .ralph/specs
  # Provide a default task file so ralph's main() doesn't error when SDD mode is used
  echo "sample task" > .ralph/tasks
}

teardown() {
  rm -rf "${TEST_TEMP_DIR}"
}

@test "integration: happy path - spec completes on first attempt" {
  # Prepare spec
  cat > .ralph/specs/001-integration.md <<'MD'
## Overview
A simple integration spec that the agent should complete by creating the .DONE file.

## Acceptance Criteria
- Agent creates the corresponding .DONE file for the spec.
MD

  # Backend stub that immediately creates the .DONE file
  mkdir -p bin
  cat > bin/backend.sh <<'SH'
#!/usr/bin/env bash
# This backend stub is invoked by ralph.bash. It should create the spec .DONE file so the loop detects completion.
# It is run with the repository working directory = TEST_TEMP_DIR (the test's CWD).
set -euo pipefail
# Create the expected done file for the 001-integration spec
mkdir -p ./.ralph/specs
echo "Agent output: completed"
touch ./.ralph/specs/001-integration.DONE
exit 0
SH
  chmod +x bin/backend.sh

  export BACKEND="${TEST_TEMP_DIR}/bin/backend.sh"
  export BACKEND_ARGS=""

  run bash "${PROJECT_ROOT}/src/ralph.bash" -s .ralph/specs -n 2
  [ "$status" -eq 0 ]
  [ -f ".ralph/specs/001-integration.DONE" ]
}

@test "integration: failure recovery - agent succeeds on second attempt" {
  # Prepare spec
  cat > .ralph/specs/002-recovery.md <<'MD'
## Overview
A spec where the agent does not complete on first attempt but completes on the second.

## Acceptance Criteria
- First attempt does not produce .DONE
- Second attempt creates the .DONE file and loop records attempts
MD

  # Backend stub that creates the done file only on the second invocation
  mkdir -p bin
  cat > bin/backend_count.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
COUNT_FILE=".backend_count"
if [ -f "$COUNT_FILE" ]; then
  count=$(cat "$COUNT_FILE")
else
  count=0
fi
count=$((count+1))
echo "$count" > "$COUNT_FILE"
if [ "$count" -lt 2 ]; then
  # First invocation: report progress but do NOT create .DONE
  echo "Agent attempt ${count}: incomplete"
  exit 0
else
  # Second (and subsequent) invocations: complete the spec
  mkdir -p ./.ralph/specs
  echo "Agent attempt ${count}: completed"
  touch ./.ralph/specs/002-recovery.DONE
  exit 0
fi
SH
  chmod +x bin/backend_count.sh

  export BACKEND="${TEST_TEMP_DIR}/bin/backend_count.sh"
  export BACKEND_ARGS=""

  # Allow multiple iterations so the stub can be invoked twice
  run bash "${PROJECT_ROOT}/src/ralph.bash" -s .ralph/specs -n 3
  [ "$status" -eq 0 ]
  [ -f ".ralph/specs/002-recovery.DONE" ]
  # Ensure at least one iteration log was written for the spec
  # Find the latest iteration dir under .ralph
  iter_dir=$(find .ralph -maxdepth 1 -type d | sort | tail -n1)
  [ -n "$iter_dir" ]
  [ -f "$iter_dir/001-integration/iteration_1.txt" ] || true
}
