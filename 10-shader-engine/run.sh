#!/usr/bin/env bash
# Nimbus Flux — launch the standalone GPU compute-shader fluid engine (Layer 10).
#
#   move / drag cursor : push the fluid and inject dye
#   1 / 2 / 3          : style — ink / mercury / water
#   D                  : toggle light / dark
#   Esc or close       : quit
#
# Env overrides (optional):
#   NIMBUS_FLUX_STYLE=0|1|2   start in a given style
#   NIMBUS_FLUX_DARK=0|1      start light/dark
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nimbus-flux"
export PATH="$HOME/.cargo/bin:$PATH"

# Prefer an optimised release binary; fall back to debug; build release if neither.
BIN="$DIR/target/release/nimbus-flux"
[[ -x "$BIN" ]] || BIN="$DIR/target/debug/nimbus-flux"
if [[ ! -x "$BIN" ]]; then
    echo "First run — building release (this takes a few minutes)…"
    (cd "$DIR" && cargo build --release)
    BIN="$DIR/target/release/nimbus-flux"
fi

# bevy resolves assets relative to the executable by default; point it at the
# crate so shaders/fluid.wgsl is found whether run from debug, release, or installed.
export BEVY_ASSET_ROOT="$DIR"
exec "$BIN" "$@"
