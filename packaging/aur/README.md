# AUR packaging (Phase 2)

The pack builds a few things from source inside its installers. This directory
turns the ones **we own and that aren't already in the AUR** into proper AUR
packages, so installers can `paru -S <pkg>` (fast, cached, no `base-devel`)
instead of compiling inline — while keeping the bundled build as a fallback.

## Strategy: prefer AUR, fall back to inline build

The canonical `PKGBUILD` for each package stays **in its layer** (single source
of truth — e.g. `8-dolphin-quicklook/PKGBUILD`). The layer installer tries the
AUR package first and falls back to that same PKGBUILD if it isn't published yet
or no AUR helper is present. So nothing here is load-bearing: publishing is an
optimisation, and an unpublished package degrades gracefully to the old behaviour.

`publish.sh` assembles `PKGBUILD` + a freshly generated `.SRCINFO` into a clone
of the AUR repo and commits — **everything up to the `git push`**, which needs
your AUR SSH key and so is left for you to run.

## Packages

| AUR package | source PKGBUILD | status | notes |
|---|---|---|---|
| `kiview-git` | `8-dolphin-quicklook/PKGBUILD` | ready to publish | not in AUR (the tagged `kiview` v1.1 lacks the direct `-s` preview mode) |

### Deferred (intentionally not packaged here yet)
- **`kwin-effect-shaders`** (Layer 9) — upstream is a third party
  (`kevinlekiller/kwin-effect-shaders`), not in the AUR, and it lives in a layer
  another track is actively editing. Package it the same way once that settles.
- **`nimbus-flux`** (Layer 10) — the pack's own engine. Publishing it standalone
  is really a *sharing* decision (Phase 3), and Layer 10 is under active
  development. Hold until both are ready.

## Publishing a package

```bash
# one-time: AUR account + SSH key at https://aur.archlinux.org/account
ssh aur@aur.archlinux.org            # should authenticate (no shell)

bash packaging/aur/publish.sh kiview-git    # prepares everything up to the push
# then run the printed command, e.g.:
git -C ~/.cache/nimbus-aur/kiview-git push -u origin master
```

After it's live, Layer 8 will pick it up automatically (`paru -S kiview-git`);
re-run `publish.sh` whenever the PKGBUILD changes to refresh the AUR copy.
