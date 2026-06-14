#!/usr/bin/env bash
# Install + activate Nimbus Launchpad (Plasma 6): a full-screen Big Sur app
# launcher with a blur-and-zoom intro/outro. Reuses the installed kicker engine.
#
# Idempotent: copies the plasmoid into the user's plasmoids dir, then swaps the
# dock's app-launcher widget (org.kde.plasma.kickerdash) for com.nimbus.launchpad
# in place — preserving its icon and left-most position — and saves what it
# replaced so restore.sh can put it back. Run as your normal user.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ID="com.nimbus.launchpad"
SRC="$HERE/$PLUGIN_ID"
DEST="$HOME/.local/share/plasma/plasmoids/$PLUGIN_ID"
APPLETS_RC="plasma-org.kde.plasma.desktop-appletsrc"
STATE_DIR="$HOME/.cache/nimbus-gpu-effects"
STATE="$STATE_DIR/launchpad-prev"          # line1: replaced launcher plugin  line2: icon

ok(){   printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn(){ printf '  \033[33m!\033[0m %s\n' "$1"; }

command -v qdbus6 >/dev/null 2>&1 || { warn "qdbus6 not found — is this a Plasma 6 session?"; exit 1; }
[ -d "$SRC" ] || { warn "plugin source missing: $SRC"; exit 1; }

# 1. deploy the plasmoid (clean copy so removed files don't linger)
rm -rf "$DEST"; mkdir -p "$DEST"
cp -r "$SRC/metadata.json" "$SRC/contents" "$DEST/"
ok "plasmoid installed → $DEST"

# 2. swap the dock launcher live. Removes the old app-launcher widget, adds ours
#    with the same icon, and reports: OK <panelId> <newId> <oldType> <id,id,…>
SWAP="$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
var DESIRED = "com.nimbus.launchpad";
var OLDS = ["org.kde.plasma.kickerdash", "org.kde.plasma.kicker"];
function isOld(t){ for (var k=0;k<OLDS.length;k++) if (t==OLDS[k]) return true; return false; }
var out = "NONE";
var ps = panels();
for (var i=0;i<ps.length;i++){
  var p = ps[i];
  var ws = p.widgets();
  var li=-1, lt="", mine=false;
  for (var j=0;j<ws.length;j++){
    var t = ws[j].type;
    if (t==DESIRED) mine=true;
    else if (isOld(t) && li<0){ li=j; lt=t; }
  }
  if (mine){ out="ALREADY"; continue; }
  if (li<0) continue;
  var oldW = ws[li];
  oldW.currentConfigGroup = ["General"];
  var icon=""; try { icon = oldW.readConfig("icon"); } catch(e){}
  if (!icon) icon = "view-app-grid";
  oldW.remove();
  var nw = p.addWidget(DESIRED);
  nw.currentConfigGroup = ["General"];
  nw.writeConfig("icon", icon);
  var ids=[]; var w2=p.widgets(); for (var m=0;m<w2.length;m++) ids.push(w2[m].id);
  out = "OK " + p.id + " " + nw.id + " " + lt + " " + ids.join(",") + " " + icon;
}
print(out);
' 2>/dev/null)"

set -- $SWAP
STATUS="${1:-NONE}"
case "$STATUS" in
  ALREADY) ok "Launchpad is already the dock launcher (plugin refreshed)"; SWAPPED=0 ;;
  OK)
    PANEL="$2"; NEWID="$3"; OLDTYPE="$4"; IDLIST="$5"; ICON="${6:-view-app-grid}"
    mkdir -p "$STATE_DIR"; printf '%s\n%s\n' "$OLDTYPE" "$ICON" > "$STATE"
    ok "dock launcher swapped: $OLDTYPE → $PLUGIN_ID"
    SWAPPED=1
    # Move our widget to the front of the panel's applet order (addWidget appends
    # it to the far end). We have the live id list; rebuild it with NEWID first.
    NEWORDER="$NEWID"
    IFS=',' read -ra _ids <<< "$IDLIST"
    for id in "${_ids[@]}"; do [ "$id" = "$NEWID" ] || NEWORDER="$NEWORDER;$id"; done
    ;;
  *) warn "no app-launcher widget found on any panel — plugin installed but not"
     warn "placed. Add the 'Nimbus Launchpad' widget to a panel yourself, or run"
     warn "Layer 1 (which pins it) after this."; SWAPPED=0 ;;
esac

# 3. apply the new order cleanly. Order changes need a plasmashell reload to take
#    effect, so: stop (flushes the live swap to disk) → write order → start.
if [ "${SWAPPED:-0}" = 1 ]; then
  # Clear the plasmoid QML cache so updated launcher QML is recompiled, not
  # served stale.
  rm -rf "$HOME/.cache/plasmashell/qmlcache" 2>/dev/null
  # Take plasmashell fully down, then write the order, then bring it back — so it
  # reads the new order on start. plasmashell isn't always a systemd service
  # here, so we POLL until the process is really gone: a fixed `sleep` raced
  # (the restart read the old order before our write landed).
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
  ok "panel reloaded — Launchpad placed at the front of the dock"
fi

echo
ok "Done. Click the app-grid icon (or it's there after the next login)."
echo "    Tune it: System Settings → click the launcher's widget settings, or"
echo "    right-click the dock icon → Configure (columns, icon size, motion)."
echo "    Revert just this:  bash 9-gpu-effects/launchpad/restore.sh --purge"
