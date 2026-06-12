#!/usr/bin/env bash
# Revert Agent B's KRunner bundle.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SVC="dev.corey.krunner.claude"

echo "── Reverting row styling (needs sudo: restores milou QML, removes hook) ──"
sudo bash "$HERE/row-tweak/revert.sh" 2>/dev/null || echo "   (row-tweak revert skipped/failed — run: sudo bash $HERE/row-tweak/revert.sh)"

echo "── Removing the Ask-Claude / web-search runner ──"
kwriteconfig6 --file krunnerrc --group Plugins --key claudesearchEnabled false
rm -f "$HOME/.local/share/dbus-1/services/$SVC.service" \
      "$HOME/.local/share/krunner/dbusplugins/$SVC.desktop"
rm -rf "$HOME/.local/share/krunner-claude-runner"
kquitapp6 krunner 2>/dev/null || true
echo "Done. KRunner is back to stock."
