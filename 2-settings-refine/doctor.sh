#!/usr/bin/env bash
# Layer 2 drift check — NimbusRefined Kvantum theme + section-icon watcher.
set -uo pipefail
SELF="$(cd "$(dirname "$0")" && pwd)"; . "$SELF/../lib/doctor-lib.sh"

HELPER="$HOME/.local/bin/nimbus-refine-icons"
gate "refine-icons helper absent" test -e "$HELPER"

# Kvantum's config lives in the Kvantum/ subdir, not ~/.config — use the absolute
# path (a bare --file kvantum.kvconfig reads a stale top-level ~/.config leftover).
theme=$(kreadconfig6 --file "$HOME/.config/Kvantum/kvantum.kvconfig" --group General --key theme 2>/dev/null || true)
case "$theme" in NimbusRefined*) theme_ok=0 ;; *) theme_ok=1 ;; esac

check "Kvantum theme is NimbusRefined* (got: ${theme:-unset})" [ "$theme_ok" = 0 ]
check "section-icon watcher enabled"           [ "$(systemctl --user is-enabled nimbus-refine-icons.path 2>/dev/null)" = enabled ]
check "refine-icons helper executable"         [ -x "$HELPER" ]

doctor_done
