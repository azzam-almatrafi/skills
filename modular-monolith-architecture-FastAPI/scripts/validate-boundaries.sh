#!/bin/bash
# validate-boundaries.sh — Detect cross-module boundary violations in Python imports
#
# Usage: ./validate-boundaries.sh <app-dir> [allowed-imports]
#   <app-dir>          Root app directory containing modules (e.g., ./app)
#   [allowed-imports]  Comma-separated list of allowed cross-module imports
#                      Default: "gateway,events,schemas.dtos,exceptions"
#
# Exit codes:
#   0 — No violations found
#   1 — Boundary violations detected

set -euo pipefail

APP_DIR="${1:?Usage: $0 <app-dir> [allowed-imports]}"
ALLOWED_IMPORTS="${2:-gateway,events,schemas.dtos,exceptions}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Discover modules (directories in app/ that are not core, __pycache__, or hidden)
MODULES=()
for dir in "$APP_DIR"/*/; do
    dirname=$(basename "$dir")
    if [[ "$dirname" != "core" && "$dirname" != "__pycache__" && ! "$dirname" =~ ^\. ]]; then
        if [[ -f "$dir/__init__.py" ]]; then
            MODULES+=("$dirname")
        fi
    fi
done

if [[ ${#MODULES[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No modules found in $APP_DIR${NC}"
    exit 0
fi

echo "Detected modules: ${MODULES[*]}"
echo "Allowed cross-module imports: $ALLOWED_IMPORTS"
echo "---"

VIOLATIONS=0

# Convert allowed imports to array
IFS=',' read -ra ALLOWED_ARRAY <<< "$ALLOWED_IMPORTS"

for source_module in "${MODULES[@]}"; do
    SOURCE_DIR="$APP_DIR/$source_module"

    # Find all Python files in source module
    while IFS= read -r filepath; do
        # Extract imports using grep for from app.X import patterns
        while IFS= read -r import_line; do
            for target_module in "${MODULES[@]}"; do
                if [[ "$target_module" == "$source_module" ]]; then
                    continue
                fi

                # Check if this line imports from the target module
                if echo "$import_line" | grep -qE "app\.$target_module"; then
                    # Check if import is from an allowed path
                    IS_ALLOWED=false
                    for allowed in "${ALLOWED_ARRAY[@]}"; do
                        allowed=$(echo "$allowed" | xargs)  # trim whitespace
                        if echo "$import_line" | grep -qE "app\.$target_module\.$allowed"; then
                            IS_ALLOWED=true
                            break
                        fi
                    done

                    if [[ "$IS_ALLOWED" == "false" ]]; then
                        echo -e "${RED}VIOLATION:${NC} $filepath"
                        echo "  $source_module → $target_module (internal import)"
                        echo "  Line: $import_line"
                        echo ""
                        VIOLATIONS=$((VIOLATIONS + 1))
                    fi
                fi
            done
        done < <(grep -nE "^(from|import)\s+app\." "$filepath" 2>/dev/null || true)
    done < <(find "$SOURCE_DIR" -name "*.py" -type f)
done

echo "---"
if [[ $VIOLATIONS -gt 0 ]]; then
    echo -e "${RED}Found $VIOLATIONS boundary violation(s)${NC}"
    echo "Modules should only import from each other's: $ALLOWED_IMPORTS"
    exit 1
else
    echo -e "${GREEN}No boundary violations found${NC}"
    exit 0
fi
