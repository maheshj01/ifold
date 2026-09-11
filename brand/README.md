# iFold Mac brand

One mark, one idea: a screen whose corner folds — on the hinge side, where iFold's crease is.

| File | Use |
|---|---|
| `ifold-mark-tile.svg` | App icon, social avatars, favicons. Graphite tile, macOS icon grid. Source of truth for `Resources/AppIcon.icns`. |
| `ifold-mark.svg` | The mark alone on transparent, for placing on light or dark. |
| `ifold-mark-mono.svg` | Outline, `currentColor`, 32-grid. UI chrome at 20–32 px. |
| `ifold-mark-mono-filled.svg` | Filled silhouette, `currentColor`. Best below 24 px (site header, menu bar). |
| `ifold-avatar-1024.png` | Ready-to-upload avatar (X, GitHub, Product Hunt). |

Colours: graphite `#2A2C36 → #0E0F14`; wallpaper `#FF7A59 → #A360FF → #4AA4FF`.
Keep the crease highlight — it is what makes the shape read as a fold at 16 px.

Regenerate every raster from the SVGs with `./brand/build.sh`.
