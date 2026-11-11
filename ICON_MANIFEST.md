# ICON_MANIFEST: Steal a Fish icon redo

Replaces the 65 flat icons in `items/icons/` with polished, lit renders, and adds 8 mutation badges.
Same file names, same 512x512 RGBA PNG format, so nothing else in the repo changes.

## Status

| Phase | Status |
|---|---|
| 1. Tool check | done |
| 2. Renderer + one test icon per category | done (`icon_render.py`, `gen_icons2.py`) |
| 3. All 65 icons + 8 badges | done (first pass) |
| 4. Contact sheet check + one fix pass | pending |
| 5. Manifest + report | pending |

## Phase 1: tools

| Tool | Present? |
|---|---|
| cairosvg, rsvg-convert, inkscape | no |
| Blender | no |
| ImageMagick (convert/magick) | no |
| scipy | no |
| **numpy 2.5.4, Pillow 13.0** | **yes** (in `/tmp/itemsvenv`, see `tools/items/requirements.txt`) |

No SVG renderer exists and there is no internet, so everything is drawn with a custom numpy + Pillow renderer
(`tools/items/icon_render.py`). Decision: rather than an SVG pipeline, the frame, stars and badges are drawn
directly with Pillow at 4x resolution and downsampled, which gives the same anti-aliased vector look.

## Decisions log

_Filled during the run._

## Failures and retries

_Filled during the run._
