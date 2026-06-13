#!/usr/bin/env bash
# Layer 6 — Local AI (Ollama + Hermes), CachyOS / Arch.
#
# Stands up a local LLM stack on this machine's NVIDIA GPU:
#   • ollama-cuda     — the runner + an OpenAI-compatible API on :11434
#   • Hermes 4 14B    — Q8_0, fully GPU-resident (~15.7 GB), fast/snappy
#   • Hermes 4.3 36B  — Q4_K_M (~22 GB), smarter, light CPU offload on 24 GB
#
# No sandbox yet — this just serves the models. Each item is opt-in (answer per
# prompt); pass -y to accept them all. Uses sudo only for the package install.
#
# Run as your normal user: bash 6-local-ai/install.sh   (add -y for all)
# Reversible via revert.sh (add --purge to also remove the package + models).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" -eq 0 ] && { echo "Run as your normal user, not root."; exit 1; }

ALL=0; case "${1:-}" in -y|--yes) ALL=1 ;; -h|--help)
  echo "Usage: bash install.sh [-y]   (-y sets up the whole local-AI stack)"; exit 0 ;;
esac

ok(){ printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn(){ printf '  \033[33m!\033[0m %s\n' "$1"; }
msg(){ printf '\n\033[1m:: %s\033[0m\n' "$1"; }
ask(){ [ "$ALL" = 1 ] && return 0; printf '  Set up %s? [Y/n] ' "$1"
       read -r r </dev/tty 2>/dev/null || r=n; case "$r" in [nN]*) return 1 ;; *) return 0 ;; esac; }

echo ":: Layer 6 — local AI (Ollama + Hermes). Pick what you want (Enter = yes)."

# --- ollama-cuda + service -------------------------------------------------
if ask "ollama-cuda runner + service (NVIDIA)"; then
  msg "Installing ollama-cuda…"
  sudo pacman -S --needed --noconfirm ollama-cuda && ok "ollama-cuda installed"

  # KV-cache tuning so large context windows (Hermes needs ≥64K) fit the GPU
  # with less CPU spill. Installed before first start so it's active immediately.
  sudo install -Dm644 "$HERE/ollama-kv-cache.conf" \
    /etc/systemd/system/ollama.service.d/10-kv-cache.conf \
    && ok "KV-cache drop-in installed (flash attn + q8_0)"
  sudo systemctl daemon-reload

  sudo systemctl enable --now ollama.service && ok "ollama.service enabled"

  # Wait for the HTTP API to answer before doing anything model-related.
  printf '  waiting for API on :11434'
  for _ in $(seq 1 30); do
    curl -sf http://localhost:11434/api/version >/dev/null 2>&1 && break
    printf '.'; sleep 1
  done; echo
  if curl -sf http://localhost:11434/api/version >/dev/null 2>&1; then
    ok "API up — $(curl -s http://localhost:11434/api/version)"
  else
    warn "API not responding yet; check: systemctl status ollama"
  fi

  # Confirm the GPU is actually visible to ollama (vs silent CPU fallback).
  if journalctl -u ollama --no-pager -b 2>/dev/null | grep -qiE 'cuda|nvidia|compute capability'; then
    ok "CUDA GPU detected by ollama"
  else
    warn "No CUDA line in ollama logs yet — verify with: ollama ps  (after a run)"
  fi
fi

command -v ollama >/dev/null 2>&1 || { warn "ollama not installed — skipping model pulls."; msg "Layer 6 done."; exit 0; }

# --- Hermes 4 14B (fast) ---------------------------------------------------
if ask "pull Hermes 4 14B  (Q8_0, ~15.7 GB, full GPU)"; then
  msg "Building hermes4-14b…  (large download, be patient)"
  if ollama create hermes4-14b -f "$HERE/Modelfile.hermes4-14b"; then
    ok "hermes4-14b ready  →  ollama run hermes4-14b"
  else
    warn "hermes4-14b build failed — see output above"
  fi
fi

# --- Hermes 4.3 36B (smarter) ----------------------------------------------
if ask "pull Hermes 4.3 36B  (Q4_K_M, ~22 GB, light CPU offload)"; then
  msg "Building hermes4.3-36b…  (large download, be patient)"
  if ollama create hermes4.3-36b -f "$HERE/Modelfile.hermes4.3-36b"; then
    ok "hermes4.3-36b ready  →  ollama run hermes4.3-36b"
  else
    warn "hermes4.3-36b build failed — see output above"
  fi
fi

# --- Smoke test ------------------------------------------------------------
if ask "run a quick smoke test against the OpenAI-compatible endpoint"; then
  msg "Smoke test (/v1/chat/completions)…"
  SMOKE_MODEL="$(ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -E '^hermes' | head -1)"
  if [ -n "$SMOKE_MODEL" ]; then
    echo "  model: $SMOKE_MODEL"
    curl -s http://localhost:11434/v1/chat/completions \
      -H 'Content-Type: application/json' \
      -d "{\"model\":\"$SMOKE_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: pong\"}],\"max_tokens\":16}" \
      | sed -E 's/.*"content":"([^"]*)".*/  reply: \1/' || warn "smoke test request failed"
    echo; ollama ps
  else
    warn "no hermes model found to test"
  fi
fi

cat <<EOF

$(printf '\033[1m:: Layer 6 done.\033[0m')
   Endpoints (localhost only by default):
     • Ollama native :  http://localhost:11434/api
     • OpenAI compat :  http://localhost:11434/v1   (api_key can be any string)
   Models:  ollama list      Run:  ollama run hermes4-14b
   Example (OpenAI SDK):  base_url="http://localhost:11434/v1", model="hermes4-14b"
EOF
