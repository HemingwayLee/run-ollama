#!/bin/bash
# Check that an Ollama image + model combination works for Claude Code.
#
# Usage:
#   ./test_claude_ollama.sh                       # gemma4:e4b on localhost:11434
#   MODEL=qwen3-coder ./test_claude_ollama.sh     # try another model
#   OLLAMA_HOST=http://192.168.0.10:11434 ./test_claude_ollama.sh
#   SKIP_CLAUDE=1 ./test_claude_ollama.sh         # API checks only
#
# Tests:
#   1. server is up + version (needs >= 0.14 for /v1/messages)
#   2. model is installed (pulls it if not, when the container is local)
#   3. native  /api/generate
#   4. Anthropic /v1/messages  (what Claude Code calls)
#   5. Anthropic /v1/messages with a tool  (Claude Code needs tool calling)
#   6. Anthropic /v1/messages with an image (vision models only)
#   7. real `claude -p` run against the server

set -uo pipefail

MODEL="${MODEL:-gemma4:e4b}"
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
CONTAINER="${CONTAINER:-ollama-claude}"
PHOTO_PATH="${PHOTO_PATH:-$(dirname "$0")/../photo1.png}"
TIMEOUT="${TIMEOUT:-300}"
# Thinking models (e.g. gemma4) spend hundreds of tokens reasoning before the
# text block; a small budget ends in stop_reason=max_tokens with no text.
MAX_TOKENS="${MAX_TOKENS:-2048}"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
need() { command -v "$1" >/dev/null || { echo "missing required command: $1"; exit 1; }; }
need curl; need jq

TMPDIR_T=$(mktemp -d)
trap 'rm -rf "$TMPDIR_T"' EXIT

post() { # post <path> <json-file> -> body on stdout
  curl -s -m "$TIMEOUT" "$OLLAMA_HOST$1" \
    -H 'content-type: application/json' \
    -H 'x-api-key: ollama' \
    -H 'anthropic-version: 2023-06-01' \
    -d @"$2"
}

why() { # explain an empty-text response
  local sr; sr=$(echo "$1" | jq -r '.stop_reason // empty' 2>/dev/null)
  if [ "$sr" = "max_tokens" ]; then
    echo "hit max_tokens=$MAX_TOKENS before any text (thinking used the budget; raise MAX_TOKENS)"
  else
    echo "$2: $(echo "$1" | head -c 300)"
  fi
}

echo "== Ollama: $OLLAMA_HOST   model: $MODEL"

echo "[1] server + version"
if ! curl -sf -m 5 "$OLLAMA_HOST/" >/dev/null; then
  fail "server not reachable at $OLLAMA_HOST (run ./run_ollama.sh)"; exit 1
fi
VERSION=$(curl -s "$OLLAMA_HOST/api/version" | jq -r .version)
echo "  version: $VERSION"
if [ "$(printf '%s\n0.14.0\n' "$VERSION" | sort -V | head -1)" = "0.14.0" ]; then
  pass "version >= 0.14.0"
else
  fail "version $VERSION < 0.14.0 — no /v1/messages; use a newer image"
fi

echo "[2] model installed"
if curl -s "$OLLAMA_HOST/api/tags" | jq -e --arg m "$MODEL" '.models[] | select(.name==$m or .model==$m)' >/dev/null; then
  pass "$MODEL present"
elif command -v docker >/dev/null && docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "  pulling $MODEL into $CONTAINER..."
  if docker exec "$CONTAINER" ollama pull "$MODEL"; then pass "pulled $MODEL"; else fail "pull $MODEL"; exit 1; fi
else
  fail "$MODEL not installed (ollama pull $MODEL)"; exit 1
fi

echo "[3] /api/generate"
jq -n --arg m "$MODEL" '{model:$m, prompt:"Reply with the single word: pong", stream:false}' > "$TMPDIR_T/gen.json"
OUT=$(post /api/generate "$TMPDIR_T/gen.json")
TEXT=$(echo "$OUT" | jq -r '.response // empty')
[ -n "$TEXT" ] && pass "response: $(echo "$TEXT" | head -c 80)" || fail "no response: $(echo "$OUT" | head -c 300)"

