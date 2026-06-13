#!/usr/bin/env python3
"""Deterministic UI-state collector for the daily KDE Plasma audit.

NO LLM runs here. This script reads the real config and emits a state.json that
the agent reasons over. The whole point is anti-confabulation: the model may
only report values that appear in this file. Every key carries `present` so the
model can say "unset" instead of inventing a value (the failure mode that
produced a fake Font and a fake FrameContrast in the first sample run).

It also computes WCAG contrast ratios for the active colour scheme using the
exact math in references/color-theory-accessibility.md, so contrast findings are
grounded numbers, not vibes.

Usage:
    ui-audit-collect.py [--out PATH]

Output: writes state.json (default ~/.hermes/ui-audit/state/state.json) and
prints its path on stdout.
"""
from __future__ import annotations

import argparse
import configparser
import json
import os
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
RUNTIME = HOME / ".hermes" / "ui-audit"
DEFAULT_OUT = RUNTIME / "state" / "state.json"

# ---------------------------------------------------------------------------
# Raw config reads (kreadconfig6) — each returns (value, present)
# ---------------------------------------------------------------------------

def kread(file: str, group: str, key: str):
    try:
        r = subprocess.run(
            ["kreadconfig6", "--file", file, "--group", group, "--key", key],
            capture_output=True, text=True, timeout=10,
        )
        val = r.stdout.rstrip("\n")
        return (val, True) if val != "" else (None, False)
    except Exception:
        return (None, False)


# (file, group, key) entries to snapshot verbatim. Sources are explicit so the
# model can cite them and never has to guess where a value lives.
RAW_KEYS = [
    ("kdeglobals", "General", "ColorScheme"),
    ("kdeglobals", "KDE", "ColorScheme"),          # legacy/dead key — flagged if present
    ("kdeglobals", "KDE", "LookAndFeelPackage"),
    ("kdeglobals", "KDE", "widgetStyle"),
    ("kdeglobals", "KDE", "contrast"),
    ("kdeglobals", "General", "AnimationDurationFactor"),
    ("kdeglobals", "KDE", "AnimationDurationFactor"),
    ("kdeglobals", "General", "Font"),
    ("kdeglobals", "General", "menuFont"),
    ("kdeglobals", "General", "toolBarFont"),
    ("kdeglobals", "General", "smallestReadableFont"),
    ("kdeglobals", "General", "fixed"),
    ("kdeglobals", "WM", "activeFont"),
    ("kdeglobals", "Icons", "Theme"),
    ("kwinrc", "Plugins", "blurEnabled"),
    ("kwinrc", "Plugins", "contrastEnabled"),
    ("kwinrc", "org.kde.kdecoration2", "theme"),
]


def collect_raw():
    out = {}
    for file, group, key in RAW_KEYS:
        val, present = kread(file, group, key)
        out[f"{file}:{group}:{key}"] = {
            "file": file, "group": group, "key": key,
            "value": val, "present": present,
        }
    # Kvantum widget theme lives in the capital-K dir (a lowercase path is the
    # classic false-"no theme" bug — see references/color-role-cheatsheet.md).
    kv = HOME / ".config" / "Kvantum" / "kvantum.kvconfig"
    if kv.exists():
        cp = configparser.ConfigParser(strict=False)
        cp.read(kv)
        theme = cp.get("General", "theme", fallback=None)
        out["Kvantum:General:theme"] = {
            "file": str(kv), "group": "General", "key": "theme",
            "value": theme, "present": theme is not None,
        }
    else:
        out["Kvantum:General:theme"] = {
            "file": str(kv), "group": "General", "key": "theme",
            "value": None, "present": False,
        }
    return out


# ---------------------------------------------------------------------------
# WCAG contrast — math mirrors references/color-theory-accessibility.md §1
# ---------------------------------------------------------------------------

