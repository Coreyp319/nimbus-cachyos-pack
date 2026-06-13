#!/usr/bin/env bash
# Show off the Apple-style notifications: a plain toast, an actionable one with
# buttons, and a sticky critical. Action clicks are printed to this terminal.
set -uo pipefail
command -v notify-send >/dev/null 2>&1 || { echo "notify-send not found (install libnotify)"; exit 1; }

echo ":: Sending a plain toast…"
notify-send -a "WhiteSur" "Good morning" "This is your macOS-style notification."
sleep 2

echo ":: Sending an actionable toast (click a button below)…"
# -A id=Label renders a styled pill button; notify-send prints the chosen id.
# --wait makes notify-send block and print the clicked action's id (else it
# returns immediately and prints nothing). Auto-closes after the popup timeout.
choice=$(notify-send --wait -a "Mail" -i mail-message \
  -A reply=Reply -A open=Open \
  "New message" "Anna: are we still on for lunch?")
[ -n "${choice:-}" ] && echo "   you clicked: $choice"
sleep 1

echo ":: Sending a critical (stays until dismissed)…"
notify-send -a "System" -u critical -i battery-caution \
  "Battery critically low" "Plug in your charger."

echo ":: Done. Toggle the notification center with Meta+N (or: swaync-client -t -sw)."