echo "[4] /v1/messages (Anthropic API)"
jq -n --arg m "$MODEL" --argjson n "$MAX_TOKENS" '{model:$m, max_tokens:$n,
  messages:[{role:"user", content:"Reply with the single word: pong"}]}' > "$TMPDIR_T/msg.json"
OUT=$(post /v1/messages "$TMPDIR_T/msg.json")
TEXT=$(echo "$OUT" | jq -r '[.content[]? | select(.type=="text") | .text] | join("")')
[ -n "$TEXT" ] && pass "response: $(echo "$TEXT" | head -c 80)" || fail "$(why "$OUT" "bad response")"

echo "[5] /v1/messages with tool use"
jq -n --arg m "$MODEL" --argjson n "$MAX_TOKENS" '{model:$m, max_tokens:$n,
  tools:[{name:"get_weather", description:"Get the current weather for a city",
          input_schema:{type:"object", properties:{city:{type:"string"}}, required:["city"]}}],
  messages:[{role:"user", content:"What is the weather in Seoul? Use the tool."}]}' > "$TMPDIR_T/tool.json"
OUT=$(post /v1/messages "$TMPDIR_T/tool.json")
TOOL=$(echo "$OUT" | jq -c '.content[]? | select(.type=="tool_use") | {name, input}' | head -1)
[ -n "$TOOL" ] && pass "tool_use: $TOOL" || fail "$(why "$OUT" "no tool_use block (model may not support tools)")"

echo "[6] /v1/messages with image"
if [ -f "$PHOTO_PATH" ]; then
  base64 -i "$PHOTO_PATH" | tr -d '\n' > "$TMPDIR_T/img.b64"
  jq -n --arg m "$MODEL" --argjson n "$MAX_TOKENS" --rawfile img "$TMPDIR_T/img.b64" '{model:$m, max_tokens:$n,
    messages:[{role:"user", content:[
      {type:"image", source:{type:"base64", media_type:"image/png", data:$img}},
      {type:"text", text:"Describe this image in one sentence."}]}]}' > "$TMPDIR_T/img.json"
  OUT=$(post /v1/messages "$TMPDIR_T/img.json")
  TEXT=$(echo "$OUT" | jq -r '[.content[]? | select(.type=="text") | .text] | join("")')
  [ -n "$TEXT" ] && pass "response: $(echo "$TEXT" | head -c 120)" || fail "$(why "$OUT" "bad response (model may not support vision)")"
else
  echo "  skipped: $PHOTO_PATH not found"
fi

echo "[7] claude -p through Ollama"
if [ -n "${SKIP_CLAUDE:-}" ]; then
  echo "  skipped (SKIP_CLAUDE set)"
elif ! command -v claude >/dev/null; then
  echo "  skipped: claude not installed"
else
  # macOS has no `timeout` unless coreutils is installed (gtimeout)
  TO=""; command -v timeout >/dev/null && TO="timeout $TIMEOUT"
  command -v gtimeout >/dev/null && TO="gtimeout $TIMEOUT"
  OUT=$(ANTHROPIC_BASE_URL="$OLLAMA_HOST" \
        ANTHROPIC_AUTH_TOKEN=ollama \
        ANTHROPIC_API_KEY="" \
        ANTHROPIC_DEFAULT_OPUS_MODEL="$MODEL" \
        ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL" \
        ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL" \
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
        $TO claude -p --model "$MODEL" "Reply with the single word: pong" 2>"$TMPDIR_T/claude.err")
  RC=$?
  # stderr carries harmless notices (e.g. "claude.ai connectors are disabled
  # because ... auth source is set"), so judge only the model's stdout.
  if [ $RC -eq 0 ] && echo "$OUT" | grep -qi pong; then
    pass "claude said: $(echo "$OUT" | head -c 120)"
  else
    fail "claude exit $RC, stdout: $(echo "$OUT" | head -c 200) stderr: $(head -c 300 "$TMPDIR_T/claude.err")"
  fi
fi

echo
echo "== $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
