# Color Theory & Accessibility Reference (KDE Plasma 6, dark themes)

Purpose: ground mechanical color audits of `~/.local/share/color-schemes/*.colors`.
Values are `R,G,B` (0–255). A 4th value (0–255) is alpha; ignore for contrast unless told otherwise.

## 1. Contrast math (compute, don't guess)
For channel c in {R,G,B}: c' = c/255; lin = c'<=0.04045 ? c'/12.92 : ((c'+0.055)/1.055)^2.4
L = 0.2126*linR + 0.7152*linG + 0.0722*linB
Contrast = (max(L1,L2)+0.05) / (min(L1,L2)+0.05)   → range 1:1 .. 21:1
(WCAG 2.x. The threshold is 0.04045 as currently published — pre-2021 it was
0.03928; W3C states the change has no practical effect. Either is fine.)

### Thresholds (WCAG 2.x)
| Use | AA | AAA |
|---|---|---|
| Body / normal text (<24px, or <18.66px bold) | 4.5 | 7.0 |
| Large text (>=24px, or >=18.66px bold) | 3.0 | 4.5 |
| UI components, focus rings, icons, borders (non-text) | 3.0 | n/a |
| Disabled controls | exempt | exempt |
APCA secondary signal (dark UI, where WCAG 2 is conservative): body |Lc|>=75, large/secondary >=60, non-text >=45. APCA is WCAG 3 draft / NON-NORMATIVE, and real thresholds vary by font size/weight — treat these as a sanity check, not a pass/fail gate.

## 2. Role -> pairing map (which fg is checked on which bg)
For each [Colors:ROLE], check these fg-on-BackgroundNormal pairings (also BackgroundAlternate for row text):
- ForegroundNormal      -> body text          -> need 4.5 (target 7)
- ForegroundInactive    -> secondary text     -> need 4.5 (3.0 acceptable if clearly secondary)
- ForegroundActive      -> emphasized text    -> need 4.5
- ForegroundLink        -> links              -> need 4.5
- ForegroundVisited     -> visited links      -> need 4.5
- ForegroundNegative    -> errors             -> need 4.5 (3.0 large)
- ForegroundNeutral     -> warnings           -> need 4.5
- ForegroundPositive    -> success            -> need 4.5
- DecorationFocus/Hover -> focus ring/hover   -> need 3.0 vs the surface it rings (non-text)
Cross-role specials:
- Selection: ForegroundNormal on Selection/BackgroundNormal (selected text) -> need 4.5
- Tooltip:   ForegroundNormal on Tooltip/BackgroundNormal -> need 4.5
- Button:    ForegroundNormal on Button/BackgroundNormal  -> need 4.5
- WM:        activeForeground on activeBackground (titlebar text) -> need 4.5
Common-path priority (fix first): View text, Window text, Selection text, Button text, Link on View/Window.

## 3. OKLCH/HSL rules of thumb for a coherent dark theme
- No pure black surface: base OKLCH L 0.16-0.24 (RGB ~24..40), never #000.
- No pure white text: ForegroundNormal OKLCH L ~0.92-0.95, faintly tinted toward the theme hue.
- Elevation = lighter, not darker. Each surface step up (base->card->popover->raised) gains ~ΔL 0.03-0.05.
  Order to verify, darkest->lightest: Complementary/panel <= View <= Window/Header <= Tooltip <= Button.
- Accent is a saturated RELATIVE of the surface hue: keep accent within ~30° (OKLCH) of the surface hue,
  not the complement. (Cyan accent on a violet surface = bug.)
- Surface chroma low (C 0.01-0.06); accent chroma moderate (C 0.10-0.18). Mid-lightness hued SURFACES
  (L 0.40-0.60) are a smell: colored foregrounds have nowhere to land. Surfaces go dark; color goes to accents/text.
- Semantic colors on dark: lighten to OKLCH L 0.70-0.78 (the white-bg versions ~L 0.55-0.65 fail on dark).
  Keep them hue-separated: red ~25°, amber ~70°, green ~150° (OKLCH), well apart from the link hue.
- Roughly balance semantic chroma; don't let red/amber (C~0.2) drown a low-chroma link.
- A "themed" scheme threads the hue through EVERY surface at low chroma, not one colored panel in grey.

## 4. Quick audit checklist (mechanical)
[ ] Identify live scheme: kreadconfig6 --file kdeglobals --group General --key ColorScheme (audit the file that actually wins).
[ ] Is it actually dark? base BackgroundNormal L < 0.10? If a surface is L>0.5, flag "light surface in dark theme".
[ ] Compute contrast for every pairing in section 2; list each as PASS/FAIL AA-normal, AA-large, AAA.
[ ] Flag every fg-on-bg < 4.5 (body) explicitly with its ratio.
[ ] Selection: white/light text on Selection bg >= 4.5? (frequent failure)
[ ] Link/semantic fg vs their surface >= 4.5? (frequent failure when reused from a light theme)
[ ] Surfaces form a monotonic lighter-with-elevation ladder? List L values in order; flag inversions.
[ ] Accent hue within ~30° (OKLCH) of surface hue? Flag clashes (e.g. cyan accent / violet surface).
[ ] No pure #000 surface, no pure #FFF body text.
[ ] ForegroundNeutral/Positive/Negative lightened for dark (OKLCH L ~0.72-0.78)?
[ ] [ColorEffects:Inactive] Enable=true if inactive dimming is intended.
Report format per pairing: `ROLE: fg(r,g,b) on bg(r,g,b) = X.X:1 — AA-norm PASS/FAIL, AA-large P/F, AAA P/F`.
