#!/usr/bin/env bash
# Layer 6 revert — stops/disables the Ollama service. With --purge it also
# removes the two Hermes models, the ollama-cuda package, and (optionally) the
# downloaded model blobs under /var/lib/ollama.
set -uo pipefail
PURGE="${1:-}"

echo "── Layer 6: local AI (Ollama + Hermes) ──"

if systemctl list-unit-files ollama.service >/dev/null 2>&1; then
  sudo systemctl disable --now ollama.service 2>/dev/null && echo "  ✓ ollama.service stopped + disabled" || true
fi

# Remove the KV-cache tuning drop-in if present.
if [ -f /etc/systemd/system/ollama.service.d/10-kv-cache.conf ]; then
  sudo rm -f /etc/systemd/system/ollama.service.d/10-kv-cache.conf \
    && echo "  ✓ removed KV-cache drop-in" || true
  sudo rmdir /etc/systemd/system/ollama.service.d 2>/dev/null || true
  sudo systemctl daemon-reload 2>/dev/null || true
fi

if [ "$PURGE" = "--purge" ]; then
  if command -v ollama >/dev/null 2>&1; then
    for m in hermes4-14b hermes4.3-36b; do
      ollama rm "$m" 2>/dev/null && echo "  ✓ removed model $m" || true
    done
  fi
  sudo pacman -Rns --noconfirm ollama-cuda 2>/dev/null && echo "  ✓ ollama-cuda removed" || true
  # The package leaves the model store behind; offer to clear it too.
  if [ -d /var/lib/ollama ]; then
    sudo rm -rf /var/lib/ollama && echo "  ✓ cleared /var/lib/ollama (downloaded blobs)" || true
  fi
else
  echo "  service disabled. Package + downloaded models kept."
  echo "  Re-run with --purge to remove ollama-cuda and the Hermes models too."
fi
