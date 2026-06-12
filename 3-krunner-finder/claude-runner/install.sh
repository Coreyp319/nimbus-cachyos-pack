#!/usr/bin/env bash
# Agent B (part 2) — KRunner "Ask Claude" + web-search D-Bus runner. User-level, no sudo.
# Web search (DuckDuckGo/GitHub/Wikipedia/YouTube) always works; "Ask Claude" is enabled
# only if the `claude` CLI is found on PATH (otherwise it stays hidden).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.local/share/krunner-claude-runner"
SVC="dev.corey.krunner.claude"   # fixed D-Bus namespace (unique; fine on any machine)

mkdir -p "$DEST" "$HOME/.local/share/dbus-1/services" "$HOME/.local/share/krunner/dbusplugins"

# Deploy the runner, templating CLAUDE_BIN to the detected CLI (or empty = Claude hidden).
install -m755 "$HERE/claude_runner.py" "$DEST/claude_runner.py"
CLAUDE="$(command -v claude || true)"
sed -i "s|^CLAUDE_BIN = .*|CLAUDE_BIN = \"${CLAUDE}\"|" "$DEST/claude_runner.py"
[ -n "$CLAUDE" ] && echo ":: claude CLI: $CLAUDE — 'Ask Claude' enabled." \
                 || echo ":: claude CLI not found — web search only (Ask Claude hidden)."

# D-Bus activation (Exec path templated to this machine's deploy dir).
sed "s|^Exec=.*|Exec=$DEST/claude_runner.py|" "$HERE/dbus-service.tmpl" \
  > "$HOME/.local/share/dbus-1/services/$SVC.service"
# KRunner plugin registration (verbatim — carries the required X-KDE-ServiceTypes etc.).
install -m644 "$HERE/plugin.desktop.tmpl" "$HOME/.local/share/krunner/dbusplugins/$SVC.desktop"
kwriteconfig6 --file krunnerrc --group Plugins --key claudesearchEnabled true

# Dependency hint (informational; not fatal).
python3 -c 'import dbus, gi' 2>/dev/null || \
  echo "   NOTE: needs python-dbus + python-gobject →  sudo pacman -S --needed python-dbus python-gobject"

kquitapp6 krunner 2>/dev/null || true
echo ":: Runner installed. Open KRunner (Alt+Space), type and pause ~3s, or use s …/c … prefixes."
