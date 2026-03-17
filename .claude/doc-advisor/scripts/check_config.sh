#!/bin/bash
# Doc Advisor config check: verify document directories are configured.
# Called from skill Pre-check steps. If not configured, outputs a warning
# that tells Claude to run /setup-doc-structure first.
# Exit 0 with no output = directories are configured (OK).
#
# Usage: bash check_config.sh [rules|specs]
#   With argument: check specific category's root_dirs
#   Without argument: check if ANY root_dirs is set (backward compatibility)
#
# Created by k_terada

# Hook cwd is not guaranteed to be project root; use $CLAUDE_PROJECT_DIR
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

CONFIG=".doc_structure.yaml"
CATEGORY="${1:-}"

# .doc_structure.yaml doesn't exist → not configured
[[ ! -f "$CONFIG" ]] && {
    echo "[ACTION REQUIRED] Doc Advisor: .doc_structure.yaml not found. Run /setup-doc-structure skill to create document structure configuration. This must be completed before document search or ToC generation will work. If in plan mode, run /setup-doc-structure after exiting plan mode."
    exit 0
}

if [[ -n "$CATEGORY" ]]; then
    # Category-specific check: look for root_dirs (v2.0) or paths (v1.0) within the target section
    in_section=$(awk -v cat="$CATEGORY" '
        /^(rules|specs|common):/ { sub(/:.*/, ""); section = $0 }
        section == cat && /^  root_dirs:/ { found=1; exit }
        section == cat && /^    paths:/ { found=1; exit }
        END { print (found ? "yes" : "no") }
    ' "$CONFIG")

    [[ "$in_section" == "yes" ]] && exit 0
else
    # No category specified: check if any root_dirs (v2.0) or paths (v1.0) exists
    grep -q "^  root_dirs:" "$CONFIG" 2>/dev/null && exit 0
    grep -q "^    paths:" "$CONFIG" 2>/dev/null && exit 0
fi

# Not configured → warn
echo "[ACTION REQUIRED] Doc Advisor: Document directories are not configured${CATEGORY:+ for '$CATEGORY'}. Run /setup-doc-structure skill to auto-detect and configure document directories. This must be completed before document search or ToC generation will work. If in plan mode, run /setup-doc-structure after exiting plan mode."
