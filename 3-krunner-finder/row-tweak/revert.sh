#!/usr/bin/env bash
# Undo krunner-row-tweak: restore original milou delegate + qmldir, remove hook.
# Run as root:  sudo ~/.local/share/krunner-row-tweak/revert.sh
set -euo pipefail

CANON_DIR="/usr/local/share/krunner-row-tweak"
MILOU_DIR="/usr/lib/qt6/qml/org/kde/milou"
HOOK="/etc/pacman.d/hooks/krunner-row-tweak.hook"

if [[ $EUID -ne 0 ]]; then
  echo "This script must run as root. Try: sudo $0" >&2
  exit 1
fi

if [[ -f "$CANON_DIR/ResultDelegate.qml.orig" ]]; then
  install -m644 "$CANON_DIR/ResultDelegate.qml.orig" "$MILOU_DIR/ResultDelegate.qml"
  echo "==> restored ResultDelegate.qml"
fi
if [[ -f "$CANON_DIR/ResultsView.qml.orig" ]]; then
  install -m644 "$CANON_DIR/ResultsView.qml.orig" "$MILOU_DIR/ResultsView.qml"
  echo "==> restored ResultsView.qml"
fi
if [[ -f "$CANON_DIR/qmldir.orig" ]]; then
  install -m644 "$CANON_DIR/qmldir.orig" "$MILOU_DIR/qmldir"
  echo "==> restored qmldir (re-enables compiled QML)"
fi
[[ -f "$CANON_DIR/ResultDelegate.qml.orig" ]] || echo "==> no backup; 'pacman -S milou' will restore files" >&2

rm -f "$HOOK" && echo "==> removed pacman hook"

if [[ -n "${SUDO_USER:-}" ]]; then
  UID_OF=$(id -u "$SUDO_USER")
  rm -rf "$(getent passwd "$SUDO_USER" | cut -d: -f6)/.cache/krunner" 2>/dev/null || true
  sudo -u "$SUDO_USER" XDG_RUNTIME_DIR="/run/user/$UID_OF" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_OF/bus" \
    kquitapp6 krunner 2>/dev/null || true
fi

echo "DONE — reverted."
