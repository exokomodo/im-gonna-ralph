#! /usr/bin/env bash

set -euo pipefail

STDIN=/dev/stdin

DEFAULT_MODEL=gpt-5-mini
MODEL="${MODEL:-$DEFAULT_MODEL}"
FORCE=false
VERBOSE=false
DEFAULT_ITERATIONS=10
ITERATIONS="${ITERATIONS:-$DEFAULT_ITERATIONS}"
INIT=false
TASK_FILE=""
RALPH_DIR="$(pwd)/.ralph"
DONE_FILE="${RALPH_DIR}/DONE"
DEFAULT_TASK_FILE="${RALPH_DIR}/tasks"
IMPORT_RUN=""
DEFAULT_BACKEND=copilot
BACKEND="${BACKEND:-$DEFAULT_BACKEND}"
DEFAULT_BACKEND_ARGS="--allow-all-tools --allow-all-urls"
BACKEND_ARGS="${BACKEND_ARGS:-$DEFAULT_BACKEND_ARGS}"
SPECS_DIR=""
SDD_MODE=false
NO_SDD=false
GENERATE_SPECS_ONLY=false
SDD_MODEL=""
DEFAULT_SPECS_DIR="${RALPH_DIR}/specs"

export COPILOT_CUSTOM_INSTRUCTIONS_DIRS="${COPILOT_CUSTOM_INSTRUCTIONS_DIRS:-${HOME}/.agents/rules}"

