#!/usr/bin/env bash
# validate-boundaries.sh
#
# Scans a modular monolith project for cross-module boundary violations.
# Checks that modules only import from other modules' public API directories.
#
# Usage:
#   ./scripts/validate-boundaries.sh <modules-dir> [public-api-dir]
#
# Examples:
#   ./scripts/validate-boundaries.sh src/modules api
#   ./scripts/validate-boundaries.sh src/Modules Contracts
#
# Arguments:
#   modules-dir    Path to the directory containing all modules
#   public-api-dir Name of the public API directory within each module (default: "api")

set -euo pipefail

MODULES_DIR="${1:?Usage: validate-boundaries.sh <modules-dir> [public-api-dir]}"
PUBLIC_API_DIR="${2:-api}"

if [ ! -d "$MODULES_DIR" ]; then
  echo "Error: Directory '$MODULES_DIR' does not exist."
  exit 1
fi

VIOLATIONS=0
CHECKED=0

# Get list of module names
MODULES=()
for dir in "$MODULES_DIR"/*/; do
  [ -d "$dir" ] && MODULES+=("$(basename "$dir")")
done

if [ ${#MODULES[@]} -eq 0 ]; then
  echo "No modules found in $MODULES_DIR"
  exit 0
fi

echo "Checking module boundaries in: $MODULES_DIR"
echo "Modules found: ${MODULES[*]}"
echo "Public API directory: $PUBLIC_API_DIR"
echo "---"

# For each module, check that it doesn't import from other modules' internals
for SOURCE_MODULE in "${MODULES[@]}"; do
  for TARGET_MODULE in "${MODULES[@]}"; do
    [ "$SOURCE_MODULE" = "$TARGET_MODULE" ] && continue

    # Find all source files in the source module
    while IFS= read -r -d '' file; do
      CHECKED=$((CHECKED + 1))

      # Check for imports referencing the target module's internal directories
      # This handles common import patterns across languages:
      #   TypeScript: from '../target-module/domain/...'
      #   Python:     from modules.target_module.domain import ...
      #   Java/C#:    import com.app.modules.target.domain.*
      #   Go:         "app/internal/modules/target/domain"

      # Pattern: reference to target module that is NOT the public API directory
      if grep -qE "(from|import).*${TARGET_MODULE}" "$file" 2>/dev/null; then
        # Check if the import is to the public API directory
        if grep -E "(from|import).*${TARGET_MODULE}" "$file" | grep -vqE "${TARGET_MODULE}/${PUBLIC_API_DIR}|${TARGET_MODULE}\.${PUBLIC_API_DIR}|${TARGET_MODULE}\\\\${PUBLIC_API_DIR}" 2>/dev/null; then
          echo "VIOLATION: $file"
          echo "  -> imports from $TARGET_MODULE internals (only $TARGET_MODULE/$PUBLIC_API_DIR is allowed)"
          grep -nE "(from|import).*${TARGET_MODULE}" "$file" | grep -vE "${TARGET_MODULE}/${PUBLIC_API_DIR}|${TARGET_MODULE}\.${PUBLIC_API_DIR}" | while IFS= read -r line; do
            echo "  $line"
          done
          VIOLATIONS=$((VIOLATIONS + 1))
        fi
      fi
    done < <(find "$MODULES_DIR/$SOURCE_MODULE" -type f \( -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.java" -o -name "*.cs" -o -name "*.go" \) ! -name "*.spec.*" ! -name "*.test.*" ! -name "*_test.*" -print0)
  done
done

echo "---"
echo "Files checked: $CHECKED"

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "FAILED: $VIOLATIONS boundary violation(s) found."
  exit 1
else
  echo "PASSED: No boundary violations detected."
  exit 0
fi
