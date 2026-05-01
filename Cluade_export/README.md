# KeyCheck — Brand Asset Handoff

This bundle is what Claude Code (or you) needs to wire the new icon into the macOS app, plus social/README assets.

## Contents

```
export/
├── AppIcon_1024.png            # master 1024×1024 with full waves
├── icon_1024.svg               # editable SVG source (full)
├── mark_1024.svg               # SVG source (no waves, for favicon)
├── iconset/                    # PNGs at all macOS iconset sizes
│   ├── icon_16x16.png         (16)
│   ├── icon_16x16_2x.png      (32 — Apple wants @2x, renamed by handoff.sh)
│   ├── icon_32x32.png         (32)
│   ├── icon_32x32_2x.png      (64)
│   ├── icon_128x128.png       (128)
│   ├── icon_128x128_2x.png    (256)
│   ├── icon_256x256.png       (256)
│   ├── icon_256x256_2x.png    (512)
│   ├── icon_512x512.png       (512)
│   └── icon_512x512_2x.png    (1024)
├── mark/                       # simplified mark (no soundwaves) for favicon
│   ├── mark_16x16.png
│   ├── mark_32x32.png
│   ├── mark_64x64.png
│   ├── mark_128x128.png
│   └── mark_256x256.png
└── handoff.sh                  # iconutil + Info.plist patcher
```

## Steps for Claude Code

1. **Copy `export/` into the `key_check` repo root.**
2. **Run `bash export/handoff.sh`** — this:
   - Renames `_2x` → `@2x` (filesystem-safe → Apple's iconset convention)
   - Generates `KeyCheck.icns` via `iconutil`
   - Patches `Info.plist` with `CFBundleIconFile = KeyCheck`
3. **Update `build.sh`** to copy `KeyCheck.icns` into the `.app/Contents/Resources/` folder during bundling.
4. **Commit & push:**
   ```bash
   git add KeyCheck.icns Info.plist build.sh export/
   git commit -m "feat: app icon, social preview, README hero"
   git push
   ```
5. **GitHub social preview:** upload `social_preview_1280x640.png` (generate from `KeyCheck Brand.html` if needed) via:
   ```bash
   gh repo edit yuchamichami/key_check --enable-issues  # placeholder; social preview is via the repo settings UI or REST
   ```
   …or in repo Settings → Social preview, drag the PNG.
6. **README**: drop `readme_hero_1600x800.png` at the top of README.md.

## Design system at a glance

- **Background gradient**: `#0B1030` → `#171347` → `#2C1454` (deep navy → indigo → plum)
- **Accent**: cyan `#5BD1FF` → `#2E8BFF`
- **Keycap**: off-white top `#FCFCFE` → `#D2D2DE`, sides `#A6A6B8` → `#5A5A70`
- **Typography**: JetBrains Mono 700 for legend "K"; same family across all assets
- **Squircle**: Big Sur radius `1024 × 0.2237 ≈ 229`

## Splash (optional)

`KeyCheck Splash.html` — drop-in HTML splash showing the icon with ripple animation. Useful as a launch screen or repo banner.
