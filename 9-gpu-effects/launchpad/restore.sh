#!/usr/bin/env bash
# Revert Nimbus Launchpad: swap the dock's launcher back to whatever it replaced
# (saved by apply.sh, default org.kde.plasma.kickerdash), restoring its icon and
# left-most position. Pass --purge to also delete the installed plasmoid.
# Run as your normal user.
set -uo pipefail
PURGE="${1:-}"
PLUGIN_ID="com.nimbus.launchpad"
DEST="$HOME/.local/share/plasma/plasmoids/$PLUGIN_ID"
APPLETS_RC="plasma-org.kde.plasma.desktop-appletsrc"
STATE="$HOME/.cache/nimbus-gpu-effects/launchpad-prev"

ok(){   printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn(){ printf '  \033[33m!\033[0m %s\n' "$1"; }

command -v qdbus6 >/dev/null 2>&1 || { warn "qdbus6 not found — nothing to do."; exit 0; }

# what to restore (defaults if no saved state)
OLDTYPE="org.kde.plasma.kickerdash"; ICON="view-app-grid"
if [ -f "$STATE" ]; then
  OLDTYPE="$(sed -n 1p "$STATE")"; ICON="$(sed -n 2p "$STATE")"
  [ -n "$OLDTYPE" ] || OLDTYPE="org.kde.plasma.kickerdash"
  [ -n "$ICON" ] || ICON="view-app-grid"
fi

# swap ours -> the saved launcher, live. Reports: OK <panelId> <newId> <ids…>
SWAP="$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
var MINE = 'com.nimbus.launchpad';
var BACK = '$OLDTYPE';
var ICON = '$ICON';
var out = 'NONE';
var ps = panels();
for (var i=0;i<ps.length;i++){
  var p = ps[i];
  var ws = p.widgets();
  var li=-1;
  for (var j=0;j<ws.length;j++){ if (ws[j].type==MINE && li<0) li=j; }
  if (li<0) continue;
  ws[li].remove();
  var nw = p.addWidget(BACK);
  nw.currentConfigGroup = ['General'];
  nw.writeConfig('icon', ICON);
  var ids=[]; var w2=p.widgets(); for (var m=0;m<w2.length;m++) ids.push(w2[m].id);
  out = 'OK ' + p.id + ' ' + nw.id + ' ' + ids.join(',');
}
print(out);
" 2>/dev/null)"

set -- $SWAP
if [ "${1:-NONE}" = "OK" ]; then
  PANEL="$2"; NEWID="$3"; IDLIST="$4"
  ok "dock launcher restored: $PLUGIN_ID → $OLDTYPE"
  NEWORDER="$NEWID"
  IFS=',' read -ra _ids <<< "$IDLIST"
  for id in "${_ids[@]}"; do [ "$id" = "$NEWID" ] || NEWORDER="$NEWORDER;$id"; done
  # reload so the restored launcher takes its front position. Poll until
  # plasmashell is really gone before writing the order (see apply.sh — a fixed
  # sleep raced the restart).
  rm -rf "$HOME/.cache/plasmashell/qmlcache" 2>/dev/null
  if systemctl --user --quiet is-active plasma-plasmashell.service 2>/dev/null; then
    systemctl --user stop plasma-plasmashell.service 2>/dev/null
  else
    kquitapp6 plasmashell 2>/dev/null || killall plasmashell 2>/dev/null
  fi
  for _i in $(seq 1 25); do pgrep -x plasmashell >/dev/null 2>&1 || break; sleep 0.3; done
  pgrep -x plasmashell >/dev/null 2>&1 && { killall -9 plasmashell 2>/dev/null; sleep 1; }
  kwriteconfig6 --file "$APPLETS_RC" --group Containments --group "$PANEL" --group General --key AppletOrder "$NEWORDER"
  if systemctl --user --quiet is-enabled plasma-plasmashell.service 2>/dev/null; then
    systemctl --user start plasma-plasmashell.service 2>/dev/null
  else
    (kstart plasmashell >/dev/null 2>&1 &) || (setsid plasmashell >/dev/null 2>&1 &)
  fi
  ok "panel reloaded"
else
  ok "Launchpad wasn't on any panel — left the dock as-is"
fi

if [ "$PURGE" = "--purge" ]; then
  rm -rf "$DEST" "$STATE"
  ok "removed Launchpad plasmoid + saved state"
else
  echo "    Left the plasmoid installed (run with --purge to remove it)."
fi
