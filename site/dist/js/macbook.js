/**
 * Draws a 14-inch MacBook Pro with its desktop folded along the screen.
 *
 * All geometry is in millimetres, taken from Apple's published dimensions:
 * 312.6 × 221.2 × 15.5 mm; 14.2" Liquid Retina XDR, 3024×1964 at 254 ppi
 * (an active area of exactly 302.4 × 196.4 mm); 78-key ANSI Magic Keyboard
 * with full-height function keys and Touch ID; Force Touch trackpad.
 *
 * World space: x across (0 = centre), y up (0 = top of the base), z toward
 * the viewer (0 = back edge). The lid pivots on a hinge just above the back
 * edge; the desktop is drawn as thin strips whose lean grows toward the top,
 * mirroring the macOS app's strip renderer.
 */

const clamp = (n, min, max) => Math.max(min, Math.min(max, n));
const deg = (d) => (d * Math.PI) / 180;

// --- Machine dimensions (mm) --------------------------------------------------

const BASE = { width: 312.6, depth: 221.2, height: 15.5, radius: 10 };
const HINGE = { y: 2.5, z: 4 }; // pivot, relative to the base's back-top edge
const LID = { width: 312.6, height: 216, thickness: 3.6, rim: 0.6, radiusTop: 8, radiusBottom: 2.5 };
const DISPLAY = { width: 302.4, height: 196.4, bottom: 14, cornerRadius: 6 }; // bottom = mm above the hinge
const NOTCH = { width: 38, height: 7.4, radius: 3 };
const KEYBOARD = { unit: 19, keySize: 16.4, rows: 6, left: -139, back: 9, wellRadius: 3, wellPadding: 2 };
const GRILLE = { inner: 142, width: 10, back: 9, depth: 116, pitch: 2.2 };
const TRACKPAD = { width: 130, depth: 82, back: 131, radius: 4 };
const FRONT_SCOOP = { width: 30, depth: 2.5 };

/** ANSI layout, widths in key units. Rows run from the function row down. */
const KEY_ROWS = [
  [['esc', 1.5], ['☀', 1], ['☀', 1], ['▦', 1], ['⌕', 1], ['◉', 1], ['◐', 1], ['◀◀', 1], ['▶‖', 1], ['▶▶', 1], ['◁', 1], ['◁)', 1], ['◁))', 1], ['', 1]],
  [['`', 1], ['1', 1], ['2', 1], ['3', 1], ['4', 1], ['5', 1], ['6', 1], ['7', 1], ['8', 1], ['9', 1], ['0', 1], ['-', 1], ['=', 1], ['delete', 1.5]],
  [['tab', 1.5], ['Q', 1], ['W', 1], ['E', 1], ['R', 1], ['T', 1], ['Y', 1], ['U', 1], ['I', 1], ['O', 1], ['P', 1], ['[', 1], [']', 1], ['\\', 1]],
  [['caps lock', 1.75], ['A', 1], ['S', 1], ['D', 1], ['F', 1], ['G', 1], ['H', 1], ['J', 1], ['K', 1], ['L', 1], [';', 1], ["'", 1], ['return', 1.75]],
  [['shift', 2.25], ['Z', 1], ['X', 1], ['C', 1], ['V', 1], ['B', 1], ['N', 1], ['M', 1], [',', 1], ['.', 1], ['/', 1], ['shift', 2.25]],
  [['fn', 1], ['control', 1], ['option', 1], ['command', 1.25], ['', 5], ['command', 1.25], ['option', 1], ['◀', 1], ['▲▼', 1], ['▶', 1]],
];

/** Fold behaviour: the desktop is flat at FLAT_ANGLE and fully curled FOLD_RANGE degrees below it. */
const FLAT_ANGLE = 102;
const FOLD_RANGE = 70;
const MAX_TILT = 1.3; // radians, top edge
const STRIPS = 90;

/** Look-and-feel per preset; mirrors the app's Silk / Shade / Frost styles. */
export const PRESETS = {
  silk: { shade: 0.5, frost: 0 },
  shade: { shade: 1.1, frost: 0 },
  frost: { shade: 0.5, frost: 1 },
};

/**
 * The app expresses motion blur in points on a 982 pt tall screen; convert to
 * a fraction of the display height so the smear looks the same at any size.
 */
const APP_SCREEN_HEIGHT_PT = 982;
const MAX_BLUR_SAMPLES = 14;

