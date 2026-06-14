#!/usr/bin/env python3
"""Guardrailed tuning manager for the Layer-10 `hexen` wallpaper refinement loop.

The renderer reads its refinement knobs from a JSON file (named by
`NIMBUS_FLUX_HEXEN_TUNING`) at startup — so a tuning model (or a human) edits
**validated data, never code**: the see-and-adjust loop never compiles, never breaks the
build, and never collides with the concurrent RT/DLSS source edits. This tool is the
guardrail layer around that file — the small sibling of `6-local-ai/ui-audit/`:

  * CLAMPED      every knob is clamped to a safe range (mirroring the Rust
                 `HexenTuning::load` clamps; the renderer re-clamps independently, so this
                 is a fast reject + convenience, never the only guard).
  * ONE AT A TIME `set` stages a proposal into tuning.json; nothing is recorded until you
                 ACCEPT. The loop is: set ONE knob -> capture -> judge -> accept|revert.
  * REVERSIBLE   `revert` restores last-good.json; `accept` promotes the staged tuning to
                 last-good AND the capture to baseline.png (the vision comparison anchor).
  * LEDGERED     every accept appends to ledger.jsonl (before/after/rationale/capture), so
                 the journey is auditable and the last-good is always recoverable.

State lives under ~/.nimbus/hexen-tune/:
    tuning.json      the live knobs the scene reads (mutated by `set`/`revert`)
    last-good.json   the last accepted knobs (revert target + ledger `before`)
    baseline.png     the last accepted capture (vision comparison baseline)
    captures/        every capture, timestamped
    ledger.jsonl     append-only record of accepted changes

Commands:
    show                              current vs last-good knobs + ledger tail
    set K=V [K=V ...] -m "why"        clamp + write to tuning.json (stages; no ledger)
    capture [--cam C] [--label L]     run the binary, save the frame, print its path
    accept -m "why" [--capture P]     promote tuning->last-good + capture->baseline + ledger
    revert                            restore last-good.json -> tuning.json (drop the stage)
    ledger                            print the full ledger

This is a 3-knob spike (see HEXEN-REFINEMENT-HANDOFF.md): prove the data-driven,
no-compile, vision-judged loop, then widen KNOBS to the full surface.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
STATE = HOME / ".nimbus" / "hexen-tune"
TUNING = STATE / "tuning.json"
LASTGOOD = STATE / "last-good.json"
BASELINE = STATE / "baseline.png"
CAPTURES = STATE / "captures"
LEDGER = STATE / "ledger.jsonl"
FRAME = Path("/tmp/nimbus-flux-frame.png")  # where capture-mode writes

# Repo layout: this script sits in 10-shader-engine/; the crate is ./nimbus-flux.
CRATE = Path(__file__).resolve().parent / "nimbus-flux"

# Deterministic comparison framing: a parked camera so before/after differ ONLY by the
# knob. (Handoff's recommended park; override with --cam, or --cam dolly to let it glide.)
DEFAULT_CAM = "0,2.2,23,0,0.4,9"

# Knob -> (lo, hi, default). Ranges MIRROR scene_hexen.rs::HexenTuning::load. Widen this
# table (and the Rust struct) together when graduating past the spike.
KNOBS = {
    "wall_roughness": (0.5, 0.95, 0.7),    # hero brick gloss; lower = wetter, reveals relief
    "wall_depth":     (0.0, 0.06, 0.045),  # hero brick parallax; >0.06 smears the stretched UV
    "moonlight":      (400.0, 1400.0, 850.0),  # cool key illuminance (raster); warm/cool = depth
}


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")


def defaults() -> dict:
    return {k: d for k, (_lo, _hi, d) in KNOBS.items()}


def clamp(name: str, value: float) -> float:
    lo, hi, _ = KNOBS[name]
    return max(lo, min(hi, value))


def load_json(path: Path, fallback: dict) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return dict(fallback)


def save_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def ensure_state() -> None:
    STATE.mkdir(parents=True, exist_ok=True)
    CAPTURES.mkdir(parents=True, exist_ok=True)
    # Seed last-good + live tuning from the hardcoded defaults on first run, so `revert`
    # always has a target and the first `accept` records before == the baseline values.
    if not LASTGOOD.exists():
        save_json(LASTGOOD, defaults())
    if not TUNING.exists():
        save_json(TUNING, load_json(LASTGOOD, defaults()))


def current() -> dict:
    return load_json(TUNING, defaults())


def lastgood() -> dict:
    return load_json(LASTGOOD, defaults())


def fmt(d: dict) -> str:
    return "  ".join(f"{k}={d.get(k)}" for k in KNOBS)


def diff(a: dict, b: dict) -> list[str]:
    out = []
    for k in KNOBS:
        if a.get(k) != b.get(k):
            out.append(f"{k}: {a.get(k)} -> {b.get(k)}")
    return out


# ---------------------------------------------------------------------------

def cmd_show(args) -> int:
    cur, lg = current(), lastgood()
    print(f"state dir : {STATE}")
    print(f"current   : {fmt(cur)}")
    print(f"last-good : {fmt(lg)}")
    d = diff(lg, cur)
    print("staged    : " + ("; ".join(d) if d else "(none — current == last-good)"))
    print(f"baseline  : {BASELINE if BASELINE.exists() else '(none yet)'}")
    recs = read_ledger()
    print(f"\nledger ({len(recs)} accepted change(s)):")
    for r in recs[-5:]:
        print(f"  {r.get('ts')}  {';'.join(r.get('changes', [])) or '(no knob delta)'}"
              f"  — {r.get('rationale','')}")
    return 0


def cmd_set(args) -> int:
    cur = current()
    changed = []
    for assign in args.assignments:
        if "=" not in assign:
            print(f"error: '{assign}' is not K=V", file=sys.stderr)
            return 2
        name, raw = assign.split("=", 1)
        name = name.strip()
        if name not in KNOBS:
            print(f"error: unknown knob '{name}'. known: {', '.join(KNOBS)}", file=sys.stderr)
            return 2
        try:
            val = float(raw)
        except ValueError:
            print(f"error: {name}={raw!r} is not a number", file=sys.stderr)
            return 2
        clamped = clamp(name, val)
        if clamped != val:
            lo, hi, _ = KNOBS[name]
            print(f"note: {name} {val} clamped to {clamped} (range {lo}..{hi})")
        cur[name] = clamped
        changed.append(f"{name}={clamped}")
    save_json(TUNING, cur)
    print(f"staged: {', '.join(changed)}")
    d = diff(lastgood(), cur)
    print("vs last-good: " + ("; ".join(d) if d else "(no net change)"))
    if len(d) > 1:
        print("WARNING: more than one knob differs from last-good — the loop expects ONE "
              "knob per iteration so the judge can attribute the change.", file=sys.stderr)
    return 0


def find_binary() -> Path | None:
    rel = CRATE / "target" / "release" / "nimbus-flux"
    dbg = CRATE / "target" / "debug" / "nimbus-flux"
    cands = [p for p in (rel, dbg) if p.is_file() and os.access(p, os.X_OK)]
    if not cands:
        return None
    # Newest wins — never let a stale release shadow a fresh debug build (handoff gotcha).
    return max(cands, key=lambda p: p.stat().st_mtime)


def cmd_capture(args) -> int:
    binary = find_binary()
    if binary is None:
        print(f"error: no nimbus-flux binary under {CRATE}/target/{{release,debug}}; "
              f"build it first (cargo build)", file=sys.stderr)
        return 1
    env = dict(os.environ)
    env["BEVY_ASSET_ROOT"] = str(CRATE)
    env["NIMBUS_FLUX_CAPTURE"] = "1"
    env["NIMBUS_FLUX_SCENE"] = "hexen"
    env["NIMBUS_FLUX_HEXEN_TUNING"] = str(TUNING)
    cam = args.cam if args.cam else DEFAULT_CAM
    if cam.lower() != "dolly":
        env["NIMBUS_FLUX_HEXEN_TUNING"] = str(TUNING)
        env["NIMBUS_FLUX_HEXEN_CAM"] = cam
    else:
        env.pop("NIMBUS_FLUX_HEXEN_CAM", None)
    if args.rt:
        env["NIMBUS_FLUX_RT"] = "1"  # opt-in RT preview; default is the raster path we tune

    FRAME.unlink(missing_ok=True)
    print(f"capture: {binary.name} (mtime {datetime.fromtimestamp(binary.stat().st_mtime)}) "
          f"cam={cam} tuning={fmt(current())}")
    try:
        p = subprocess.run([str(binary)], env=env, cwd=str(CRATE),
                           capture_output=True, text=True, timeout=args.timeout)
    except subprocess.TimeoutExpired:
        print("error: capture timed out (the window app didn't exit). Is a Wayland/X "
              "display reachable?", file=sys.stderr)
        return 1
    # Surface the tuning-load line so the operator can confirm the knobs took effect.
    for line in (p.stdout + p.stderr).splitlines():
        if "hexen tuning" in line or "panic" in line.lower():
            print("  " + line.split("scene_hexen:")[-1].strip())
    if not FRAME.exists():
        print("error: no frame written to /tmp/nimbus-flux-frame.png — capture failed.",
              file=sys.stderr)
        sys.stderr.write("\n".join((p.stdout + p.stderr).splitlines()[-15:]) + "\n")
        return 1
    label = args.label or f"iter-{stamp()}"
    dst = CAPTURES / f"{label}.png"
    shutil.copy2(FRAME, dst)
    print(f"saved: {dst}")
    if BASELINE.exists():
        print(f"baseline for comparison: {BASELINE}")
    return 0


def latest_capture() -> Path | None:
    pngs = sorted(CAPTURES.glob("*.png"), key=lambda p: p.stat().st_mtime)
    return pngs[-1] if pngs else (FRAME if FRAME.exists() else None)


def cmd_accept(args) -> int:
    cur = current()
    prev = lastgood()
    changes = diff(prev, cur)
    cap = Path(args.capture) if args.capture else latest_capture()
    if cap is None or not cap.exists():
        print("error: no capture to promote to baseline (run `capture` first, or pass "
              "--capture PATH)", file=sys.stderr)
        return 1
    # Promote: tuning -> last-good, capture -> baseline.
    save_json(LASTGOOD, cur)
    shutil.copy2(cap, BASELINE)
    rec = {
        "ts": now(), "action": "accept",
        "before": prev, "after": cur, "changes": changes,
        "rationale": args.message or "",
        "capture": str(cap), "baseline": str(BASELINE),
    }
    LEDGER.parent.mkdir(parents=True, exist_ok=True)
    with LEDGER.open("a", encoding="utf-8") as f:
        f.write(json.dumps(rec) + "\n")
    print(f"accepted: {'; '.join(changes) if changes else '(no knob delta — baseline refresh)'}")
    print(f"  new last-good: {fmt(cur)}")
    print(f"  new baseline : {BASELINE}  (from {cap})")
    print(f"  ledgered     : {LEDGER}")
    return 0


def cmd_revert(args) -> int:
    lg = lastgood()
    cur = current()
    changes = diff(cur, lg)
    save_json(TUNING, lg)
    print(f"reverted tuning.json -> last-good: {fmt(lg)}")
    print("undone: " + ("; ".join(changes) if changes else "(nothing was staged)"))
    return 0


def read_ledger() -> list[dict]:
    recs = []
    if LEDGER.exists():
        for line in LEDGER.read_text(encoding="utf-8").splitlines():
            try:
                recs.append(json.loads(line))
            except Exception:
                continue
    return recs


def cmd_ledger(args) -> int:
    recs = read_ledger()
    if not recs:
        print("(ledger empty — no accepted changes yet)")
        return 0
    for r in recs:
        print(f"{r.get('ts')}  {'; '.join(r.get('changes', [])) or '(no knob delta)'}")
        print(f"    rationale: {r.get('rationale','')}")
        print(f"    capture:   {r.get('capture','')}")
    return 0


def main() -> int:
    ensure_state()
    ap = argparse.ArgumentParser(description="Guardrailed hexen tuning loop manager.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("show", help="current vs last-good knobs + ledger tail")

    s = sub.add_parser("set", help="clamp + stage knob value(s) into tuning.json")
    s.add_argument("assignments", nargs="+", metavar="K=V")
    s.add_argument("-m", "--message", default="", help="rationale (recorded on accept)")

    c = sub.add_parser("capture", help="run the binary and save a frame")
    c.add_argument("--cam", default="", help=f"camera park x,y,z,lx,ly,lz (default {DEFAULT_CAM}; "
                   "'dolly' = let it glide)")
    c.add_argument("--label", default="", help="capture filename stem (default iter-<ts>)")
    c.add_argument("--rt", action="store_true", help="preview the RT path (default: raster)")
    c.add_argument("--timeout", type=int, default=40, help="seconds before giving up")

    a = sub.add_parser("accept", help="promote staged tuning + capture, ledger it")
    a.add_argument("-m", "--message", default="", help="rationale for the accepted change")
    a.add_argument("--capture", default="", help="capture PNG to promote (default: newest)")

    sub.add_parser("revert", help="restore last-good.json -> tuning.json")
    sub.add_parser("ledger", help="print the full accept ledger")

    args = ap.parse_args()
    return {
        "show": cmd_show, "set": cmd_set, "capture": cmd_capture,
        "accept": cmd_accept, "revert": cmd_revert, "ledger": cmd_ledger,
    }[args.cmd](args)


if __name__ == "__main__":
    raise SystemExit(main())
