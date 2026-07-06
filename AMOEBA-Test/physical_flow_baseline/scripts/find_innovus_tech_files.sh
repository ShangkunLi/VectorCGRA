#!/usr/bin/env bash
set -euo pipefail

TECH_ROOT="${1:-/usr/eelocal/tsmc_icdc/tsmc022/tsmc022_ULL}"
STD_CELL="${2:-tcbn22ullbwp30p140lvt}"
ROUTING_STACK="${3:-5x2z}"

if [[ ! -d "$TECH_ROOT" ]]; then
  echo "TECH_ROOT does not exist: $TECH_ROOT" >&2
  exit 1
fi

echo "TECH_ROOT: $TECH_ROOT"
echo "STD_CELL:  $STD_CELL"
echo "ROUTING:   $ROUTING_STACK"
echo

is_tech_lef() {
  local file="$1"
  grep -Eiq '^[[:space:]]*(MANUFACTURINGGRID|LAYER[[:space:]]+M1([[:space:]]|$))' "$file" &&
    ! grep -Eiq '^[[:space:]]*MACRO[[:space:]]+' "$file"
}

score_tech_lef() {
  local file="${1,,}"
  local stack="${ROUTING_STACK,,}"
  local score=0
  [[ "$file" == *"$stack"* ]] && score=$((score + 100))
  [[ "$file" == *"9m"* ]] && score=$((score + 20))
  [[ "$file" == *"innovus"* ]] && score=$((score + 10))
  [[ "$file" == *"cadence"* ]] && score=$((score + 5))
  [[ "$file" == *"lefheader"* ]] && score=$((score + 3))
  echo "$score"
}

echo "Technology LEF candidates:"
tech_candidates=()
while IFS= read -r file; do
  if is_tech_lef "$file"; then
    tech_candidates+=("$file")
    echo "  $file"
  fi
done < <(find "$TECH_ROOT" -type f \( \
  -iname '*.lef' -o \
  -iname '*.tlef' -o \
  -iname '*techlef*' -o \
  -iname '*tech.lef' -o \
  -iname '*technology*.lef' \
\) | sort)

best_tech=""
best_score=-1
for file in "${tech_candidates[@]}"; do
  score="$(score_tech_lef "$file")"
  if (( score > best_score )); then
    best_score="$score"
    best_tech="$file"
  fi
done

echo
echo "LVT standard-cell LEF candidates:"
cell_candidates=()
while IFS= read -r file; do
  cell_candidates+=("$file")
  echo "  $file"
done < <(find "$TECH_ROOT/SC/$STD_CELL" -type f -iname '*.lef' 2>/dev/null | sort)

echo
echo "QRC candidates:"
qrc_candidates=()
while IFS= read -r file; do
  qrc_candidates+=("$file")
  echo "  $file"
done < <(find "$TECH_ROOT" -type f \( \
  -iname 'qrcTechFile' -o \
  -iname '*.tch' -o \
  -iname '*.ict' \
\) | grep -i "$ROUTING_STACK" | sort || true)

echo
echo "Suggested flow_config.tcl snippet:"
if [[ -n "$best_tech" ]]; then
  echo "set INNOVUS_TECH_LEF_FILES [list \\"
  echo "    \"$best_tech\" \\"
  echo "]"
else
  echo "# No technology LEF candidate found automatically."
  echo "# Ask the PDK owner which LEF defines routing layers such as M1."
fi

if [[ ${#cell_candidates[@]} -gt 0 ]]; then
  echo "set INNOVUS_CELL_LEF_FILES [list \\"
  echo "    \"${cell_candidates[0]}\" \\"
  echo "]"
else
  echo "# No standard-cell LEF candidate found for $STD_CELL."
fi

if [[ ${#qrc_candidates[@]} -gt 0 ]]; then
  echo "set INNOVUS_QRC_FILE \"${qrc_candidates[0]}\""
else
  echo "# No QRC candidate found for routing stack $ROUTING_STACK."
fi
