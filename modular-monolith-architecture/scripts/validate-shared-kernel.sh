#!/usr/bin/env bash
# validate-shared-kernel.sh
#
# Verifies that the shared kernel does not import from any module.
# The shared kernel should contain only cross-cutting concerns and must
# never depend on module-specific code.
#
# Usage:
#   ./scripts/validate-shared-kernel.sh <shared-dir> <modules-dir>
#
# Examples:
#   ./scripts/validate-shared-kernel.sh src/shared src/modules
#   ./scripts/validate-shared-kernel.sh src/MyApp.Shared src/Modules

set -euo pipefail

SHARED_DIR="${1:?Usage: validate-shared-kernel.sh <shared-dir> <modules-dir>}"
MODULES_DIR="${2:?Usage: validate-shared-kernel.sh <shared-dir> <modules-dir>}"

if [ ! -d "$SHARED_DIR" ]; then
  echo "Error: Shared directory '$SHARED_DIR' does not exist."
  exit 1
fi

if [ ! -d "$MODULES_DIR" ]; then
  echo "Error: Modules directory '$MODULES_DIR' does not exist."
  exit 1
fi

VIOLATIONS=0
CHECKED=0

# Get module names for pattern matching
MODULES=()
for dir in "$MODULES_DIR"/*/; do
  [ -d "$dir" ] && MODULES+=("$(basename "$dir")")
done

MODULES_PARENT=$(basename "$MODULES_DIR")

echo "Checking shared kernel isolation: $SHARED_DIR"
echo "Modules directory: $MODULES_DIR"
echo "---"

while IFS= read -r -d '' file; do
  CHECKED=$((CHECKED + 1))

  # Check for any import/reference to the modules directory
  if grep -qE "(from|import).*${MODULES_PARENT}" "$file" 2>/dev/null; then
    echo "VIOLATION: $file"
    echo "  -> shared kernel must not reference any module"
    grep -nE "(from|import).*${MODULES_PARENT}" "$file" | while IFS= read -r line; do
      echo "  $line"
    done
    VIOLATIONS=$((VIOLATIONS + 1))
  fi

  # Also check for individual module name references in imports
  for MODULE in "${MODULES[@]}"; do
    if grep -qE "(from|import).*${MODULE}" "$file" 2>/dev/null; then
      # Don't double-count if already caught by the modules directory check
      if ! grep -qE "(from|import).*${MODULES_PARENT}" "$file" 2>/dev/null; then
        echo "VIOLATION: $file"
        echo "  -> references module '$MODULE'"
        grep -nE "(from|import).*${MODULE}" "$file" | while IFS= read -r line; do
          echo "  $line"
        done
        VIOLATIONS=$((VIOLATIONS + 1))
      fi
    fi
  done
done < <(find "$SHARED_DIR" -type f \( -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.java" -o -name "*.cs" -o -name "*.go" \) -print0)

echo "---"
echo "Files checked: $CHECKED"

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "FAILED: $VIOLATIONS violation(s) — shared kernel depends on module code."
  exit 1
else
  echo "PASSED: Shared kernel has no module dependencies."
  exit 0
fi
