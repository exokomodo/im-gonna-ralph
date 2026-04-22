#!/usr/bin/env bats

setup() {
  # Source property helpers
  source "$(pwd)/tests/property_helpers.sh"
}

@test "parse-args is order-independent (property-based)" {
  # Tweak case count for CI/fast mode
  if [[ -n "${PROPERTY_TEST_FAST:-}" || -n "${CI:-}" ]]; then
    CASES=20
  else
    CASES=100
  fi

  for ((i=1;i<=CASES;i++)); do
    # Generate a random items list (each item is a flag or flag+value packed)
    items=()
    while IFS= read -r _line; do
      items+=("$_line")
    done < <(make_random_items)
    if (( ${#items[@]} == 0 )); then
      continue
    fi

    # Two permutations at item granularity: original and reversed
    items1=("${items[@]}")
    items2=()
    for (( idx=${#items[@]}-1; idx>=0; idx-- )); do
      items2+=("${items[idx]}")
    done

    # Expand items to tokens for snapshots
    perm1=(); perm2=(); sep=$'\x1F'
    for it in "${items1[@]}"; do
      if [[ "$it" == *"$sep"* ]]; then
        a=${it%%"$sep"*}
        b=${it#*"$sep"}
        perm1+=("$a" "$b")
      else
        perm1+=("$it")
      fi
    done
    for it in "${items2[@]}"; do
      if [[ "$it" == *"$sep"* ]]; then
        a=${it%%"$sep"*}
        b=${it#*"$sep"}
        perm2+=("$a" "$b")
      else
        perm2+=("$it")
      fi
    done

    s1=$(snapshot "${perm1[@]}") || s1=$?
    s2=$(snapshot "${perm2[@]}") || s2=$?

    if [ "$s1" != "$s2" ]; then
      failing_input="${items[*]}"
      # For shrink, operate at item granularity: use shrink_input? (it currently works on tokens)
      # Call shrink_input on the flattened token list for simplicity
      minimal=$(shrink_input "${perm1[@]}")
      echo "Property-based failure on case #${i}" >&2
      echo "Original items: ${items[*]}" >&2
      echo "Minimal failing input (tokens): ${minimal}" >&2
      echo "--- Snapshot (items1) ---" >&2
      snapshot "${perm1[@]}" >&2 || true
      echo "--- Snapshot (items2) ---" >&2
      snapshot "${perm2[@]}" >&2 || true
      fail "parse-args produced different snapshots for different argument orderings"
    fi
  done
}
