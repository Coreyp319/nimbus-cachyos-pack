# Hermes-driven Blender forge — design & scope

**Status:** scoped, Phase-0 spike done (2026-06-13). Not yet implemented.
**Owner:** Corey. **Depends on:** the gpu-effects forge (`blender-mcp.sh`, `NIMBUS_BLENDER_PORT`)
and Layer 6 Ollama stack (`:11434`, `hermes4-14b` / `hermes4.3-36b`).

> **Phase-0 verdict — GREEN.** Both Hermes models emit **structured `tool_calls`**
> through Ollama's native tools API (`/api/chat`, `stream:false`, `tools:[…]`), with
> correct arguments, and both produced **two tool calls in one turn**. So the central
> unknown ("can a local Hermes do MCP-style tool calling at all?") is resolved with
> **no Modelfile `TEMPLATE` work required.** The remaining work is engineering.

## 1. Goal
Let the **local Hermes model autonomously author/edit a hero asset** by calling the
same `blender` MCP tools the Claude forge uses, on its own lane, with no Claude in the
loop. Cost-free, offline, unattended. The Blender side needs **zero changes** —
`blender-mcp.sh up` + `NIMBUS_BLENDER_PORT` already give Hermes a private lane.

## 2. Phase-0 spike (done)
Script: tools API probe against `:11434` with a Blender-flavored schema
(`add_primitive`, `get_scene_info`) and a prompt that forces a call.
Result: `hermes4-14b` PASS (31.2s cold), `hermes4.3-36b` PASS (22.2s). Both returned
`message.tool_calls` structured + parallel. → Use the **14B** tier (lighter VRAM).

## 3. Architecture — the harness
```
                         ┌────────────────────────────────────────────┐
 distilled prompt + task │  hermes-forge.py                            │
  ──────────────────────▶│  1. MCP client → spawn `uvx blender-mcp`    │──stdio──▶ blender-mcp ──:$PORT──▶ Blender (lane)
                         │     (env BLENDER_PORT=$NIMBUS_BLENDER_PORT)  │
   Ollama /api/chat ◀────│  2. list tools → translate to tools schema  │
  (hermes4-14b) ────────▶│  3. loop: Hermes → tool_call → exec via MCP  │
                         │           → feed result back → repeat         │
                         │  4. on render/export: harness auto-verifies  │──Read PNG/GLB, assert >0 bytes──▶ back into loop
                         │  5. GPU policy: unload model during render    │
                         └────────────────────────────────────────────┘
```

## 4. Build options
| | A — bridge (mcphost/Kit) | **B — Python harness (recommended)** |
|---|---|---|
| What | `mcphost` Go CLI (Ollama↔MCP) or successor **Kit** | ~250-line Python: `mcp` SDK client + Ollama tools loop |
| MVP speed | fast | moderate |
| Repo fit | foreign Go binary; **mcphost unmaintained** (Kit is successor) | Python like the rest; idiomatic install/revert/doctor |
| Control over verify-by-file / GPU unload / code-safety | limited | **full** — these are the parts that matter here |

Recommend **B**. (The spike already validated the bridge concept, so an A spike is no
longer needed.)

## 5. Repo layout & work items
Lives Layer-6-side (a local-AI capability), reusing the gpu-effects forge for the
Blender half. **Kept out of `nimbus.layers`' install path** — authoring tooling, never
shipped in the skin.
```
6-local-ai/hermes-forge/
  DESIGN.md          # this file
  hermes-forge.py    # harness: MCP client + Ollama loop + verify + GPU policy
  forge-prompt.md    # distilled system prompt: blender-pipeline.md §0 + golden rules, ~1–2 KB
  install.sh / revert.sh
  doctor.sh          # ollama up? model pulled? tool-calling works? lane reachable?
```
- **Reuse:** `.claude/skills/gpu-effects/blender-mcp.sh` for the lane; `NIMBUS_BLENDER_PORT`
  routing; the `:11434` endpoint; the Claude reference doc as the *source* for the
  distilled prompt.
- **Distill, don't dump:** the 79 KB `blender-pipeline.md` is too much for a 14B. Extract
  §0 operating reality + the 9 golden rules into `forge-prompt.md`.
- **Enforce verify-by-file in the harness,** not the model: after any render/export tool
  call, the harness `Read`s the output and asserts non-zero before continuing.

## 6. GPU & concurrency reality (the hard constraint)
One 24 GB GPU. `hermes4.3-36b` ≈ 21 GB + 64K KV → already CPU-spilling; `hermes4-14b`
≈ 15 GB. Blender EEVEE rendering also needs VRAM (EEVEE-only — no Cycles). So:
- **Hermes resident + an EEVEE render do not co-reside.** The harness must **time-share**:
  unload/idle the model (`keep_alive:0` or `ollama stop`) before a render, reload after.
- A Hermes lane is therefore **sequential-with-renders**, *not* a true extra concurrent
  render worker alongside Claude lanes. Schedule accordingly.

## 7. Safety
blender-mcp `exec()`s arbitrary `bpy`/Python. An *autonomous local model* generating that
warrants the care the `ui-audit` agent already gets (kernel-sandboxed, network-isolated,
allowlisted ops). Minimum: system-prompt constraints (writes only under `$HOME/<renderdir>`,
no `os`/network); better: a pre-exec code scan; best: ui-audit-style sandbox parity.

## 8. Effort & phasing
- ~~Phase 0 — tool-calling spike~~ **DONE (GREEN).**
- **Phase 1 — MVP harness (1–2 d):** Option B loop; Hermes runs "create → render →
  read-back-verify" on its lane; GPU unload-during-render.
- **Phase 2 — usable (2–3 d):** distilled prompt tuned against real golden-rule failures;
  `doctor.sh`; install/revert; code-safety constraints.
- **Phase 3 — hardened (optional):** sandbox parity with ui-audit; quality eval vs Claude.

~3–5 focused days to a usable Phase 2 (down from the pre-spike 4–6).

## 9. When to use it
Strong for **cost-free, offline, bulk/iterative** asset chores — turntable re-renders,
parameter sweeps, batch variants — where "good enough, unattended, free" beats "best."
For the hero money-shot, Claude lanes still win (14B/36B bpy quality trails Claude).

## 10. Open decisions
1. **Model tier:** `hermes4-14b` (recommended — fits VRAM, leaves room for EEVEE) vs
   `hermes4.3-36b` (smarter, won't co-reside with a render at all).
2. **Safety posture:** system-prompt constraints only, or full ui-audit-style sandbox?
3. **Scheduling:** how a Hermes lane interleaves with Claude lanes on the shared GPU.

## 11. Next step
Green-light Phase 1: build `hermes-forge.py` (Option B) + `forge-prompt.md`, prove a
full create→render→verify loop on a dedicated lane (e.g. `NIMBUS_BLENDER_PORT=9879`).
