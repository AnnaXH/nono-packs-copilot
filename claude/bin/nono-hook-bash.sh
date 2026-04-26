#!/bin/bash
# nono-hook-bash.sh - PostToolUse hook for Bash commands
# Version: 1.0.0
#
# Inspects a Bash tool result for sandbox-denial patterns and injects
# context so Claude can guide the user.

if [ -z "$NONO_CAP_FILE" ] || [ ! -f "$NONO_CAP_FILE" ]; then
    exit 0
fi
if ! command -v jq &> /dev/null; then
    exit 0
fi

INPUT=$(cat)
OUTPUT=$(echo "$INPUT" | jq -r '.tool_result // ""' 2>/dev/null)

if ! echo "$OUTPUT" | grep -qiE 'operation not permitted|permission denied|EPERM|EACCES|sandbox.*denied|landlock'; then
    exit 0
fi

CAPS=$(jq -r '.fs[] | "  " + (.resolved // .path) + " (" + .access + ")"' "$NONO_CAP_FILE" 2>/dev/null)
NET=$(jq -r 'if .net_blocked then "blocked" else "allowed" end' "$NONO_CAP_FILE" 2>/dev/null)

CONTEXT="[NONO SANDBOX - PERMISSION DENIED]

This is a nono sandbox denial, not macOS TCC or a Unix permissions issue.

Allowed paths:
$CAPS
Network: $NET

Run \`nono why --path <blocked-path> --op read\` to diagnose, then present the user with two options:

  Option A (quick fix): exit and restart with the path allowed:
    nono run --allow /path/to/needed -- claude

  Option B (persistent fix): write a nono profile. Run \`nono profile guide\` for the schema, then save a profile JSON at ~/.config/nono/profiles/<name>.json. Start sessions with:
    nono run --profile <name> -- claude"

jq -n --arg ctx "$CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $ctx
  }
}'
