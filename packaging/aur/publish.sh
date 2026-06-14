#!/usr/bin/env bash
# packaging/aur/publish.sh — prepare a pack PKGBUILD for the AUR, right up to the
# push. Everything here is local and needs NO credentials: it pulls the canonical
# PKGBUILD, regenerates a fresh .SRCINFO, and stages both in a clone of the AUR
# repo with a commit ready. The final `git push` — which needs YOUR AUR SSH key —
# it prints for you to run.
#
#   bash packaging/aur/publish.sh kiview-git
#
# First-time AUR setup: create an account at https://aur.archlinux.org, add your
# SSH public key there, and confirm `ssh aur@aur.archlinux.org` authenticates.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

# package -> canonical PKGBUILD path within the repo. Add a line to publish more.
src_for(){ case "$1" in
  kiview-git) echo "8-dolphin-quicklook/PKGBUILD" ;;
  *)          return 1 ;;
esac; }
KNOWN="kiview-git"

PKG="${1:-}"
if [ -z "$PKG" ]; then echo "usage: bash publish.sh <pkgname>"; echo "known packages: $KNOWN"; exit 1; fi
SRC_REL="$(src_for "$PKG")" || { echo "unknown package '$PKG' (known: $KNOWN)"; exit 1; }
SRC="$ROOT/$SRC_REL"
[ -f "$SRC" ] || { echo "PKGBUILD not found: $SRC"; exit 1; }
command -v makepkg >/dev/null 2>&1 || { echo "makepkg not found — install base-devel"; exit 1; }

WORK="${XDG_CACHE_HOME:-$HOME/.cache}/nimbus-aur/$PKG"
echo ":: preparing $PKG  (source: $SRC_REL)"
rm -rf "$WORK"; mkdir -p "$WORK"

# Clone the existing AUR repo, or init a fresh one if the package is new.
# Read-only HTTPS clone (no auth). AUR serves an EMPTY repo for any name, so an
# existing package is distinguished by an actual PKGBUILD, not by the .git dir.
if git clone -q "https://aur.archlinux.org/$PKG.git" "$WORK" 2>/dev/null && [ -f "$WORK/PKGBUILD" ]; then
  echo "   cloned existing AUR repo (updating)"
else
  rm -rf "$WORK"; mkdir -p "$WORK"; ( cd "$WORK" && git init -q -b master )
  echo "   new package — initialised a fresh repo"
fi

cp "$SRC" "$WORK/PKGBUILD"
( cd "$WORK" && makepkg --printsrcinfo > .SRCINFO )
ver="$(awk -F' = ' '/pkgver =/{print $2; exit}' "$WORK/.SRCINFO")"
echo "   PKGBUILD + .SRCINFO ready (pkgver $ver)"

( cd "$WORK"
  git add PKGBUILD .SRCINFO
  git -c user.name="$(git -C "$ROOT" config user.name)" \
      -c user.email="$(git -C "$ROOT" config user.email)" \
      commit -q -m "Update $PKG to $ver" 2>/dev/null || echo "   (no change — already current)"
  # AUR push is SSH-only (an HTTPS clone leaves an https origin that can't push).
  git remote remove origin 2>/dev/null || true
  git remote add origin "ssh://aur@aur.archlinux.org/$PKG.git"
)

cat <<EOF

  Prepared — everything but the push (which needs your AUR SSH key).
    review:   git -C "$WORK" show
    publish:  git -C "$WORK" push -u origin master

  Note: this stages pkgver=$ver. For a -git package the real version is
  recomputed at build; to bake the exact current upstream version, run
  'makepkg -o' in $WORK first, then re-run this script.
EOF