const FONT = '-apple-system, "Helvetica Neue", Helvetica, sans-serif';

// --- Drawing helpers ------------------------------------------------------------

function polygon(ctx, points, fill, stroke, lineWidth = 1) {
  ctx.beginPath();
  points.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
  ctx.closePath();
  if (fill) {
    ctx.fillStyle = fill;
    ctx.fill();
  }
  if (stroke) {
    ctx.lineWidth = lineWidth;
    ctx.strokeStyle = stroke;
    ctx.stroke();
  }
}

/** Sample a rounded rectangle in 2-D (u, v) so it can be projected point by point. */
function roundedRectPoints(u0, v0, width, height, radii, samplesPerCorner = 6) {
  const [rTL, rTR, rBR, rBL] = Array.isArray(radii) ? radii : [radii, radii, radii, radii];
  const corners = [
    [u0 + width - rTR, v0 + rTR, rTR, -Math.PI / 2, 0],
    [u0 + width - rBR, v0 + height - rBR, rBR, 0, Math.PI / 2],
    [u0 + rBL, v0 + height - rBL, rBL, Math.PI / 2, Math.PI],
    [u0 + rTL, v0 + rTL, rTL, Math.PI, 1.5 * Math.PI],
  ];
  const points = [];
  for (const [cx, cy, r, from, to] of corners) {
    if (r === 0) {
      points.push([cx, cy]);
      continue;
    }
    for (let i = 0; i <= samplesPerCorner; i++) {
      const a = from + ((to - from) * i) / samplesPerCorner;
      points.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
    }
  }
  return points;
}

/**
 * Draw one horizontal slice of `image` (texture rows v0→v1, 0–1) onto a thin
 * quad. A strip is only ~2 mm tall, so a single affine map is visually exact
 * and avoids the seam two triangles would leave. `clipQuad` is the quad
 * expanded a little top and bottom so neighbouring strips overlap instead of
 * showing hairlines between them.
 */
function drawStrip(ctx, image, quad, clipQuad, v0, v1) {
  const [a, b, , d] = quad; // a,b: bottom edge (left, right); d: top-left
  const width = image.width;
  const y0 = image.height * v0;
  const y1 = image.height * v1;
  const m11 = (b[0] - a[0]) / width, m12 = (b[1] - a[1]) / width;
  const m21 = (d[0] - a[0]) / (y1 - y0), m22 = (d[1] - a[1]) / (y1 - y0);
  const e = a[0] - m21 * y0, f = a[1] - m22 * y0;

  ctx.save();
  polygon(ctx, clipQuad);
  ctx.clip();
  ctx.transform(m11, m12, m21, m22, e, f);
  const pad = 2; // texture rows of extra content for the bleed
  const top = Math.max(0, y1 - pad);
  const bottom = Math.min(image.height, y0 + pad);
  ctx.drawImage(image, 0, top, width, bottom - top, 0, top, width, bottom - top);
  ctx.restore();
}

// --- Camera -----------------------------------------------------------------------

/**
 * A camera in front of and slightly above the machine. Returns projectors for
 * points on the base and on the lid; output is in mm-scaled canvas units with
 * y pointing down.
 */
function createProjector(lidAngleDeg) {
  const pitch = 0.36; // radians the camera looks down
  const eye = 1050; // mm from the machine; smaller = stronger perspective
  const cp = Math.cos(pitch), sp = Math.sin(pitch);
  const project = (x, y, z) => {
    const zc = z - BASE.depth * 0.45; // pivot the pitch around the middle of the machine
    const up = y * cp - zc * sp;
    const toward = y * sp + zc * cp;
    const f = eye / (eye - toward);
    return [x * f, -up * f];
  };
  const alpha = deg(lidAngleDeg);
  const sa = Math.sin(alpha), ca = Math.cos(alpha);
  return {
    /** A point on the base: x across, z from the back edge, y height above the top surface. */
    base: (x, z, y = 0) => project(x, y, z),
    /** A point on the lid: x across, u up the lid from the hinge, d out of the display face toward the viewer. */
    lid: (x, u, d = 0) => project(x, HINGE.y + u * sa - d * ca, HINGE.z + u * ca + d * sa),
  };
}

