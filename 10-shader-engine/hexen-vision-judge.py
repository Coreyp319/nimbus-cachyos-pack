#!/usr/bin/env python3
"""The *look* step of the hexen refinement loop, run by a LOCAL vision model.

Two Layer-6 locals are vision-capable (`gemma4-64k`, `qwen3.6-27b-64k`), so the
see-and-adjust loop can run on an ongoing basis with no human and no cloud: this script
hands a vision model the BEFORE (last-good baseline) and AFTER (the just-captured) frames
plus the aesthetic rubric, and asks for a strict verdict — better or worse, and why. The
caller (`hexen-tune.py accept` / `revert`) acts on the verdict.

It talks to Ollama's /api/chat with both frames as base64 images in one user turn, so the
model compares them directly. Output is parsed tolerantly (small models wrap JSON in
prose) into: {"better", "reason", "artifacts", "confidence"}.

Usage:
    hexen-vision-judge.py --before BASE.png --after NEW.png --goal "raised moonlight" \
        [--model gemma4-64k:latest]

Exit code 0 = "better" (keep), 10 = "not better" (revert), 1 = call/parse failed.
The verdict JSON is printed to stdout regardless.
"""
from __future__ import annotations

import argparse
import base64
import json
import re
import sys
import urllib.request

OLLAMA = "http://localhost:11434/api/chat"

# The rubric is spelled out because a model can't intuit "better" — lifted verbatim from
# HEXEN-REFINEMENT-HANDOFF.md so the judge and the human share one definition of done.
RUBRIC = """\
You are judging two renders of a torch-lit gothic-dungeon corridor wallpaper (Hexen/Heretic
mood). The FIRST image is the BEFORE (current best). The SECOND image is the AFTER (a
candidate with ONE lighting/material knob changed). Decide whether AFTER is BETTER than
BEFORE against this rubric:

- Depth/contrast: warm torch pools against cool shadow; a real dark<->bright range; never
  one flat hue/wash.
- Material richness: brick/stone relief visible (grazing speculars + parallax), not matte-flat.
- Composition: the hall leads to the focal shrine at the far end; foreground dressed, props
  hug the walls.
- Mood/legibility: torch-lit gothic; fog atmospheric but not curtaining; the far end melts
  to dark.
- No artifacts: no texture smear/swim, no blown-out bloom, no washed-out flat lighting, no
  crushed-to-black loss of detail.

The change is a SMALL single-knob delta, so judge honestly: if AFTER looks the same or
worse, say so. Prefer the option with richer depth and material read.

Respond with ONLY a JSON object, no prose:
{"better": true|false, "reason": "<one sentence>", "artifacts": "<any new artifacts, or 'none'>", "confidence": 0.0-1.0}
"""


def b64(path: str) -> str:
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")


def parse_verdict(text: str) -> dict | None:
    """Tolerant JSON extraction — small models wrap the object in prose/fences."""
    for candidate in (text, *re.findall(r"\{.*?\}", text, re.DOTALL)):
        try:
            obj = json.loads(candidate)
            if isinstance(obj, dict) and "better" in obj:
                return obj
        except Exception:
            continue
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--before", required=True, help="baseline PNG (current best)")
    ap.add_argument("--after", required=True, help="candidate PNG (just captured)")
    ap.add_argument("--goal", default="", help="what knob changed and why (context for the model)")
    ap.add_argument("--model", default="gemma4-64k:latest", help="Ollama vision model tag")
    ap.add_argument("--timeout", type=int, default=300)
    args = ap.parse_args()

    prompt = RUBRIC
    if args.goal:
        prompt += f"\n\nContext — the operator's intent for this change: {args.goal}\n"

    body = {
        "model": args.model,
        "messages": [{"role": "user", "content": prompt,
                      "images": [b64(args.before), b64(args.after)]}],
        "stream": False,
        "options": {"temperature": 0.2},
    }
    req = urllib.request.Request(OLLAMA, data=json.dumps(body).encode("utf-8"),
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=args.timeout) as r:
            resp = json.loads(r.read().decode("utf-8"))
    except Exception as e:
        print(json.dumps({"error": f"ollama call failed: {e}", "model": args.model}))
        return 1

    content = (resp.get("message", {}) or {}).get("content", "")
    verdict = parse_verdict(content)
    if verdict is None:
        print(json.dumps({"error": "could not parse a verdict", "model": args.model,
                          "raw": content[:800]}))
        return 1

    verdict["model"] = args.model
    print(json.dumps(verdict, indent=2))
    return 0 if verdict.get("better") is True else 10


if __name__ == "__main__":
    raise SystemExit(main())
