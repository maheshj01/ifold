# iFold Mac website

The product site for iFold Mac, kept alongside the app in `site/`. A static site: no framework, no build step, no dependencies.

## Run locally

From the repository root:

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory site/dist
```

Open http://127.0.0.1:4173. Any static file server works; the JavaScript uses ES modules, so the page must be served over HTTP rather than opened from disk.

## Deploy

`site/dist/` is the whole site and is deployed on **Vercel**: project Root Directory `site/dist`,
framework preset *Other*, no build command, no output directory. Every push to `main` redeploys.

Everything is path-relative or root-relative, so the same folder works unchanged on any static host
(Netlify, Cloudflare Pages, GitHub Pages with a custom domain). Once the production domain is final, set the
absolute `og:image` URL in `index.html` (and optionally `canonical` / `og:url`) so link previews render.

## Layout

```
site/dist/
├── index.html            page content, demo controls, setup and photo dialogs
├── 404.html              not-found page (used automatically by most static hosts)
├── robots.txt
├── site.webmanifest
├── css/style.css         tokens, layout, sections, responsive and reduced-motion rules
├── js/
│   ├── main.js           entry point: hero scroll, playground controls, wiring
│   ├── macbook.js        millimetre-accurate MacBook Pro 14" renderer, folding desktop, motion blur
│   ├── desktop-texture.js  loads the desktop screenshot and builds the frosted copy
│   ├── fold-view.js      spring + motion-blur state per canvas (ported from the app), replay, rAF loop
│   └── dialogs.js        native <dialog> behaviour and the copy button
└── assets/
    ├── icon.svg, favicon-32.png, apple-touch-icon.png
    ├── desktop.{webp,jpg}   the real desktop shown on the screen
    ├── og.jpg            1200×630 social preview
    └── ifold-demo.mp4 + ifold-demo-poster.jpg   13 s desk video (muted loop inline, with sound in the dialog)
```

## How the demo works

Scroll the hero to lower the lid and curl the desktop; "See it move" replays a close-and-open. The dark playground has a keyboard-accessible lid-angle slider, Silk / Shade / Frost presets, and a replay button.

**The MacBook** (`js/macbook.js`) is drawn in millimetres from Apple's published 14-inch MacBook Pro dimensions — 312.6 × 221.2 × 15.5 mm body, a 3024×1964 @ 254 ppi display (302.4 × 196.4 mm active area with rounded top corners and the notch), the 14.5-unit ANSI Magic Keyboard with full-height function row and inverted-T arrows, speaker grilles, Force Touch trackpad, hinge cover and front scoop — under a fixed perspective camera. The drawing's extents are computed once and fitted into the canvas, so it can never spill outside its stage.

**The fold** mirrors the macOS app's renderer: the desktop is 90 strips whose lean grows toward the top of the screen, each shaded by how far it turns away plus a light sheen. Frost cross-fades to a pre-blurred copy of the texture, so it works in Safari too (no canvas `filter`).

**The motion** (`js/fold-view.js`) is a direct port of the app's Swift `Spring` and blur logic: a second-order spring (0.32 s response, 0.82 damping) chases the lid angle, and the motion-blur radius follows the spring's angular speed — fast attack, slow release — so the picture smears the instant the lid moves and resolves as it settles. The blur is a vertical multi-sample smear of the folded-desktop layer, standing in for the app's `CIMotionBlur`.

The desktop on the screen is a real macOS screenshot (`assets/desktop.webp`, JPEG fallback), loaded asynchronously — the MacBook draws at once with a dark screen and the desktop fills in when the image arrives. `prefers-reduced-motion` disables the scroll-driven animation and replaces replays with a two-state toggle. Dialogs are native `<dialog>` elements, so Escape and focus handling come for free.

## Product notes

Copy and behaviour come from the iFold README and Swift renderer. The **Download** buttons (nav and the closing section) open the setup dialog: the DMG link points at `https://github.com/maheshj01/ifold-mac/releases/latest/download/ifold-mac.dmg` (the asset is always named `ifold-mac.dmg`, so the link survives new releases), followed by the install steps — including the one-time Gatekeeper *Open Anyway* step while the build is signed but not notarized — and the source-build alternative. Bump the version/size line in the dialog when cutting a release; drop the Gatekeeper step once releases are notarized.
