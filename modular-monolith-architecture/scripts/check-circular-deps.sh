#!/usr/bin/env bash
# check-circular-deps.sh
#
# Detects circular dependencies between modules in a modular monolith.
# Builds a dependency graph from import statements and checks for cycles.
#
# Usage:
#   ./scripts/check-circular-deps.sh <modules-dir>
#
# Examples:
#   ./scripts/check-circular-deps.sh src/modules
#   ./scripts/check-circular-deps.sh src/Modules

set -euo pipefail

MODULES_DIR="${1:?Usage: check-circular-deps.sh <modules-dir>}"

if [ ! -d "$MODULES_DIR" ]; then
  echo "Error: Directory '$MODULES_DIR' does not exist."
  exit 1
fi

# Get list of module names
MODULES=()
for dir in "$MODULES_DIR"/*/; do
  [ -d "$dir" ] && MODULES+=("$(basename "$dir")")
done

if [ ${#MODULES[@]} -eq 0 ]; then
  echo "No modules found in $MODULES_DIR"
  exit 0
fi

echo "Checking for circular dependencies in: $MODULES_DIR"
echo "Modules: ${MODULES[*]}"
echo "---"

# Build adjacency list: module -> modules it depends on
declare -A DEPS

for SOURCE in "${MODULES[@]}"; do
  DEPS[$SOURCE]=""
  for TARGET in "${MODULES[@]}"; do
    [ "$SOURCE" = "$TARGET" ] && continue

    # Check if source module has any import from target module
    if find "$MODULES_DIR/$SOURCE" -type f \( -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.java" -o -name "*.cs" -o -name "*.go" \) ! -name "*.spec.*" ! -name "*.test.*" -print0 2>/dev/null \
       | xargs -0 grep -lE "(from|import).*${TARGET}" 2>/dev/null | head -1 | grep -q .; then
      if [ -z "${DEPS[$SOURCE]}" ]; then
        DEPS[$SOURCE]="$TARGET"
      else
        DEPS[$SOURCE]="${DEPS[$SOURCE]} $TARGET"
      fi
    fi
  done
done

echo "Dependency graph:"
for MODULE in "${MODULES[@]}"; do
  if [ -n "${DEPS[$MODULE]}" ]; then
    echo "  $MODULE -> ${DEPS[$MODULE]}"
  else
    echo "  $MODULE -> (none)"
  fi
done
echo "---"

# Detect cycles using DFS
CYCLES_FOUND=0

detect_cycle() {
  local node="$1"
  local path="$2"

  # Check if node is already in the current path (cycle detected)
  if echo " $path " | grep -q " $node "; then
    echo "CIRCULAR DEPENDENCY: $path -> $node"
    CYCLES_FOUND=$((CYCLES_FOUND + 1))
    return
  fi

  local new_path="$path $node"

  for dep in ${DEPS[$node]}; do
    detect_cycle "$dep" "$new_path"
  done
}

for MODULE in "${MODULES[@]}"; do
  detect_cycle "$MODULE" ""
done

if [ "$CYCLES_FOUND" -gt 0 ]; then
  echo "FAILED: $CYCLES_FOUND circular dependency chain(s) detected."
  echo ""
  echo "To fix circular dependencies:"
  echo "  1. Extract the shared concern into a new module or the shared kernel"
  echo "  2. Replace one direction with async events instead of direct calls"
  echo "  3. Introduce a mediator/orchestrator module that both modules depend on"
  exit 1
else
  echo "PASSED: No circular dependencies detected."
  exit 0
fi
