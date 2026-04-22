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
DONE_FILE="${RALPH_DIR}/.done"
DEFAULT_TASK_FILE="${RALPH_DIR}/tasks"
IMPORT_RUN=""
DEFAULT_BACKEND=copilot
BACKEND="${BACKEND:-$DEFAULT_BACKEND}"
DEFAULT_BACKEND_ARGS="--allow-all-tools --allow-all-urls"
BACKEND_ARGS="${BACKEND_ARGS:-$DEFAULT_BACKEND_ARGS}"

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

		Subcommands:
		    init                          Initialize the Ralph environment in the current directory
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
			*)
				break
				;;
		esac
	done

	if [[ $# -gt 0 ]]; then
		if [[ "$1" == "init" ]]; then
			INIT=true
		else
			fatal-with-usage "Unknown subcommand: $1"
		fi
	fi
}

init() {
	echo "Initializing Ralph..."
	mkdir -p "$(pwd)/.ralph"
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

main() {
	parse-args "$@"

	if ${INIT}; then
		init
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

	# Do iterations
	for i in $(seq 1 "${ITERATIONS}"); do
		verbose "Iteration ${i}/${ITERATIONS}"
		ralph-loop "${i}" "${TASK_FILE}" "${ITERATION_DIR}" "${IMPORT_HISTORY}"
	done

	fatal "Reached maximum iterations ($ITERATIONS) without completion."
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

main "$@"
