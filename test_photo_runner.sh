#!/bin/bash

PHOTO_PATH="$(dirname "$0")/photo1.png"
IMAGE_B64=$(base64 -i "$PHOTO_PATH")

TMPFILE=$(mktemp /tmp/ollama_request.XXXXXX.json)
cat > "$TMPFILE" <<EOF
{
  "model": "gemma3:12b",
  "prompt": "Describe what you see in this image.",
  "images": ["$IMAGE_B64"],
  "stream": false
}
EOF

curl http://localhost:11434/api/generate -d @"$TMPFILE"
rm -f "$TMPFILE"

