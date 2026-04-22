#!/usr/bin/env bats

setup() {
  # Source property helpers
  source "$(pwd)/tests/property_helpers.sh"
}

@test "parse-args is idempotent (property-based)" {
  if [[ -n "${PROPERTY_TEST_FAST:-}" || -n "${CI:-}" ]]; then CASES=20; else CASES=100; fi

  for ((i=1;i<=CASES;i++)); do
    tokens=()
    while IFS= read -r l; do tokens+=("$l"); done < <(make_random_args)
    if (( ${#tokens[@]} == 0 )); then continue; fi

    s1=$(snapshot "${tokens[@]}") || s1=$?
    s2=$(snapshot "${tokens[@]}") || s2=$?

    if [ "${s1}" != "${s2}" ]; then
      minimal=$(shrink_input "${tokens[@]}")
      echo "Idempotence failure on case #${i}" >&2
      echo "Original tokens: ${tokens[*]}" >&2
      echo "Minimal failing input: ${minimal}" >&2
      echo "parse-args not idempotent" >&2
      return 1
    fi
  done
}

@test "snapshot round-trip through parse-args (permutation invariant)" {
  if [[ -n "${PROPERTY_TEST_FAST:-}" || -n "${CI:-}" ]]; then CASES=20; else CASES=100; fi

  for ((i=1;i<=CASES;i++)); do
    items=()
    while IFS= read -r _line; do items+=("$_line"); done < <(make_random_items)
    if (( ${#items[@]} == 0 )); then continue; fi

    perm1=(); perm2=(); sep=$'\x1F'
    for it in "${items[@]}"; do
      if [[ "${it}" == *"${sep}"* ]]; then a=${it%%"${sep}"*}; b=${it#*"${sep}"}; perm1+=("$a" "$b"); else perm1+=("$it"); fi
    done

    # create perm2 by shuffling item-level ordering (preserve flag+value attachment)
    items_shuf=("${items[@]}")
    for ((j=${#items_shuf[@]}-1;j>0;j--)); do k=$((RANDOM%(j+1))); tmp=${items_shuf[j]}; items_shuf[j]=${items_shuf[k]}; items_shuf[k]=$tmp; done
    perm2=()
    for it in "${items_shuf[@]}"; do
      if [[ "$it" == *"$sep"* ]]; then a=${it%%"$sep"*}; b=${it#*"$sep"}; perm2+=("$a" "$b"); else perm2+=("$it"); fi
    done

    s1=$(snapshot "${perm1[@]}") || s1=$?
    s2=$(snapshot "${perm2[@]}") || s2=$?

    if [ "${s1}" != "${s2}" ]; then
      minimal=$(shrink_input "${perm1[@]}")
      echo "Round-trip failure case #${i}" >&2
      echo "Original items: ${items[*]}" >&2
      echo "Minimal failing input: ${minimal}" >&2
      echo "snapshot not equal after different permutations" >&2
      return 1
    fi
  done
}
