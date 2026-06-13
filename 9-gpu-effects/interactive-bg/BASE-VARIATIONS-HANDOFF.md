# Handoff — base-look variations for `com.nimbus.aurora`

Spec for adding selectable **base styles** to the aurora wallpaper. The current
single style (a domain-warped fbm "flow") becomes one of several the user picks in
*Wallpaper → Configure*. Read `README.md` for the plugin layout and
`WINDOW-REACTIVE-HANDOFF.md` for the bridge architecture (unaffected here).

## Goal

One new config control — **Style** — switches the *generative base look* while
**everything else stays shared**: the palette/themes, light↔dark lift, custom
colours, and the whole reactive light system (cursor bloom, window bend/glow/wake,
music energy/bass/beat). A variation changes how the background *field* is drawn;
it does NOT re-implement reactivity or colour. Adding a style should be ~30–60 lines
of GLSL plus one combobox entry.

## The seam (this is the important part)

In `contents/shaders/aurora.frag`, `main()` currently runs in this order:

```
1. music energy + time            ← SHARED (keep)
2. cursor / window / music warp  → warpP   ← SHARED (keep): the reactive flow field
3. BASE FIELD: two-stage fbm domain warp (q, r, f), SC=0.85          ← VARY THIS
4. palette() + dark lift → c0..c4 + accentWarm/accentCool   ← SHARED (keep)
5. BASE COMPOSE: sky gradient + ribbon ramp → col, and `shade`        ← VARY THIS
6. depth mult + loudness swell                              ← SHARED (keep)
7. `light` accumulator (cursor+window+music) → screen-blend ← SHARED (keep)
8. intensity + dither + out                                ← SHARED (keep)
```

Steps **3 and 5 are the base look.** Factor them into one function per style:

```glsl
// Produces the base colour AND a 0..1 "where the aurora is bright" field that the
// shared reactive light rides (beat flares & ribbon bloom read `shade`). Every
// style MUST output a sensible `shade` or the music/cursor light won't sit right.
// `mus` is the music packet: (bass, mid, level, beat) — see "Music packet" below.
vec3 baseLook(int style, vec2 warpP, vec2 p, float t,
              vec3 c0, vec3 c1, vec3 c2, vec3 c3, vec3 c4,
              float uDark, vec4 mus, out float shade);
```

Then `main()` becomes: `… ; float shade; vec3 col = baseLook(uStyle, warpP, p, t, c0,c1,c2,c3,c4, uDark, mus, shade); …` and the existing `light` block (step 7)
is untouched. Style 0 = the *current* code moved verbatim into `baseLook`.

### Music packet (`mus`)

`main()` builds `mus = vec4(mBass, mMid, mLevel, mBeat)` once — four eased,
master-gated drives, each with a role a style picks from so the reaction fits its
metaphor rather than one shared term:

