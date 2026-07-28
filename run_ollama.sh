#!/bin/bash

docker run -d \
  -v ollama:/root/.ollama \
  -p 11434:11434 \
  -e OLLAMA_ORIGINS="*" \
  --name ollama \
  ollama/ollama:0.13.3

docker exec ollama ollama pull gemma3:12b
