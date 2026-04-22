#!/usr/bin/env bash
set -euo pipefail

# Helper utilities for property-based testing of src/ralph.bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/src/ralph.bash"

snapshot() {
  # Run parse-args in a subshell to avoid leaking state between calls
  ( 
    set -euo pipefail
    source "${ROOT_DIR}/src/ralph.bash"
    parse-args "$@"
    # Print a stable snapshot of key variables
    printf "%s\n" \
      "MODEL=${MODEL:-}" \
      "ITERATIONS=${ITERATIONS:-}" \
      "FORCE=${FORCE:-}" \
      "VERBOSE=${VERBOSE:-}" \
      "TASK_FILE=${TASK_FILE:-}" \
      "SPECS_DIR=${SPECS_DIR:-}" \
      "NO_SDD=${NO_SDD:-}" \
      "SDD_MODEL=${SDD_MODEL:-}" \
      "BACKEND=${BACKEND:-}" \
      "BACKEND_ARGS=${BACKEND_ARGS:-}"
  )
}

# Generate a random integer in [min,max]
rand_int() {
  local min=$1; local max=$2
  echo $(( RANDOM % (max - min + 1) + min ))
}

# Generate a short random string
rand_str() {
  # Use base64 to produce ASCII-safe output, then filter
  head -c 12 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c ${1:-6} || echo "x"
}

# Build a token array representing CLI arguments from a random subset of options
# Allowed options chosen to be safe for tests (no filesystem side-effects)
make_random_args() {
  local tokens=()
  # Option: verbose flag
  if (( RANDOM % 2 == 0 )); then tokens+=("-v"); fi
  # Option: force
  if (( RANDOM % 3 == 0 )); then tokens+=("--force"); fi
  # Option: iterations (-n)
  if (( RANDOM % 2 == 0 )); then
    local n=$(rand_int 0 999)
    tokens+=("-n" "$n")
  fi
  # Option: model (-m)
  if (( RANDOM % 2 == 0 )); then
    tokens+=("-m" "$(rand_str 8)")
  fi
  # Option: no-sdd
  if (( RANDOM % 4 == 0 )); then tokens+=("--no-sdd"); fi
  # Option: sdd-model
  if (( RANDOM % 5 == 0 )); then tokens+=("--sdd-model" "$(rand_str 6)"); fi
  # Option: backend (-b)
  if (( RANDOM % 6 == 0 )); then tokens+=("-b" "$(rand_str 6)"); fi

  # Shuffle tokens but preserving value attachment (flags followed by values)
  # We'll construct a list of "items" where item may be one or two tokens
  local items=()
  local sep=$'\x1F'  # unit separator - safe non-printable delimiter
  local i=0
  while [ $i -lt ${#tokens[@]} ]; do
    if [[ "${tokens[$i]}" =~ ^-[-a-zA-Z]+$ ]] && [ $((i+1)) -lt ${#tokens[@]} ] && [[ ! "${tokens[$i+1]}" =~ ^-[-a-zA-Z]+$ ]]; then
      items+=("${tokens[$i]}${sep}${tokens[$i+1]}")
      i=$((i+2))
    else
      items+=("${tokens[$i]}")
      i=$((i+1))
    fi
  done

  # Fisher-Yates shuffle
  for ((i=${#items[@]}-1; i>0; i--)); do
    j=$(( RANDOM % (i+1) ))
    tmp=${items[i]}; items[i]=${items[j]}; items[j]=$tmp
  done

  # Expand items back to tokens
  local out=()
  for it in "${items[@]}"; do
    if [[ "$it" == *"$sep"* ]]; then
      a=${it%%"$sep"*}
      b=${it#*"$sep"}
      out+=("$a" "$b")
    else
      out+=("$it")
    fi
  done
  printf '%s\n' "${out[@]}"
}

# Return the shuffled "items" (flags or flag+value) one per line using the unit separator
make_random_items() {
  local tokens=()
  if (( RANDOM % 2 == 0 )); then tokens+=("-v"); fi
  if (( RANDOM % 3 == 0 )); then tokens+=("--force"); fi
  if (( RANDOM % 2 == 0 )); then local n=$(rand_int 0 999); tokens+=("-n" "$n"); fi
  if (( RANDOM % 2 == 0 )); then tokens+=("-m" "$(rand_str 8)"); fi
  if (( RANDOM % 4 == 0 )); then tokens+=("--no-sdd"); fi
  if (( RANDOM % 5 == 0 )); then tokens+=("--sdd-model" "$(rand_str 6)"); fi
  if (( RANDOM % 6 == 0 )); then tokens+=("-b" "$(rand_str 6)"); fi

  local items=()
  local sep=$'\x1F'
  local i=0
  while [ $i -lt ${#tokens[@]} ]; do
    if [[ "${tokens[$i]}" =~ ^-[-a-zA-Z]+$ ]] && [ $((i+1)) -lt ${#tokens[@]} ] && [[ ! "${tokens[$i+1]}" =~ ^-[-a-zA-Z]+$ ]]; then
      items+=("${tokens[$i]}${sep}${tokens[$i+1]}")
      i=$((i+2))
    else
      items+=("${tokens[$i]}")
      i=$((i+1))
    fi
  done

  # Shuffle items
  for ((i=${#items[@]}-1; i>0; i--)); do
    j=$(( RANDOM % (i+1) ))
    tmp=${items[i]}; items[i]=${items[j]}; items[j]=$tmp
  done

  # Print one item per line
  for it in "${items[@]}"; do
    printf '%s\n' "$it"
  done
}

# Shrink a failing input by attempting to remove tokens while property still fails
shrink_input() {
  local -a tokens=("$@")
  local changed=true
  while $changed; do
    changed=false
    for (( i=0; i<${#tokens[@]}; i++ )); do
      # remove token at i
      local copy=()
      for (( j=0; j<${#tokens[@]}; j++ )); do
        if [ "$j" -ne "$i" ]; then
          copy+=("${tokens[$j]}")
        fi
      done
      # Check property: compare two permutations of copy tokens
      local perm1=("${copy[@]}")
      local perm2=()
      for (( k=${#copy[@]}-1; k>=0; k-- )); do
        perm2+=("${copy[$k]}")
      done
      local s1
      s1=$(snapshot "${perm1[@]}") || true
      local s2
      s2=$(snapshot "${perm2[@]}") || true
      if [ "$s1" != "$s2" ]; then
        tokens=("${copy[@]}")
        changed=true
        break
      fi
    done
  done
  printf '%s\n' "${tokens[@]}"
}

# Expose functions when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # If executed directly, run a small demo or help
  echo "Property helpers: snapshot, make_random_args, shrink_input" >&2
fi
