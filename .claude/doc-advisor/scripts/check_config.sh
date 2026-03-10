#!/bin/bash
# Doc Advisor config check: verify document directories are configured.
# Called from skill Pre-check steps. If not configured, outputs a warning
# that tells Claude to run /setup-config first.
# Exit 0 with no output = directories are configured (OK).
#
# Usage: bash check_config.sh [rules|specs]
#   With argument: check specific category's root_dirs
#   Without argument: check if ANY root_dirs is set (backward compatibility)
#
# Created by k_terada

# Hook cwd is not guaranteed to be project root; use $CLAUDE_PROJECT_DIR
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

CONFIG=".claude/doc-advisor/config.yaml"
CATEGORY="${1:-}"

# config.yaml doesn't exist → Doc Advisor not installed
[[ ! -f "$CONFIG" ]] && exit 0

if [[ -n "$CATEGORY" ]]; then
    # Category-specific check: look for uncommented root_dirs within the target section
    in_section=$(awk -v cat="$CATEGORY" '
        /^(rules|specs|common):/ { sub(/:.*/, ""); section = $0 }
        section == cat && /^  root_dirs:/ { found=1; exit }
        END { print (found ? "yes" : "no") }
    ' "$CONFIG")

    [[ "$in_section" == "yes" ]] && exit 0
else
    # No category specified: check if any root_dirs exists (backward compat)
    grep -q "^  root_dirs:" "$CONFIG" 2>/dev/null && exit 0
fi

# Not configured → warn
echo "[ACTION REQUIRED] Doc Advisor: Document directories are not configured${CATEGORY:+ for '$CATEGORY'}. Run /setup-config skill to auto-detect and configure document directories. This must be completed before document search or ToC generation will work. If in plan mode, run /setup-config after exiting plan mode."
