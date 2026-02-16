#!/bin/bash
# check-circular-deps.sh — Detect circular dependencies between FastAPI modules
#
# Usage: ./check-circular-deps.sh <app-dir>
#   <app-dir>  Root app directory containing modules (e.g., ./app)
#
# Exit codes:
#   0 — No circular dependencies found
#   1 — Circular dependencies detected

set -euo pipefail

APP_DIR="${1:?Usage: $0 <app-dir>}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

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

echo "Detected modules: ${MODULES[*]}"
echo "---"

# Build dependency graph
declare -A DEPS

for source_module in "${MODULES[@]}"; do
    SOURCE_DIR="$APP_DIR/$source_module"
    MODULE_DEPS=""

    while IFS= read -r filepath; do
        while IFS= read -r import_line; do
            for target_module in "${MODULES[@]}"; do
                if [[ "$target_module" == "$source_module" ]]; then
                    continue
                fi
                if echo "$import_line" | grep -qE "app\.$target_module"; then
                    if [[ ! "$MODULE_DEPS" =~ "$target_module" ]]; then
                        MODULE_DEPS="$MODULE_DEPS $target_module"
                    fi
                fi
            done
        done < <(grep -E "^(from|import)\s+app\." "$filepath" 2>/dev/null || true)
    done < <(find "$SOURCE_DIR" -name "*.py" -type f)

    DEPS[$source_module]="$MODULE_DEPS"
    if [[ -n "$MODULE_DEPS" ]]; then
        echo "$source_module depends on:$MODULE_DEPS"
    else
        echo "$source_module has no module dependencies"
    fi
done

echo "---"

# Detect cycles using DFS
CYCLES_FOUND=0

detect_cycle() {
    local start=$1
    local current=$2
    local path=$3
    local visited=$4

    for dep in ${DEPS[$current]:-}; do
        if [[ "$dep" == "$start" && "$path" != "$start" ]]; then
            echo -e "${RED}CIRCULAR DEPENDENCY:${NC} $path → $dep"
            CYCLES_FOUND=1
            return
        fi

        if [[ ! " $visited " =~ " $dep " ]]; then
            detect_cycle "$start" "$dep" "$path → $dep" "$visited $dep"
        fi
    done
}

for module in "${MODULES[@]}"; do
    detect_cycle "$module" "$module" "$module" "$module"
done

echo "---"
if [[ $CYCLES_FOUND -eq 1 ]]; then
    echo -e "${RED}Circular dependencies detected!${NC}"
    echo "Modules must not form dependency cycles."
    echo "Consider using events for decoupling or restructuring module boundaries."
    exit 1
else
    echo -e "${GREEN}No circular dependencies found${NC}"
    exit 0
fi