- **`mus.x` mBass** — slow low-end surge → **scale / reach / drift** (swell the field).
- **`mus.y` mMid** — band "body" → **brightness / density** (fill it in).
- **`mus.z` mLevel** — overall loudness → global luminance breath (used in `main`).
- **`mus.w` mBeat** — gated transient (strong hits only) → a style-native **pulse**
  (a puff / flare / ripple in the style's own geometry). The SAME `mBeat` also fires
  the shared light flare, so the structural puff and the light flash land as one hit.

Keep music on slow amplitudes, never on fast spatial motion — that reads as jitter
(treble is deliberately not in the packet for the same reason). Per-style coefficients
sit around `0.1–0.3`; copy a neighbouring style's restraint when adding one.

**Hard rule: build every style from the palette stops `c0..c4`** (never hardcoded
RGB). They already encode theme + light/dark + custom palette, so a style that only
mixes `c0..c4` gets all 6 themes, both schemes, and the custom picker **for free**.
Hardcoding a colour breaks theming and is the #1 thing to reject in review.

## Config plumbing (3 small edits, mirror the existing `Theme` control)

1. `contents/config/main.xml` — add under group `General`:
   ```xml
   <entry name="Style" type="Int"><default>0</default></entry>
   ```
2. `contents/ui/config.qml` — add an alias + a ComboBox (copy the `Theme` one at
   lines ~16/31):
   ```qml
   property alias cfg_Style: styleBox.currentIndex
   QQC2.ComboBox { id: styleBox; Kirigami.FormData.label: i18n("Style:")
       model: [i18n("Flow"), i18n("Mesh gradient"), i18n("Silk curtains"),
               i18n("Caustics"), i18n("Contours"), i18n("Calm gradient")] }
   ```
3. `contents/ui/main.qml` — add to the ShaderEffect (near `uTheme`):
   ```qml
   property int uStyle: root.configuration.Style ?? 0
   ```
   and `contents/shaders/aurora.frag` UBO: `int uStyle;` (order doesn't matter —
   ShaderEffect binds UBO members to QML properties by NAME via the .qsb reflection).

Branching on a uniform int is *uniform* control flow (every fragment takes the same
branch) → cheap; don't worry about it. Keep each style's cost near the current fbm
(≤ ~5 noise octaves total) so it stays smooth at 4K.

## Candidate styles (an opinionated slate — prune to the 3–4 worth shipping)

All slow + dreamy to match Big Sur; each must define `shade` and use only `c0..c4`.

0. **Flow** *(current)* — domain-warped fbm ribbons over a vertical sky. Keep as the
   default; just relocate into `baseLook`.
1. **Mesh gradient** — 4–6 soft gaussian colour "sources" (one per palette stop)
   whose centres drift on slow `sin`/`cos` of `t`; blend by inverse-distance weight.
   This is the macOS Sonoma/Ventura dynamic-mesh look — very Apple, very calm. `shade`
   = normalised brightness of the blended result. Cheapest of the set (no fbm).
2. **Silk curtains** — aurora-borealis vertical curtains: warp `p.x` by a low-freq
   `fbm(vec2(p.x, t))`, draw a few soft vertical light bands (`exp` of distance to a
   wandering x-centre), tint along `c2..c4`. `shade` = band intensity.
3. **Caustics** — calm water-light: ridged noise `abs(fbm*2-1)` at two scales,
   thresholded soft, in cool palette stops. Keep amplitude low so it shimmers slowly,
   not boils. `shade` = caustic brightness.
4. **Contours** — topographic iso-lines of the fbm field: `c = abs(fract(f*N)-0.5)`,
   thin glowing lines via `smoothstep`, over a dim `c0→c1` wash. Reads "technical/
   WhiteSur." `shade` = line proximity. (Watch aliasing — use `fwidth(f)` for line
   width.)
5. **Calm gradient** — near-static: a slowly-rotating linear/radial sweep through
   `c0..c4` with one faint fbm wobble. For users who want almost-zero motion. `shade`
   = position along the sweep.

## Verify each style (don't ship on faith)

- Recompile: `qsb --qt6 -o contents/shaders/aurora.frag.qsb contents/shaders/aurora.frag`
  (qsb at `/usr/lib/qt6/bin/qsb`). A GLSL error here = the qsb won't update.
- Deploy + reload (editing the installed file alone is NOT enough — plasmashell
  serves stale compiled QML):
  ```bash
  cp contents/shaders/aurora.frag{,.qsb} ~/.local/share/plasma/wallpapers/com.nimbus.aurora/contents/shaders/
  rm -rf ~/.cache/plasmashell/qmlcache
  systemctl --user restart plasma-plasmashell
  ```
- For EACH style: cycle all 6 themes × {light, dark} × the custom palette. If any
  combo has hardcoded colour or a dead/blown-out `shade`, fix it. Confirm the cursor
  bloom + a window drag + music still read correctly on top (the shared `light` rides
  `shade`).
- Watch for errors: `journalctl --user -b | grep -iE 'aurora|shader' | grep -i error`.

## Don't-repeat-this-session's-mistakes

- **Never read state files via `file://` XMLHttpRequest** — it never reaches `DONE`
  in this Plasma build. (Not relevant to styles, but if you touch `main.qml`, use the
  `DataSource{engine:"executable"}` `cat` pattern.)
- **Keep music/treble out of fast motion.** A prior pass mapped treble to a per-pixel
  sparkle + a `sin(iTime*8)` warp; it read as *chaos*. Styles should be slow fields;
  let the shared `energy`/bass do the gentle breathing. If a style needs liveliness,
  drive it from `mBass` (eased, low-freq), not raw treble.
- **Test at 4K** — the dev box has a 3840×2160 screen; an octave too many tanks it.
- Plasma-6-wallpaper gotchas (WallpaperItem root, no Kirigami scheme tracking, qsb
  shaders) are in `README.md` — already paid for, don't rediscover.

## Stretch (optional)

- A **per-style default Speed/Intensity** nudge (some styles want slower drift).
- "**Surprise me**" — pick a style+theme at login (write the config keys in `apply.sh`).
- Expose the **mesh source count** / **contour density** as a single "Detail" slider
  reusing one spare uniform, rather than a control per style.
