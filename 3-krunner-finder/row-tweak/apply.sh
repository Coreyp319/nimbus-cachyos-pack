#!/usr/bin/env bash
# Persistent applier for krunner-row-tweak. Installed to
# /usr/local/share/krunner-row-tweak/apply.sh and invoked by the pacman hook
# after every milou upgrade. Idempotent.
set -euo pipefail

CANON_DIR="/usr/local/share/krunner-row-tweak"
MILOU_DIR="/usr/lib/qt6/qml/org/kde/milou"
QMLDIR="$MILOU_DIR/qmldir"

# 1. Install our patched QML files over the system copies.
for f in ResultDelegate.qml ResultsView.qml; do
  [ -f "$CANON_DIR/$f" ] && install -m644 "$CANON_DIR/$f" "$MILOU_DIR/$f"
done

# 2. Drop the `prefer :/qt/qml/...` line so Qt loads the on-disk .qml instead of
#    the copy compiled into libmilou.so. Idempotent: only acts if present.
if grep -q '^prefer :/qt/qml/org/kde/milou/' "$QMLDIR"; then
  sed -i '\#^prefer :/qt/qml/org/kde/milou/#d' "$QMLDIR"
fi
