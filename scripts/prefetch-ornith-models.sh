#!/usr/bin/env bash
set -euo pipefail

OLLAMA_BIN="${1:?usage: prefetch-ornith-models.sh <path-to-ollama>}"
MODELS_DIR="${OLLAMA_MODELS:-/var/lib/ollama/models}"
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ollama-prefetch"
mkdir -p "$MODELS_DIR" "$LOG_DIR"

export HOME="${OLLAMA_HOME:-/var/lib/ollama}"
export OLLAMA_MODELS="$MODELS_DIR"
export OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11435}"

mkdir -p "$HOME"

if ! curl -sf "http://${OLLAMA_HOST#*://}/api/tags" >/dev/null 2>&1; then
  echo "starting ollama serve on $OLLAMA_HOST"
  "$OLLAMA_BIN" serve >"$LOG_DIR/serve.log" 2>&1 &
  SERVE_PID=$!
  trap 'kill "$SERVE_PID" 2>/dev/null || true' EXIT
  for _ in $(seq 1 60); do
    if curl -sf "http://${OLLAMA_HOST#*://}/api/tags" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
fi

echo "pulling ornith:9b into $MODELS_DIR"
"$OLLAMA_BIN" pull ornith:9b | tee "$LOG_DIR/ornith-9b.log"

echo "pulling ornith:35b into $MODELS_DIR"
"$OLLAMA_BIN" pull ornith:35b | tee "$LOG_DIR/ornith-35b.log"

echo "done; models in $MODELS_DIR"
"$OLLAMA_BIN" list