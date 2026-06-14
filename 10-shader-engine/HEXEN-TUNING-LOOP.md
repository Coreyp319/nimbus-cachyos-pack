# Hexen tuning loop — data-driven, no-compile, vision-judged refinement

The Layer-10 `hexen` wallpaper is refined by a **see-and-adjust loop** that a local vision
model (or a human) can run on an ongoing basis: change ONE knob → render → *look at the
PNG* → judge against the last-good baseline → keep or revert. The knobs are **externalized
to a JSON file the scene reads at startup**, so the loop **never compiles**, never breaks
the build, and never collides with the concurrent RT/DLSS source edits in `scene_hexen.rs`.

This is the small, working sibling of the dreaming-phase composer and `6-local-ai/ui-audit/`:
the model edits *validated data, never code*. Built as a **3-knob spike** (proven
2026-06-14); widen the knob surface once the loop is trusted.

## The pieces
| Piece | What it does |
|---|---|
| `scene_hexen.rs::HexenTuning` | Deserializes `NIMBUS_FLUX_HEXEN_TUNING` (a JSON path) at `setup()`. **Missing/invalid → the hardcoded defaults.** Every field is **clamp-bounded on load** — the renderer never trusts the file. Only **raster/shared** values are externalized; the `if rt {…}` lighting stays the DLSS session's. |
| `hexen-tune.py` | Guardrail manager: `set` (clamp+stage) · `capture` (run binary, save frame) · `accept` (promote tuning→last-good + capture→baseline + **ledger**) · `revert` (restore last-good) · `show`/`ledger`. |
| `hexen-vision-judge.py` | The **look** step: hands BEFORE+AFTER frames + the rubric to a local Ollama vision model (`gemma4-64k` / `qwen3.6-27b-64k`), returns a strict `{better,reason,artifacts,confidence}` verdict. Exit 0 = keep, 10 = revert. |
| `~/.nimbus/hexen-tune/` | State: `tuning.json` (live knobs the scene reads), `last-good.json` (revert target), `baseline.png` (comparison anchor), `captures/`, `ledger.jsonl`. Not in the repo — machine state, like `~/.hermes/ui-audit/`. |

## Knob surface (the 3-knob spike — ranges mirror the Rust clamps)
| Knob | Default | Safe range | Effect |
|---|---|---|---|
| `wall_roughness` | 0.7 | 0.5–0.95 | hero brick gloss; lower = wetter, reveals relief |
| `wall_depth` | 0.045 | 0.0–0.06 | hero brick parallax; **>0.06 smears** the stretched UV |
| `moonlight` | 850 | 400–1400 | cool key illuminance (raster); warm/cool contrast = depth |

The full knob table (floor/ceiling/torch/fog/props/…) is in `HEXEN-REFINEMENT-HANDOFF.md`.
To **widen**: add the field to `KNOBS` in `hexen-tune.py` **and** to `HexenTuning` (struct +
`Default` + clamped `load`) in `scene_hexen.rs`, then rebuild once. After that, tuning that
field is data-only again.

## One iteration (what the loop runs)
```bash
cd 10-shader-engine
# 0. (first time) establish the baseline at the current best:
./hexen-tune.py capture --label baseline && ./hexen-tune.py accept -m "baseline"

# 1. pick ONE goal + ONE knob + a small in-range delta:
./hexen-tune.py set moonlight=1150 -m "raise cool key to penetrate the interior"
# 2. render (NO compile — just re-reads the JSON):
./hexen-tune.py capture --label moon1150
# 3. the model looks and judges (before = baseline, after = the new capture):
./hexen-vision-judge.py --before ~/.nimbus/hexen-tune/baseline.png \
    --after ~/.nimbus/hexen-tune/captures/moon1150.png --goal "raised moonlight for depth"
# 4. keep or revert on the verdict:
./hexen-tune.py accept -m "<verdict>" --capture ~/.nimbus/hexen-tune/captures/moon1150.png
#   or, if not better:
./hexen-tune.py revert
```
`capture` parks a deterministic camera (`--cam`, default `0,2.2,23,0,0.4,9`) so before/after
differ ONLY by the knob; `--cam dolly` lets it glide; `--rt` previews the RT path; `--label`
names the frame. The launcher/loop always runs the **newest** of `target/{release,debug}`.

## Running it autonomously (the "ongoing basis" ask)
Wrap steps 1–4 in a driver that, per iteration: picks one goal from the rubric, picks one
knob + delta, runs the four commands, and branches on `hexen-vision-judge.py`'s exit code
(0 → `accept`, 10 → `revert`). The vision model is the judge; `gemma4-64k` and
`qwen3.6-27b-64k` are both vision-capable. A text-only model (Hermes) can drive the
*parameter search* but still needs a vision model (or a human) for the look.

**Guardrails (non-negotiable):** clamp every knob (enforced twice — script + renderer);
**one knob per iteration** (the judge must be able to attribute the change); **always
re-render before judging**; **verify the EFFECT, not the command** (exit 0 ≠ better);
revert on regression; **ledger every accept**; keep the last-good capture as the baseline;
**never edit the `if rt {…}` RT/DLSS branches**; **don't judge on the live wallpaper** (a
layer-shell surface can't be screenshotted — always capture windowed).

## Making an accepted tuning go live (the widen step — not yet wired)
Accepted knobs sit in `~/.nimbus/hexen-tune/tuning.json`. They affect a run **only when
`NIMBUS_FLUX_HEXEN_TUNING` points at that file** (the capture loop sets it; the default is
still the hardcoded values, by design). To make the **live wallpaper** honour them, set that
env in `~/.local/bin/nimbus-flux-wallpaper` before `setsid …`, and do a final `--release`
build so the optimized binary goes live. Kept env-gated on purpose so an in-progress tuning
never surprises the live desktop or the DLSS session.

## Status
- 2026-06-14: spike built + verified. Proved the data-driven path mechanically (two
  captures, two JSON values, **one binary, no rebuild** → different renders) and ran one
  full vision-judged iteration: `moonlight 850→1150` judged *better* (conf 0.95) by
  `gemma4-64k`, human-confirmed grounded, accepted + ledgered. The Rust externalization is
  applied/built on disk; left for a coordinated commit because `scene_hexen.rs` is the
  DLSS session's untracked file too.
