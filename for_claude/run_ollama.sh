#!/bin/bash
# Start an Ollama container that Claude Code can talk to.
# Claude Code needs Ollama's Anthropic-compatible /v1/messages API (Ollama >= 0.14).
#
# Usage:
#   ./run_ollama.sh                                   # latest image, gemma4:e4b
#   OLLAMA_IMAGE=ollama/ollama:0.14.0 MODEL=qwen3-coder ./run_ollama.sh

set -euo pipefail

OLLAMA_IMAGE="${OLLAMA_IMAGE:-ollama/ollama:0.40.16}"
MODEL="${MODEL:-gemma4:e4b}"
CONTAINER="${CONTAINER:-ollama-claude}"
PORT="${PORT:-11434}"
# Claude Code's system prompt + tools are large; the small default context truncates it.
CONTEXT_LENGTH="${CONTEXT_LENGTH:-32768}"

docker pull "$OLLAMA_IMAGE"

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "Removing existing container '$CONTAINER' (models stay in the 'ollama' volume)"
  docker rm -f "$CONTAINER" >/dev/null
fi

docker run -d \
  -v ollama:/root/.ollama \
  -p "$PORT":11434 \
  -e OLLAMA_ORIGINS="*" \
  -e OLLAMA_CONTEXT_LENGTH="$CONTEXT_LENGTH" \
  --name "$CONTAINER" \
  "$OLLAMA_IMAGE"

echo "Waiting for Ollama on port $PORT..."
for _ in $(seq 1 30); do
  curl -sf "http://localhost:$PORT/" >/dev/null && break
  sleep 1
done

docker exec "$CONTAINER" ollama --version
docker exec "$CONTAINER" ollama pull "$MODEL"
