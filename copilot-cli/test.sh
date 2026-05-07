#!/bin/bash
# test.sh — Local test suite for the copilot-cli nono pack
# Run from the repo root: bash copilot-cli/test.sh
# Or from the pack directory: bash test.sh

PACK_DIR="$(cd "$(dirname "$0")" && pwd)"

PASS=0
FAIL=0

green='\033[0;32m'
red='\033[0;31m'
bold='\033[1m'
reset='\033[0m'

pass() { echo -e "  ${green}PASS${reset} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${red}FAIL${reset} $1"; FAIL=$((FAIL + 1)); }
header() { echo -e "\n${bold}── $1${reset}"; }

# ── 1. Validate package.json ──────────────────────────────────────────────────
header "1. Validate package.json"

if jq . "$PACK_DIR/package.json" > /dev/null 2>&1; then
  pass "package.json is valid JSON"
else
  fail "package.json is invalid JSON"
fi

# ── 2. Artifact paths ─────────────────────────────────────────────────────────
header "2. Artifact paths"

while IFS= read -r p; do
  if [ -f "$PACK_DIR/$p" ]; then
    pass "$p"
  else
    fail "$p  (file missing)"
  fi
done < <(jq -r '.artifacts[].path' "$PACK_DIR/package.json")

# ── 3. Hook script unit tests ─────────────────────────────────────────────────
header "3. Hook scripts"

CAPS_FILE="$(mktemp)"
cat > "$CAPS_FILE" <<'EOF'
{
  "fs": [
    { "path": "/tmp", "resolved": "/tmp", "access": "read-write" }
  ],
  "net_blocked": true
}
EOF
cleanup() { rm -f "$CAPS_FILE"; }
trap cleanup EXIT

# assert_json: pipe input, expect hookSpecificOutput in output
assert_json() {
  local label="$1" input="$2" script="$3"
  local out
  out=$(echo "$input" | NONO_CAP_FILE="$CAPS_FILE" bash "$script" 2>&1)
  if echo "$out" | jq -e '.hookSpecificOutput' > /dev/null 2>&1; then
    pass "$label"
  else
    fail "$label  (expected JSON with hookSpecificOutput, got: $out)"
  fi
}

# assert_silent: pipe input, expect no output and exit 0
assert_silent() {
  local label="$1" input="$2" script="$3" extra_env="${4:-}"
  local out exit_code
  if [ -n "$extra_env" ]; then
    out=$(echo "$input" | env -i HOME="$HOME" PATH="$PATH" $extra_env bash "$script" 2>&1)
  else
    out=$(echo "$input" | NONO_CAP_FILE="$CAPS_FILE" bash "$script" 2>&1)
  fi
  exit_code=$?
  if [ -z "$out" ] && [ "$exit_code" -eq 0 ]; then
    pass "$label"
  else
    fail "$label  (expected silent exit 0, got exit=$exit_code output='$out')"
  fi
}

# nono-hook.sh (PostToolUseFailure)
assert_json \
  "nono-hook.sh: denial in error → emits JSON" \
  '{"hook_event_name":"PostToolUseFailure","tool_name":"bash","error":"Operation not permitted"}' \
  "$PACK_DIR/bin/nono-hook.sh"

assert_silent \
  "nono-hook.sh: no denial → silent" \
  '{"hook_event_name":"PostToolUseFailure","tool_name":"bash","error":"some other error"}' \
  "$PACK_DIR/bin/nono-hook.sh"

# nono-hook-bash.sh (PostToolUse)
assert_json \
  "nono-hook-bash.sh: bash tool + denial in output → emits JSON" \
  '{"hook_event_name":"PostToolUse","tool_name":"bash","tool_result":{"result_type":"text","text_result_for_llm":"Operation not permitted"}}' \
  "$PACK_DIR/bin/nono-hook-bash.sh"

assert_silent \
  "nono-hook-bash.sh: non-bash tool → silent" \
  '{"hook_event_name":"PostToolUse","tool_name":"view","tool_result":{"result_type":"text","text_result_for_llm":"some output"}}' \
  "$PACK_DIR/bin/nono-hook-bash.sh"

assert_silent \
  "nono-hook-bash.sh: bash tool, no denial → silent" \
  '{"hook_event_name":"PostToolUse","tool_name":"bash","tool_result":{"result_type":"text","text_result_for_llm":"hello world"}}' \
  "$PACK_DIR/bin/nono-hook-bash.sh"

# nono-hook-session.sh (SessionStart)
assert_json \
  "nono-hook-session.sh: emits JSON with context" \
  "" \
  "$PACK_DIR/bin/nono-hook-session.sh"

# All hooks: no NONO_CAP_FILE → silent
for script in nono-hook.sh nono-hook-bash.sh nono-hook-session.sh; do
  out=$(echo '{}' | bash "$PACK_DIR/bin/$script" 2>&1)
  exit_code=$?
  if [ -z "$out" ] && [ "$exit_code" -eq 0 ]; then
    pass "$script: no NONO_CAP_FILE → silent"
  else
    fail "$script: no NONO_CAP_FILE → expected silent exit 0, got exit=$exit_code output='$out'"
  fi
done

# ── 4. nono profile ───────────────────────────────────────────────────────────
header "4. nono profile"
echo "if stuck, press enter to continue..."

if ! command -v nono &> /dev/null; then
  echo "  SKIP  (nono not installed)"
else
  if nono run --profile "$PACK_DIR/policy.json" -- echo "sandbox ok" > /dev/null 2>&1; then
    pass "sandbox starts and runs a command"
  else
    fail "sandbox failed to start"
  fi

  if nono run --profile "$PACK_DIR/policy.json" -- ls "$HOME/.copilot" > /dev/null 2>&1; then
    pass "~/.copilot is readable inside sandbox"
  else
    fail "~/.copilot is not accessible inside sandbox — check policy.json"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────"
echo -e "  ${green}${PASS} passed${reset}   ${red}${FAIL} failed${reset}"
echo "────────────────────────────────────"

[ "$FAIL" -eq 0 ]