usage() {
	cat <<- EOF
		Usage: ralph [options] [subcommand]

		Options:
		    -h, --help                   Show this help message and exit
		    -v, --verbose                Enable verbose output
		    -f <file>, --file <file>     Specify a task file (default: read from stdin, or .ralph/$(basename "${DEFAULT_TASK_FILE}"), or the lexicographically first .md/.txt file in $(basename "${RALPH_DIR}")
		    -n <num>, --iterations <num> Number of iterations to perform (default: ${DEFAULT_ITERATIONS})
		    -m <model>, --model <model>  Specify the AI model to use (default: ${DEFAULT_MODEL})
		    -b <cmd>, --backend <cmd>    Agent CLI to use (default: ${DEFAULT_BACKEND})
		    --backend-args <args>        Extra args passed to the agent CLI (default: "${DEFAULT_BACKEND_ARGS}")
		    --force                      Force the task to run even if it is marked as completed
		    --import-run <dir>           Import iteration files from a previous run directory as starting memory
		    -s <dir>, --specs <dir>      Path to specs directory (default: .ralph/specs if it exists)
		    --no-sdd                     Disable SDD mode; use raw task file passthrough
		    --sdd-model <model>          Model for spec generation pre-pass (defaults to MODEL)

		Subcommands:
		    init                          Initialize the Ralph environment in the current directory
		    generate-specs                Run only the task-to-specs pre-pass, then exit
	EOF
}

error() {
	echo "Error: $1" >&2
}

fatal() {
	error "$1"
	exit 1
}

fatal-with-usage() {
	error "$1"
	usage
	exit 1
}

verbose() {
	if ${VERBOSE}; then
		echo "$@"
	fi
}

parse-args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-h|--help)
				usage
				exit 0
				;;
			--force)
				FORCE=true
				shift
				;;
			--import-run)
				if [[ $# -gt 1 && "$2" != -* ]]; then
					IMPORT_RUN="$2"
					# Imported runs implicitly force
					FORCE=true
					shift 2
				else
					fatal-with-usage "$1 requires a value"
				fi
				;;
			-f|--file)
				if [[ $# -gt 1 && "$2" != -* ]]; then
					TASK_FILE="$2"
					shift 2
				else
					fatal-with-usage "$1 requires a value"
				fi
				;;
			-v|--verbose)
				VERBOSE=true
				shift
				;;
			-n|--iterations)
				if [[ $# -gt 1 ]]; then
					ITERATIONS="$2"
					if ! [[ "${ITERATIONS}" =~ ^[0-9]+$ ]]; then
						fatal-with-usage "$1 must be a positive integer"
					fi
					shift 2
				else
					fatal-with-usage "$1 requires a value"
				fi
				;;
			-m|--model)
				if [[ $# -gt 1 ]]; then
					MODEL="$2"
					shift 2
				else
					fatal-with-usage "$1 requires a value"
				fi
				;;
			-b|--backend)
				if [[ $# -gt 1 ]]; then
					BACKEND="$2"
					shift 2
				else
					fatal-with-usage "$1 requires a value"
				fi
				;;
			--backend-args)
				if [[ $# -gt 1 ]]; then
					BACKEND_ARGS="$2"
					shift 2
				else
					fatal-with-usage "$1 requires a value"
				fi
				;;
			-s|--specs)
				if [[ $# -gt 1 && "$2" != -* ]]; then
					SPECS_DIR="$2"
					shift 2
				else
					fatal-with-usage "$1 requires a value"
				fi
				;;
			--no-sdd)
				NO_SDD=true
				shift
				;;
			--sdd-model)
				if [[ $# -gt 1 ]]; then
					SDD_MODEL="$2"
					shift 2
				else
					fatal-with-usage "$1 requires a value"
				fi
				;;
			*)
				break
				;;
		esac
	done

	if [[ $# -gt 0 ]]; then
		if [[ "$1" == "init" ]]; then
			INIT=true
		elif [[ "$1" == "generate-specs" ]]; then
			GENERATE_SPECS_ONLY=true
		else
			fatal-with-usage "Unknown subcommand: $1"
		fi
	fi
}

init() {
	echo "Initializing Ralph..."
	mkdir -p "$(pwd)/.ralph"
	mkdir -p "$(pwd)/.ralph/specs"
	# Check if .gitignore exists and add .ralph to it
	if [[ -f "$(pwd)/.gitignore" ]]; then
		if ! grep -q "^.ralph$" "$(pwd)/.gitignore"; then
			echo ".ralph" >> "$(pwd)/.gitignore"
			echo "Added .ralph to .gitignore"
		fi
	else
		echo "No .gitignore found. Skipping..."
	fi
}

generate-specs-from-task-file() {
	local task_file="$1"
	local specs_dir="$2"
	local gen_model="${SDD_MODEL:-${MODEL}}"

	echo "Generating specs from task file: ${task_file}"
	mkdir -p "${specs_dir}"

	local GEN_PROMPT
	GEN_PROMPT="You are a spec writer. Read the following task file and convert it into individual spec files.

Create numbered spec files under '${specs_dir}/' with the naming convention:
  001-feature-name.md, 002-feature-name.md, etc.

Each spec file MUST have these sections:
  ## Overview
  ## Acceptance Criteria
  ## Out of Scope
  ## Notes

Create the directory '${specs_dir}' if it does not exist.
Break the task into logical, independently completable units of work.

Here is the task file content:
$(cat "${task_file}")
"

	# shellcheck disable=SC2086
	${BACKEND} ${BACKEND_ARGS} --model "${gen_model}" -p "${GEN_PROMPT}"
	echo "Specs generated in: ${specs_dir}"
}

ralph-loop-spec() {
	local ITERATION="$1"
	local spec="$2"
	local ITERATION_DIR="$3"
	local IMPORT_HISTORY="${4:-}"

	local spec_name
	spec_name="$(basename "${spec%.md}")"
	local spec_done="${spec%.md}.DONE"
	local spec_iter_dir="${ITERATION_DIR}/${spec_name}"
	mkdir -p "${spec_iter_dir}"

	verbose "Processing spec ${spec} iteration ${ITERATION}"

	local HISTORY_CONTEXT="${IMPORT_HISTORY}"

	if [ "${ITERATION}" -gt 1 ]; then
		echo "   (Reading memory from previous iterations for spec: ${spec_name}...)"
		for (( i=1; i < ITERATION; i++ )); do
			local PREV_FILE="${spec_iter_dir}/iteration_$i.txt"
			if [ -f "$PREV_FILE" ]; then
				local STEP_CONTENT
				STEP_CONTENT=$(cat "$PREV_FILE")
				HISTORY_CONTEXT+=$'\n'"--- HISTORY (Iteration #${i}) ---"$'\n'"${STEP_CONTENT}"$'\n'
			fi
		done
	fi

	local FULL_PROMPT
	FULL_PROMPT="
$(cat "$spec")

====== SHORT-TERM MEMORY (What you already tried) ======
${HISTORY_CONTEXT}
========================================================

LOOP INSTRUCTIONS:
1. You are running in an autonomous loop.
2. Analyze the history above. If you tried something and it failed, try a different approach.
3. YOU are responsible for ensuring the code works. Run your own internal checks/tests if possible.
4. Complete ALL acceptance criteria in this spec.
5. When the spec is 100% COMPLETE and TESTED, create a '${spec_done}' file.
6. If not finished, briefly describe your progress and what you expect should be done in the next iteration.
7. DO NOT use git automatically and commit changes. Let the user handle this. Also NEVER commit stuff found in .gitignore
"

	local OUTPUT
	# shellcheck disable=SC2086
	if ${VERBOSE}; then
		OUTPUT=$(${BACKEND} ${BACKEND_ARGS} --model "${MODEL}" -p "$FULL_PROMPT" | tee /dev/stderr)
	else
		OUTPUT=$(${BACKEND} ${BACKEND_ARGS} --model "${MODEL}" -p "$FULL_PROMPT")
	fi

	local CURRENT_LOG_FILE="${spec_iter_dir}/iteration_${ITERATION}.txt"
	echo "${OUTPUT}" > "${CURRENT_LOG_FILE}"
	echo "Thought process saved: ${CURRENT_LOG_FILE}"
}

ralph-sdd-loop() {
	local ITERATION_DIR="$1"
	local IMPORT_HISTORY="$2"

	local specs
	specs=$(find "${SPECS_DIR}" -maxdepth 1 -name "*.md" | sort)

	if [[ -z "${specs}" ]]; then
		fatal "No spec files found in ${SPECS_DIR}"
	fi

	local all_done=true
	while IFS= read -r spec; do
		local spec_done="${spec%.md}.DONE"
		if [[ -f "${spec_done}" && "${FORCE}" != true ]]; then
			verbose "Skipping completed spec: $(basename "${spec}")"
			continue
		fi
		all_done=false
		echo "Processing spec: $(basename "${spec}")"
		for i in $(seq 1 "${ITERATIONS}"); do
			ralph-loop-spec "${i}" "${spec}" "${ITERATION_DIR}" "${IMPORT_HISTORY}"
			# Check if this spec is done
			if [[ -f "${spec_done}" ]]; then
				break
			fi
		done
		if [[ ! -f "${spec_done}" ]]; then
			echo "Warning: spec $(basename "${spec}") did not complete within ${ITERATIONS} iterations"
		fi
	done <<< "${specs}"

	if ${all_done}; then
		echo "All specs complete."
	fi
}

main() {
	parse-args "$@"

	if ${INIT}; then
		init
		return
	fi

	if ${GENERATE_SPECS_ONLY}; then
		mkdir -p "${RALPH_DIR}"
		if [[ -z "${TASK_FILE}" ]]; then
			if [[ -f "${DEFAULT_TASK_FILE}" ]]; then
				TASK_FILE="${DEFAULT_TASK_FILE}"
			else
				fatal-with-usage "No task file provided for spec generation."
			fi
		fi
		if [[ ! -f "${TASK_FILE}" ]]; then
			fatal "Task file not found: ${TASK_FILE}"
		fi
		local specs_target="${SPECS_DIR:-${DEFAULT_SPECS_DIR}}"
		generate-specs-from-task-file "${TASK_FILE}" "${specs_target}"
		return
	fi

	mkdir -p "${RALPH_DIR}"

	# If forcing a run, remove any existing DONE_FILE and ensure it's cleaned up on exit
	if ${FORCE}; then
		if [[ -f "${DONE_FILE}" ]]; then
			verbose "Force flag is set. Removing ${DONE_FILE} file to allow re-execution."
			rm -f "${DONE_FILE}" || true
		fi
		# Ensure cleanup of any DONE_FILE the agent might create during the run
		trap 'rm -f "${DONE_FILE}" >/dev/null 2>&1 || true' EXIT
	fi
	if [[ -z "${TASK_FILE}" ]]; then
		# Check if stdin has input
		if [ ! -t 0 ]; then
			TASK_FILE="${STDIN}"
			# If reading from stdin, capture it to a file so it can be reused per-iteration
			mkdir -p "${RALPH_DIR}"
			TASK_FILE_CAPTURE="${RALPH_DIR}/task_from_stdin.txt"
			cat "${STDIN}" > "${TASK_FILE_CAPTURE}"
			TASK_FILE="${TASK_FILE_CAPTURE}"
		else
			# Select first file by name of DEFAULT_TASK_FILE, or any text extension
			if [[ -f "${DEFAULT_TASK_FILE}" ]]; then
				TASK_FILE="${DEFAULT_TASK_FILE}"
			else
				TASK_FILE=$(find "${RALPH_DIR}" -maxdepth 1 -type f \( -name "*.md" -o -name "*.txt" \) | sort | head -n 1)
				if [[ -z "${TASK_FILE}" ]]; then
					fatal-with-usage "No task file provided and no suitable files found in $(basename "${RALPH_DIR}"). Exiting."
				fi
			fi
		fi
	fi

	if [[ "${TASK_FILE}" != "${STDIN}" && ! -f "${TASK_FILE}" && ! -e "${TASK_FILE}" ]]; then
		fatal "Task file not found: ${TASK_FILE}"
	fi
	
	verbose "Task file: ${TASK_FILE}"
	verbose "Iterations: ${ITERATIONS}"
	verbose "Backend: ${BACKEND}"
	verbose "Backend args: ${BACKEND_ARGS}"
	verbose "Force? ${FORCE}"

	if [[ -f "${DONE_FILE}" ]]; then
		if ${FORCE}; then
			verbose "Force flag is set. Removing ${DONE_FILE} file to allow re-execution."
			rm -f "${DONE_FILE}"
		else
			echo "Task already completed. Use --force to re-run."
			exit 0
		fi
	fi

	local ITERATION_DIR
	ITERATION_DIR="${RALPH_DIR}/$(date +%Y%m%d_%H%M%S)"
	mkdir -p "${ITERATION_DIR}"

	# Copy original task file into iteration dir for record
	if [[ -f "${TASK_FILE}" ]]; then
		cp "${TASK_FILE}" "${ITERATION_DIR}/task_file.txt"
	fi

	# Build imported history once
	local IMPORT_HISTORY=""
	if [[ -n "${IMPORT_RUN}" ]]; then
		if [[ -d "${IMPORT_RUN}" ]]; then
			echo "   (Importing history from $(realpath "${IMPORT_RUN}")...)"
			for f in "${IMPORT_RUN}"/iteration_*.txt; do
				if [ ! -e "$f" ]; then
					continue
				fi
				local PREV_BASENAME
				PREV_BASENAME=$(basename "$f")
				local PREV_IDX
				PREV_IDX=$(echo "${PREV_BASENAME}" | sed -E 's/.*iteration_([0-9]+)\.txt/\1/')
				local STEP_CONTENT
				STEP_CONTENT=$(cat "$f")
				IMPORT_HISTORY+=$'\n'"--- IMPORTED HISTORY (${IMPORT_RUN}) (Iteration #${PREV_IDX}) ---"$'\n'"${STEP_CONTENT}"$'\n'
			done
		else
			echo "Warning: import run dir '${IMPORT_RUN}' not found" >&2
		fi
	fi

	# SDD mode detection
	if [[ -n "${SPECS_DIR}" ]]; then
		SDD_MODE=true
	elif [[ -d "${DEFAULT_SPECS_DIR}" && "${NO_SDD}" != true ]]; then
		SPECS_DIR="${DEFAULT_SPECS_DIR}"
		SDD_MODE=true
	elif [[ "${NO_SDD}" != true && -n "${TASK_FILE}" && -f "${TASK_FILE}" ]]; then
		# Auto-generate specs from task file
		SPECS_DIR="${DEFAULT_SPECS_DIR}"
		generate-specs-from-task-file "${TASK_FILE}" "${SPECS_DIR}"
		SDD_MODE=true
	fi

	if ${SDD_MODE}; then
		ralph-sdd-loop "${ITERATION_DIR}" "${IMPORT_HISTORY}"
	else
		# Existing flat task loop
		for i in $(seq 1 "${ITERATIONS}"); do
			verbose "Iteration ${i}/${ITERATIONS}"
			ralph-loop "${i}" "${TASK_FILE}" "${ITERATION_DIR}" "${IMPORT_HISTORY}"
		done
		fatal "Reached maximum iterations ($ITERATIONS) without completion."
	fi
}

ralph-loop() {
	local ITERATION
	ITERATION="$1"
	# Support optional parameters safely: TASK_FILE, ITERATION_DIR, IMPORT_HISTORY
	local TASK_FILE
	TASK_FILE="${2:-}"
	local ITERATION_DIR
	ITERATION_DIR="${3:-}"
	local IMPORT_HISTORY
	IMPORT_HISTORY="${4:-}"

	verbose "Processing task file ${TASK_FILE} in ${ITERATION_DIR}"

	# Adapted from https://gist.github.com/Tavernari/01d21584f8d4d8ccea8ceca305656ab3
	local HISTORY_CONTEXT="${IMPORT_HISTORY}"

	if [ "${ITERATION}" -gt 1 ]; then
		echo "   (Reading memory from previous iterations...)"
		for (( i=1; i < ITERATION; i++ )); do
			local PREV_FILE
			PREV_FILE="${ITERATION_DIR}/iteration_$i.txt"
			if [ -f "$PREV_FILE" ]; then
				STEP_CONTENT=$(cat "$PREV_FILE")
				HISTORY_CONTEXT+=$'\n'"--- HISTORY (Iteration #${i}) ---"$'\n'"${STEP_CONTENT}"$'\n'
			fi
		done
	fi

	FULL_PROMPT="
$(cat "$TASK_FILE")

====== SHORT-TERM MEMORY (What you already tried) ======
${HISTORY_CONTEXT}
========================================================

LOOP INSTRUCTIONS:
1. You are running in an autonomous loop.
2. Analyze the history above. If you tried something and it failed, try a different approach.
3. YOU are responsible for ensuring the code works. Run your own internal checks/tests if possible.
4. If the task is 100% COMPLETE and TESTED, create a '${DONE_FILE}' file.
5. If not finished, briefly describe your progress and what you expect should be done in the next iteration.
6. DO NOT use git automatically and commit changes. Let the user handle this. Also NEVER commit stuff found in .gitignore
"

	# shellcheck disable=SC2086 # Intentional word splitting on BACKEND_ARGS
	if ${VERBOSE}; then
		OUTPUT=$(${BACKEND} ${BACKEND_ARGS} --model "${MODEL}" -p "$FULL_PROMPT" | tee /dev/stderr)
	else
		OUTPUT=$(${BACKEND} ${BACKEND_ARGS} --model "${MODEL}" -p "$FULL_PROMPT")
	fi

	local CURRENT_LOG_FILE
	CURRENT_LOG_FILE="${ITERATION_DIR}/iteration_${ITERATION}.txt"
	echo "${OUTPUT}" > "${CURRENT_LOG_FILE}"
	echo "Thought process saved: ${CURRENT_LOG_FILE}"

	if [[ -f "${DONE_FILE}" ]]; then
		echo "-----------------------------------"
		echo "Agent reported completion."
		echo "Full history available at: ${ITERATION_DIR}"
		exit 0
	fi
	# Delay to avoid rate limits
	if [[ "${ITERATION}" -lt "${ITERATIONS}" ]]; then sleep 2; fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