/** Bounding box (canvas units) of everything that can ever be drawn, so the fit never changes. */
function drawingExtents() {
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  const include = ([x, y]) => {
    minX = Math.min(minX, x); maxX = Math.max(maxX, x);
    minY = Math.min(minY, y); maxY = Math.max(maxY, y);
  };
  const hw = BASE.width / 2;
  for (const angle of [30, 60, 90, 108, 115]) {
    const { base, lid } = createProjector(angle);
    for (const x of [-hw, hw]) {
      for (const z of [0, BASE.depth]) {
        include(base(x, z, 0));
        include(base(x, z, -BASE.height));
      }
      include(lid(x, LID.height, 0));
      include(lid(x, LID.height, -LID.thickness));
    }
    include(base(0, BASE.depth + 30, -BASE.height)); // ground shadow spill
  }
  return { minX, minY, maxX, maxY };
}
const EXTENTS = drawingExtents();

// --- Parts ----------------------------------------------------------------------------

function drawGroundShadow(ctx, { base }, dark) {
  const [cx, cy] = base(0, BASE.depth * 0.6, -BASE.height);
  const [, frontY] = base(0, BASE.depth, -BASE.height);
  ctx.save();
  ctx.translate(cx, cy);
  ctx.scale(1, Math.max(0.12, (frontY - cy) / 170));
  const shadow = ctx.createRadialGradient(0, 0, 20, 0, 0, 200);
  shadow.addColorStop(0, dark ? '#000e' : '#12182640');
  shadow.addColorStop(0.55, dark ? '#0008' : '#12182618');
  shadow.addColorStop(1, '#0000');
  ctx.fillStyle = shadow;
  ctx.beginPath();
  ctx.arc(0, 0, 200, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

function drawBase(ctx, { base }) {
  const hw = BASE.width / 2;
  const outline = roundedRectPoints(-hw, 0, BASE.width, BASE.depth, BASE.radius);

  // Side faces first (mostly hidden), then the front, then the top deck
  const bottom = -BASE.height;
  polygon(ctx, [base(-hw, BASE.radius), base(-hw, BASE.depth - BASE.radius), base(-hw, BASE.depth - BASE.radius, bottom), base(-hw, BASE.radius, bottom)], '#9ea3aa');
  polygon(ctx, [base(hw, BASE.radius), base(hw, BASE.depth - BASE.radius), base(hw, BASE.depth - BASE.radius, bottom), base(hw, BASE.radius, bottom)], '#8f949b');

  const frontTop = outline.filter(([, z]) => z > BASE.depth - BASE.radius - 0.01);
  const frontFace = [...frontTop, ...frontTop.map(([x, z]) => [x, z, bottom]).reverse()];
  const [, y0] = base(0, BASE.depth, 0);
  const [, y1] = base(0, BASE.depth, bottom);
  const front = ctx.createLinearGradient(0, y0, 0, y1);
  front.addColorStop(0, '#c3c7cd');
  front.addColorStop(0.35, '#b1b6bd');
  front.addColorStop(1, '#8d9299');
  polygon(ctx, frontFace.map(([x, z, y]) => base(x, z, y)), front);

  // Thumb scoop in the front lip
  const sw = FRONT_SCOOP.width / 2;
  polygon(ctx, [base(-sw, BASE.depth, 0), base(sw, BASE.depth, 0), base(sw * 0.8, BASE.depth, -FRONT_SCOOP.depth), base(-sw * 0.8, BASE.depth, -FRONT_SCOOP.depth)], '#6f757c');

  // Top deck
  const [, backY] = base(0, 0);
  const [, frontY] = base(0, BASE.depth);
  const deck = ctx.createLinearGradient(0, backY, 0, frontY);
  deck.addColorStop(0, '#cdd0d5');
  deck.addColorStop(1, '#dfe1e5');
  polygon(ctx, outline.map(([x, z]) => base(x, z)), deck, '#b3b7bd', 0.6);
}

function drawHinge(ctx, { base, lid }) {
  const hw = LID.width / 2 - 1;
  // Dark hinge cover between the back edge and the keyboard
  polygon(ctx, [base(-hw, 0.5, 0.2), base(hw, 0.5, 0.2), base(hw, HINGE.z + 3.5, 0.2), base(-hw, HINGE.z + 3.5, 0.2)], '#25272b');
  // The lid's own bottom edge where it meets the hinge
  polygon(ctx, [lid(-hw, 0, 0), lid(hw, 0, 0), lid(hw, 0, -LID.thickness), lid(-hw, 0, -LID.thickness)], '#1d1f23');
}

function drawKeyboard(ctx, projector, keyPixelSize) {
  const { base } = projector;
  const { unit, keySize, rows, left, back, wellRadius, wellPadding } = KEYBOARD;
  const width = 14.5 * unit;
  const depth = rows * unit;

  // Keyboard well
  const well = roundedRectPoints(left - wellPadding, back - wellPadding, width + wellPadding * 2, depth + wellPadding * 2, wellRadius, 3);
  polygon(ctx, well.map(([x, z]) => base(x, z, 0.3)), '#141517');

  const showLegends = keyPixelSize >= 7;
  const gap = (unit - keySize) / 2;
  KEY_ROWS.forEach((row, r) => {
    const z = back + r * unit + gap;
    let x = left;
    for (const [label, units] of row) {
      const w = units * unit - gap * 2;
      const kx = x + gap;
      if (label === '▲▼') {
        // Inverted-T arrows: up and down stacked as two half-height keys
        const h = (keySize - 1.5) / 2;
        drawKey(ctx, projector, kx, z, w, h, '▲', showLegends, true);
        drawKey(ctx, projector, kx, z + h + 1.5, w, h, '▼', showLegends, true);
      } else {
        const small = label.length > 1 && !/[◀▶]/.test(label);
        drawKey(ctx, projector, kx, z, w, keySize, label, showLegends, small);
      }
      x += units * unit;
    }
  });
}

function drawKey(ctx, { base }, x, z, w, h, label, showLegend, small) {
  const quad = [base(x, z, 1), base(x + w, z, 1), base(x + w, z + h, 1), base(x, z + h, 1)];
  polygon(ctx, quad, '#2b2c30');
  if (!showLegend || !label) return;
  const [px, py] = base(x + w / 2, z + h * (small ? 0.6 : 0.62), 1);
  const [, top] = base(x, z, 1);
  const [, bottomY] = base(x, z + h, 1);
  const keyHeight = bottomY - top;
  ctx.fillStyle = '#d5d7dc';
  ctx.font = `${(small ? 0.32 : 0.5) * keyHeight}px ${FONT}`;
  ctx.textAlign = 'center';
  ctx.fillText(label, px, py);
}

function drawSpeakerGrilles(ctx, { base }, keyPixelSize) {
  const step = keyPixelSize >= 10 ? GRILLE.pitch : GRILLE.pitch * 2;
  const cols = Math.floor(GRILLE.width / step);
  const rowsCount = Math.floor(GRILLE.depth / step);
  ctx.fillStyle = '#9aa0a8';
  for (const side of [-1, 1]) {
    for (let c = 0; c < cols; c++) {
      for (let r = 0; r < rowsCount; r++) {
        const [x, y] = base(side * (GRILLE.inner + c * step + step / 2), GRILLE.back + r * step + step / 2, 0.2);
        ctx.fillRect(x - 0.25, y - 0.25, 0.5, 0.5);
      }
    }
  }
}

function drawTrackpad(ctx, { base }) {
  const hw = TRACKPAD.width / 2;
  const pad = roundedRectPoints(-hw, TRACKPAD.back, TRACKPAD.width, TRACKPAD.depth, TRACKPAD.radius, 4);
  polygon(ctx, pad.map(([x, z]) => base(x, z, 0.15)), '#d3d6db', '#b6bac1', 0.5);
}

/** Lid outline in lid coordinates (u up from the hinge). */
function lidOutline(inset = 0) {
  const hw = LID.width / 2 - inset;
  return roundedRectPoints(-hw, inset, hw * 2, LID.height - inset * 2, [LID.radiusTop, LID.radiusTop, LID.radiusBottom, LID.radiusBottom]).map(([x, u]) => [x, LID.height - u + inset * 0]);
}

/**
 * The lid's top edge (its 3.6 mm thickness). Only the top face can ever be
 * seen from a centred camera — the side faces point away — and only when the
 * lid leans back past vertical.
 */
function drawLidEdge(ctx, { lid }, angle) {
  if (angle <= 90) return;
  const hw = LID.width / 2;
  polygon(ctx, [lid(-hw, LID.height, 0), lid(hw, LID.height, 0), lid(hw, LID.height, -LID.thickness), lid(-hw, LID.height, -LID.thickness)], '#a3a7ad');
}

function drawBezel(ctx, { lid }) {
  ctx.lineJoin = 'round';
  polygon(ctx, lidOutline(0).map(([x, u]) => lid(x, u, 0)), '#9ea3a9'); // thin aluminium rim
  polygon(ctx, lidOutline(LID.rim).map(([x, u]) => lid(x, u, 0.2)), '#0b0c0e'); // black bezel
}

/** The display area in lid coordinates, with rounded top corners and square bottom corners. */
function displayPoints() {
  const hw = DISPLAY.width / 2;
  const r = DISPLAY.cornerRadius;
  const top = DISPLAY.bottom + DISPLAY.height;
  const points = [[-hw, DISPLAY.bottom], [hw, DISPLAY.bottom]];
  for (let i = 0; i <= 6; i++) {
    const a = (Math.PI / 2) * (i / 6);
    points.push([hw - r + r * Math.cos(a), top - r + r * Math.sin(a)]);
  }
  for (let i = 0; i <= 6; i++) {
    const a = Math.PI / 2 + (Math.PI / 2) * (i / 6);
    points.push([-hw + r + r * Math.cos(a), top - r + r * Math.sin(a)]);
  }
  return points;
}

/**
 * The desktop, folded. Strips start flat at the bottom of the display and
 * lean progressively further back toward the top; each is shaded by how far
 * it turns from the viewer and gets a soft sheen where it catches the light.
 */
function drawFoldedDesktop(ctx, projector, angle, preset, textures, pixel) {
  const { lid } = projector;
  const hw = DISPLAY.width / 2;
  const screen = displayPoints().map(([x, u]) => lid(x, u, 0.6));
  polygon(ctx, screen, '#050608');

  const fold = clamp((FLAT_ANGLE - angle) / FOLD_RANGE, 0, 1);
  const tilt = fold * MAX_TILT;
  const stripHeight = DISPLAY.height / STRIPS;
  const style = PRESETS[preset] ?? PRESETS.silk;
  const frostAlpha = style.frost * fold;

  ctx.save();
  polygon(ctx, screen);
  ctx.clip();
  ctx.imageSmoothingQuality = 'high';
  const bleed = pixel * 1.2;

  let u = DISPLAY.bottom;
  let depth = 0.6;
  for (let i = 0; i < STRIPS; i++) {
    const t = (i + 0.5) / STRIPS;
    const lean = tilt * (0.3 + 0.7 * Math.pow(t, 1.4));
    const nextU = u + stripHeight * Math.cos(lean);
    const nextDepth = depth - stripHeight * Math.sin(lean);
    const quad = [lid(-hw, u, depth), lid(hw, u, depth), lid(hw, nextU, nextDepth), lid(-hw, nextU, nextDepth)];
    // Every layer of a strip bleeds into its neighbours so anti-aliased edges never leave hairlines
    const [a, b, c, d] = quad;
    const overlap = [[a[0], a[1] + bleed], [b[0], b[1] + bleed], [c[0], c[1] - bleed], [d[0], d[1] - bleed]];
    // Texture row 0 is the top of the desktop; strip 0 is the bottom of the screen
    const v0 = 1 - i / STRIPS;
    const v1 = 1 - (i + 1) / STRIPS;

    drawStrip(ctx, textures.sharp, quad, overlap, v0, v1);
    if (frostAlpha > 0.01) {
      ctx.globalAlpha = frostAlpha;
      drawStrip(ctx, textures.frosted, quad, overlap, v0, v1);
      ctx.globalAlpha = 1;
    }

    const shade = (1 - Math.cos(lean)) * style.shade + t * fold * 0.13;
    if (shade > 0.002) polygon(ctx, overlap, `rgba(0,8,19,${clamp(shade, 0, 0.78)})`);
    const leanDeg = (lean * 180) / Math.PI;
    const sheen = Math.exp(-Math.pow((leanDeg - 28) / 16, 2)) * 0.1 * fold;
    if (sheen > 0.005) polygon(ctx, overlap, `rgba(210,244,255,${sheen})`);

    u = nextU;
    depth = nextDepth;
  }
  ctx.restore();
}

function drawNotch(ctx, { lid }) {
  const top = DISPLAY.bottom + DISPLAY.height;
  const hw = NOTCH.width / 2;
  const pts = roundedRectPoints(-hw, 0, NOTCH.width, NOTCH.height + 2, [0, 0, NOTCH.radius, NOTCH.radius], 4)
    .map(([x, v]) => lid(x, top + 2 - v, 0.7));
  polygon(ctx, pts, '#0b0c0e');
  const [cx, cy] = lid(0, top - NOTCH.height / 2, 0.8);
  ctx.fillStyle = '#1a2436';
  ctx.beginPath();
  ctx.arc(cx, cy, 0.9, 0, Math.PI * 2);
  ctx.fill();
}

// --- Motion blur ------------------------------------------------------------------------

let layer = null;

/** Offscreen canvas matching the main canvas, reused between frames. */
function screenLayer(width, height) {
  if (!layer) layer = document.createElement('canvas');
  if (layer.width !== width || layer.height !== height) {
    layer.width = width;
    layer.height = height;
  }
  return layer;
}

/**
 * Composite `source` onto `ctx` smeared vertically by ±radius pixels — a
 * multi-sample stand-in for the app's CIMotionBlur.
 */
function drawWithMotionBlur(ctx, source, radiusPx) {
  ctx.save();
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  if (radiusPx < 0.5) {
    ctx.drawImage(source, 0, 0);
  } else {
    const samples = clamp(Math.round(radiusPx / 1.5), 3, MAX_BLUR_SAMPLES);
    ctx.globalAlpha = 1 / samples;
    for (let i = 0; i < samples; i++) {
      const offset = (i / (samples - 1) - 0.5) * 2 * radiusPx;
      ctx.drawImage(source, 0, offset);
    }
  }
  ctx.restore();
}

// --- Frame --------------------------------------------------------------------------------

/**
 * Render one frame.
 *
 * @param {HTMLCanvasElement} canvas
 * @param {object} frame
 * @param {number} frame.angle        lid angle in degrees (30 closed-ish … 115 open)
 * @param {string} frame.preset       'silk' | 'shade' | 'frost'
 * @param {boolean} frame.dark        true on a dark background (deeper ground shadow)
 * @param {number} [frame.motionBlur] blur radius in app points (0–28), see APP_SCREEN_HEIGHT_PT
 * @param {{sharp: HTMLCanvasElement, frosted: HTMLCanvasElement}} frame.textures
 */
export function drawMacBook(canvas, { angle, preset, dark, motionBlur = 0, textures }) {
  const rect = canvas.getBoundingClientRect();
  if (!rect.width || !rect.height) return;

  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const width = Math.round(rect.width * dpr);
  const height = Math.round(rect.height * dpr);
  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width;
    canvas.height = height;
  }

  // Fit the drawing's fixed extents into the canvas with a small margin
  const margin = 0.03;
  const extentW = EXTENTS.maxX - EXTENTS.minX;
  const extentH = EXTENTS.maxY - EXTENTS.minY;
  const scale = Math.min((rect.width * (1 - margin * 2)) / extentW, (rect.height * (1 - margin * 2)) / extentH);
  const originX = rect.width / 2 - ((EXTENTS.minX + EXTENTS.maxX) / 2) * scale;
  const originY = rect.height / 2 - ((EXTENTS.minY + EXTENTS.maxY) / 2) * scale;
  const applyTransform = (c) => c.setTransform(dpr * scale, 0, 0, dpr * scale, originX * dpr, originY * dpr);

  const ctx = canvas.getContext('2d');
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.clearRect(0, 0, width, height);
  applyTransform(ctx);

  const projector = createProjector(angle);
  const keyPixelSize = KEYBOARD.keySize * scale;

  drawGroundShadow(ctx, projector, dark);
  drawBase(ctx, projector);
  drawKeyboard(ctx, projector, keyPixelSize);
  drawSpeakerGrilles(ctx, projector, keyPixelSize);
  drawTrackpad(ctx, projector);
  drawHinge(ctx, projector);
  drawLidEdge(ctx, projector, angle);
  drawBezel(ctx, projector);

  // The folded desktop is drawn to its own layer so it can be motion-blurred
  const screen = screenLayer(width, height);
  const sctx = screen.getContext('2d');
  sctx.setTransform(1, 0, 0, 1, 0, 0);
  sctx.clearRect(0, 0, width, height);
  applyTransform(sctx);
  drawFoldedDesktop(sctx, projector, angle, preset, textures, 1 / (scale * dpr));

  const radiusPx = (motionBlur / APP_SCREEN_HEIGHT_PT) * DISPLAY.height * scale * dpr;
  ctx.save();
  polygon(ctx, lidOutline(LID.rim).map(([x, u]) => projector.lid(x, u, 0.2))); // never smear past the bezel
  ctx.clip();
  drawWithMotionBlur(ctx, screen, radiusPx);
  ctx.restore();

  drawNotch(ctx, projector);
}
