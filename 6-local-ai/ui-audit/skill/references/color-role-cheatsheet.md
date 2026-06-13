# KDE Plasma Color Role → UI Element Mapping

Mapping of `.colors` (KColorScheme) roles to UI elements in Plasma 6. Verified
against KColorScheme API docs and Breeze's QStyle source.

> **Caveat that bit us before:** these mappings describe the **native Breeze
> widget style**. Fully custom QML controls (e.g. the aurora wallpaper's
> `AuroraSlider`) define their own delegate colors and may ignore these roles
> entirely — check the widget's source before assuming a role drives it. And
> Kvantum, when active, draws many widgets from its own SVG theme rather than
> KColorScheme. So a role here is the *default-Breeze* answer, not a guarantee.

## Color sets (7)
View, Window, Button, Selection, Tooltip, Complementary, Header — the
`KColorScheme::ColorSet` values. Each set has foreground roles
(Normal/Inactive/Active/Link/Visited/Negative/Neutral/Positive), two background
roles (Normal/Alternate), and two decoration roles (Focus/Hover).

## View `[Colors:View]`
Background of content areas — lists, tree views, text entry fields, settings
pages.
- `BackgroundNormal` — content-area background
- `BackgroundAlternate` — alternating list/table rows
- `ForegroundNormal` — default text on content backgrounds
- `DecorationFocus` / `DecorationHover` — focus ring / hover highlight on view widgets

> NOTE: the native QSlider **unfilled groove is NOT View** — it's
> `WindowText` at ~20% alpha over the `Window` background (a faint neutral
> track). Changing `View/BackgroundNormal` does not recolour a Breeze slider
> groove.

## Window `[Colors:Window]`
Window/dialog body background and chrome.
- `BackgroundNormal` — window/dialog background
- `BackgroundAlternate` — secondary chrome (tab bars)
- `ForegroundNormal` — window text; at ~20% alpha it is also the **native slider
  unfilled groove**

## Button `[Colors:Button]`
Push buttons, combo boxes, and the **slider handle**.
- `BackgroundNormal` — button face **and the slider handle FILL**
- `BackgroundAlternate` — secondary button variant
- `ForegroundNormal` — button text
- `DecorationFocus` / `DecorationHover` — focus/hover **OUTLINE** on buttons and
  the slider handle (the ring around the knob, NOT the knob fill)

## Selection `[Colors:Selection]`
Selected / highlighted / "active" fills — this set is the system accent/highlight.
- `BackgroundNormal` — selected-item background **and the slider FILLED (elapsed)
  portion of the track**
- `ForegroundNormal` — text on selected backgrounds (usually light)

## Tooltip `[Colors:Tooltip]`
- `BackgroundNormal` / `ForegroundNormal` — tooltip popup background / text

## Header `[Colors:Header]`
Section headers, list/tree header rows, system-settings group titles.
- `BackgroundNormal` / `ForegroundNormal` — header background / text
- Has the one shipped per-state subsection: `[Colors:Header][Inactive]`

## Complementary `[Colors:Complementary]`
Full-screen inverted-background contexts — **lock screen, logout/SDDM-style
screens, and some apps' fullscreen modes**. It is NOT the Plasma panel/taskbar.
- `BackgroundNormal` / `ForegroundNormal` — fullscreen surface background / text

> **Panels, taskbars, the system tray are NOT controlled by the color scheme.**
> They are drawn by the **Plasma Desktop (SVG) theme** (`plasma-apply-desktoptheme`
> / `~/.local/share/plasma/desktoptheme/`), independent of `.colors`.

## Widget states (Disabled / Inactive)
There are **no per-role `[Hover]`/`[Disabled]`/`[Inactive]` subsections** (a
common myth). State colours are derived globally:
- `[ColorEffects:Disabled]` — desaturate/tint/contrast for disabled widgets
- `[ColorEffects:Inactive]` — dimming when the parent window loses focus
- The sole shipped per-role state section is `[Colors:Header][Inactive]`.
- Hover/focus are **not states** — they come from each set's `DecorationHover` /
  `DecorationFocus`, computed by the style.

`[ColorEffects:Disabled]` / `[ColorEffects:Inactive]` keys:
- `Color` — tint RGB blended over the state's colours
- `IntensityAmount` / `IntensityEffect` — desaturation (0=none .. 1=max)
- `ContrastAmount` / `ContrastEffect` — contrast shift
- `[ColorEffects:Inactive] Enable` — master on/off for inactive-window dimming
- `[ColorEffects:Inactive] ChangeSelectionColor` — also dim selection in inactive windows

## Recolouring a native Breeze slider (corrected)
- Filled/elapsed portion → `[Colors:Selection] BackgroundNormal` (the accent)
- Handle fill → `[Colors:Button] BackgroundNormal`; handle focus/hover ring →
  `[Colors:Button] DecorationFocus` / `DecorationHover`
- Unfilled groove → derived (`Window` text @ ~20%); not directly a `BackgroundNormal`

```ini
[Colors:Selection]
BackgroundNormal=124,92,196   # filled/elapsed track = accent

[Colors:Button]
BackgroundNormal=64,60,80     # handle fill
DecorationFocus=216,194,255   # handle focus ring (and button focus ring)
```

## Quick diagnostic commands
```bash
# Active scheme — the CANONICAL key is [General]ColorScheme (NOT [KDE])
ACTIVE=$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)
echo "active scheme: $ACTIVE"

# Roles present in the active scheme
grep '^\[' ~/.local/share/color-schemes/"$ACTIVE".colors

# A specific role's colours
grep -A 12 '^\[Colors:View\]' ~/.local/share/color-schemes/"$ACTIVE".colors

# Userland vs system schemes
ls ~/.local/share/color-schemes/ /usr/share/color-schemes/
```
