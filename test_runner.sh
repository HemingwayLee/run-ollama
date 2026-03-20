#!/bin/bash

curl http://localhost:11434/api/generate -d '{
  "model": "gemma3:12b",
  "prompt": "Write a short poem about the ocean.",
  "stream": false
}'

