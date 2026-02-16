#!/bin/bash
# validate-shared-kernel.sh — Ensure core/shared kernel doesn't reference business modules
#
# Usage: ./validate-shared-kernel.sh <core-dir> <app-dir>
#   <core-dir>  Path to the core/shared kernel directory (e.g., ./app/core)
#   <app-dir>   Path to the app directory containing modules (e.g., ./app)
#
# Exit codes:
#   0 — No violations found
#   1 — Shared kernel references business modules

set -euo pipefail

CORE_DIR="${1:?Usage: $0 <core-dir> <app-dir>}"
APP_DIR="${2:?Usage: $0 <core-dir> <app-dir>}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Files in core that are allowed to reference modules (composition root files)
EXEMPT_FILES="models.py routers.py listeners.py tasks.py"

# Discover modules
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

echo "Core directory: $CORE_DIR"
echo "Detected modules: ${MODULES[*]}"
echo "Exempt files: $EXEMPT_FILES"
echo "---"

VIOLATIONS=0

while IFS= read -r filepath; do
    filename=$(basename "$filepath")

    # Skip exempt files
    IS_EXEMPT=false
    for exempt in $EXEMPT_FILES; do
        if [[ "$filename" == "$exempt" ]]; then
            IS_EXEMPT=true
            break
        fi
    done

    if [[ "$IS_EXEMPT" == "true" ]]; then
        continue
    fi

    # Check for imports from business modules
    while IFS= read -r import_line; do
        for module in "${MODULES[@]}"; do
            if echo "$import_line" | grep -qE "app\.$module"; then
                echo -e "${RED}VIOLATION:${NC} $filepath"
                echo "  Core imports from '$module' module"
                echo "  Line: $import_line"
                echo ""
                VIOLATIONS=$((VIOLATIONS + 1))
            fi
        done
    done < <(grep -nE "^(from|import)\s+app\." "$filepath" 2>/dev/null || true)
done < <(find "$CORE_DIR" -name "*.py" -type f)

echo "---"
if [[ $VIOLATIONS -gt 0 ]]; then
    echo -e "${RED}Found $VIOLATIONS violation(s) — core references business modules${NC}"
    echo "The shared kernel (core/) must not depend on business modules."
    echo "Exempt files: $EXEMPT_FILES"
    exit 1
else
    echo -e "${GREEN}Shared kernel is clean — no module references found${NC}"
    exit 0
fi