def _lin(c: float) -> float:
    # WCAG 2.x linearization; 0.04045 is the currently-published threshold
    # (pre-2021 was 0.03928 — no practical difference).
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(rgb) -> float:
    r, g, b = (_lin(x / 255.0) for x in rgb[:3])
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(rgb1, rgb2) -> float:
    l1, l2 = luminance(rgb1), luminance(rgb2)
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def parse_rgb(val: str):
    try:
        parts = [int(x) for x in val.split(",")]
        if len(parts) >= 3:
            return tuple(parts[:3])
    except Exception:
        pass
    return None


# Foreground (text) roles checked against their section's BackgroundNormal.
# DecorationFocus/Hover are deliberately EXCLUDED: the focus ring renders over
# varied surfaces (not just this role's own background), so a fixed 3:1 pairing
# here is a false positive. Focus-ring contrast is not auto-audited.
FG_KEYS = {
    "ForegroundNormal": 4.5, "ForegroundInactive": 4.5, "ForegroundActive": 4.5,
    "ForegroundLink": 4.5, "ForegroundVisited": 4.5, "ForegroundNegative": 4.5,
    "ForegroundNeutral": 4.5, "ForegroundPositive": 4.5,
}


def find_scheme_file(scheme: str):
    if not scheme:
        return None
    for base in (HOME / ".local/share/color-schemes",
                 Path("/usr/share/color-schemes")):
        p = base / f"{scheme}.colors"
        if p.exists():
            return p
    return None


def collect_contrast(scheme: str):
    path = find_scheme_file(scheme)
    result = {"scheme": scheme, "scheme_file": str(path) if path else None,
              "pairings": [], "failures": 0}
    if not path:
        result["error"] = "active colour-scheme .colors file not found"
        return result
    cp = configparser.ConfigParser(strict=False)
    cp.read(path)
    for section in cp.sections():
        if not section.startswith("Colors:"):
            continue
        bg = cp.get(section, "BackgroundNormal", fallback=None)
        bg_rgb = parse_rgb(bg) if bg else None
        if not bg_rgb:
            continue
        for fg_key, need in FG_KEYS.items():
            fg = cp.get(section, fg_key, fallback=None)
            fg_rgb = parse_rgb(fg) if fg else None
            if not fg_rgb:
                continue
            ratio = round(contrast(fg_rgb, bg_rgb), 2)
            is_decoration = fg_key.startswith("Decoration")
            ok = ratio >= need
            if not ok:
                result["failures"] += 1
            result["pairings"].append({
                "role": section, "fg_key": fg_key,
                "fg": ",".join(map(str, fg_rgb)), "bg": ",".join(map(str, bg_rgb)),
                "ratio": ratio, "need": need,
                "kind": "non-text" if is_decoration else "body-text",
                "pass": ok,
                "aa_normal": ratio >= 4.5, "aa_large": ratio >= 3.0,
                "aaa_normal": ratio >= 7.0,
            })
    return result


# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    args = ap.parse_args()

    raw = collect_raw()
    scheme = raw.get("kdeglobals:General:ColorScheme", {}).get("value")
    contrast_block = collect_contrast(scheme)

    # Cheap structural smells the model would otherwise miss / hallucinate.
    smells = []
    legacy_cs = raw.get("kdeglobals:KDE:ColorScheme", {})
    canon_cs = raw.get("kdeglobals:General:ColorScheme", {})
    if legacy_cs.get("present") and canon_cs.get("present") and \
            legacy_cs.get("value") != canon_cs.get("value"):
        smells.append({
            "class": "duplicate-colorscheme-key",
            "detail": f"[General]ColorScheme={canon_cs['value']} wins; dead "
                      f"[KDE]ColorScheme={legacy_cs['value']} disagrees",
        })

    state = {
        "meta": {
            "collected_at": datetime.now(timezone.utc).isoformat(),
            "host": os.uname().nodename,
            "collector": "ui-audit-collect.py",
            "active_scheme": scheme,
        },
        "raw": raw,
        "contrast": contrast_block,
        "structural_smells": smells,
    }

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    # Rotate the prior snapshot so the applier can diff "changed since last run".
    if out.exists():
        shutil.copy2(out, out.parent / "state.prev.json")
    tmp = out.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(state, indent=2), encoding="utf-8")
    os.replace(tmp, out)
    print(str(out))


if __name__ == "__main__":
    main()
