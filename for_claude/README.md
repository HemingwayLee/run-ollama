# Run Claude Code against Ollama (gemma4:e4b)

Claude Code talks the Anthropic Messages API. Ollama serves a compatible
endpoint at `/v1/messages` starting with **Ollama 0.14.0**. The `ollama/ollama:0.13.3`
image in the top-level README is too old for this, so use a newer image.

## install
```
docker pull ollama/ollama:0.40.16
```

## how to run
```
docker run -d -v ollama:/root/.ollama -p 11434:11434 \
  -e OLLAMA_ORIGINS="*" \
  -e OLLAMA_CONTEXT_LENGTH=32768 \
  --name ollama-claude ollama/ollama:0.40.16

docker exec ollama-claude ollama pull gemma4:e4b
```
or just
```
./run_ollama.sh
OLLAMA_IMAGE=ollama/ollama:0.14.0 MODEL=qwen3-coder ./run_ollama.sh   # other image/model
```

## Note
* The container reuses the named volume `ollama` (mounted at `/root/.ollama`), so models
  pulled by the old container are still there.
* `OLLAMA_CONTEXT_LENGTH`: Claude Code sends a large system prompt plus tool definitions.
  With Ollama's small default context the prompt gets truncated and the model acts confused.
  Use at least 32k if you have the memory for it.
* The model must support **tool calling**, or Claude Code can't read or edit files.
  gemma4 supports tools. Small models like `e4b` handle simple tasks but struggle
  with long, multi-step agent work.

## point Claude Code to Ollama
```
export ANTHROPIC_BASE_URL=http://localhost:11434
export ANTHROPIC_AUTH_TOKEN=ollama        # any non-empty value; Ollama ignores it
export ANTHROPIC_API_KEY=""
# Claude Code uses a "haiku" model for background tasks. Map every tier to the local model
export ANTHROPIC_DEFAULT_OPUS_MODEL=gemma4:e4b
export ANTHROPIC_DEFAULT_SONNET_MODEL=gemma4:e4b
export ANTHROPIC_DEFAULT_HAIKU_MODEL=gemma4:e4b
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

claude --model gemma4:e4b
```

* One-liner, without changing your shell:
```
ANTHROPIC_BASE_URL=http://localhost:11434 ANTHROPIC_AUTH_TOKEN=ollama ANTHROPIC_API_KEY="" \
  claude --model gemma4:e4b
```

* Or keep it per project in `.claude/settings.local.json`:
```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:11434",
    "ANTHROPIC_AUTH_TOKEN": "ollama",
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_MODEL": "gemma4:e4b",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "gemma4:e4b",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
  }
}
```

* If Ollama is installed natively (not docker), newer versions can set this up for you:
```
ollama launch claude --model gemma4:e4b
```

* Inside Claude Code, `/status` shows the base URL and model in use.

## how to test outside of docker
* run all checks (needs `curl` and `jq`)
```
./test_claude_ollama.sh
MODEL=qwen3-coder ./test_claude_ollama.sh                  # test another model
OLLAMA_HOST=http://192.168.0.10:11434 ./test_claude_ollama.sh
SKIP_CLAUDE=1 ./test_claude_ollama.sh                       # API checks only
```

* what it checks

| # | check | why |
|---|-------|-----|
| 1 | server up, version >= 0.14.0 | `/v1/messages` exists |
| 2 | model installed (pulls it if missing) | |
| 3 | `/api/generate` | the model loads and answers |
| 4 | `/v1/messages` | the endpoint Claude Code calls |
| 5 | `/v1/messages` with a tool | Claude Code needs tool calling |
| 6 | `/v1/messages` with `../photo1.png` | vision (optional) |
| 7 | `claude -p` end to end | the real thing |

* test the Anthropic endpoint by hand
```
curl http://localhost:11434/v1/messages \
  -H 'content-type: application/json' \
  -H 'x-api-key: ollama' \
  -H 'anthropic-version: 2023-06-01' \
  -d '{
  "model": "gemma4:e4b",
  "max_tokens": 256,
  "messages": [{"role": "user", "content": "Write a short poem about the ocean."}]
}'
```

# Note
```
docker exec ollama-claude ollama ps        # is the model loaded? CPU or GPU?
docker exec ollama-claude ollama ls
docker exec ollama-claude ollama stop gemma4:e4b
docker logs -f ollama-claude               # watch requests coming from Claude Code
unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY   # back to Anthropic
```
* Docker Desktop on macOS has no GPU access, so models run on CPU and are slow.
  For Apple Silicon GPU speed, install Ollama natively (`brew install ollama`, `ollama serve`).
