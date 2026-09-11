/**
 * Paints a fictional macOS-style desktop onto an offscreen canvas.
 *
 * The texture is mapped onto the folding screen of the MacBook illustration.
 * It is deliberately invented (no real app screenshots, no private content).
 */

export const TEXTURE_WIDTH = 1700;
export const TEXTURE_HEIGHT = 1060;

const FONT = 'Helvetica Neue, sans-serif';

/** Fill (and optionally stroke) a rounded rectangle. */
function roundedRect(ctx, x, y, w, h, radius, fill, stroke) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, radius);
  if (fill) {
    ctx.fillStyle = fill;
    ctx.fill();
  }
  if (stroke) {
    ctx.strokeStyle = stroke;
    ctx.stroke();
  }
}

function text(ctx, str, x, y, font, color, align = 'left') {
  ctx.font = font;
  ctx.fillStyle = color;
  ctx.textAlign = align;
  ctx.fillText(str, x, y);
  ctx.textAlign = 'left';
}

/** Abstract silk wallpaper: overlapping teal ribbons on a deep-blue gradient. */
function paintWallpaper(ctx, w, h) {
  const base = ctx.createLinearGradient(0, 0, w, h);
  base.addColorStop(0, '#082b48');
  base.addColorStop(0.42, '#146d91');
  base.addColorStop(1, '#64c2c9');
  ctx.fillStyle = base;
  ctx.fillRect(0, 0, w, h);

  for (let i = 0; i < 8; i++) {
    const x = i * 170 - 520;
    const ribbon = ctx.createLinearGradient(x, 0, x + 950, h);
    ribbon.addColorStop(0, i % 2 ? '#0b3858' : '#2c92af');
    ribbon.addColorStop(0.48, i % 2 ? '#408fa3' : '#9bdddf');
    ribbon.addColorStop(0.59, '#65b1c1');
    ribbon.addColorStop(0.67, '#196385');
    ribbon.addColorStop(1, '#103954');
    ctx.fillStyle = ribbon;
    ctx.beginPath();
    ctx.moveTo(x, -50);
    ctx.bezierCurveTo(x + 1150, 65, x - 450, 760, x + 1000, 1160);
    ctx.lineTo(x + 1330, 1160);
    ctx.bezierCurveTo(x - 20, 700, x + 1350, 210, x + 270, -50);
    ctx.closePath();
    ctx.fill();
  }
}

function paintMenuBar(ctx, w) {
  ctx.fillStyle = '#072b4160';
  ctx.fillRect(0, 0, w, 35);
  text(ctx, '●', 24, 24, `600 17px ${FONT}`, '#f4f8fb');
  text(ctx, 'Finder', 68, 24, `600 17px ${FONT}`, '#f4f8fb');
  text(ctx, 'File    Edit    View    Go    Window    Help', 150, 24, `16px ${FONT}`, '#f4f8fb');
  text(ctx, '◉   ◇   ▰     Thu  9:41 AM', 1440, 24, `16px ${FONT}`, '#f4f8fb');
}

function paintFinderWindow(ctx) {
  // Window body with a soft drop shadow
  ctx.save();
  ctx.shadowColor = '#00203370';
  ctx.shadowBlur = 38;
  ctx.shadowOffsetY = 20;
  roundedRect(ctx, 300, 212, 875, 562, 16, '#f3f5f7');
  ctx.restore();

  // Sidebar + toolbar
  roundedRect(ctx, 300, 212, 205, 562, [16, 0, 0, 16], '#e3eaf0');
  roundedRect(ctx, 505, 212, 670, 63, [0, 16, 0, 0], '#edf0f3');
  ['#ff6059', '#ffbd2e', '#28c840'].forEach((color, i) => {
    ctx.beginPath();
    ctx.arc(327 + i * 24, 240, 7, 0, Math.PI * 2);
    ctx.fillStyle = color;
    ctx.fill();
  });
  text(ctx, '‹   ›     A little inspiration', 530, 251, `600 19px ${FONT}`, '#53616e');

  // Sidebar items
  text(ctx, 'Favorites', 323, 296, `16px ${FONT}`, '#85919c');
  const items = ['AirDrop', 'Recents', 'Applications', 'Desktop', 'Documents', 'Downloads'];
  const glyphs = ['◎', '◷', '⌘', '▣', '▤', '↓'];
  items.forEach((label, i) => {
    if (i === 3) roundedRect(ctx, 313, 419, 180, 35, 6, '#c4d5e5'); // selected row
    text(ctx, glyphs[i], 325, 333 + i * 34, `19px ${FONT}`, '#4389b8');
    text(ctx, label, 352, 332 + i * 34, `16px ${FONT}`, '#4a5a68');
  });

  // Folders
  ['Ideas', 'Weekends', 'Good things'].forEach((name, i) => {
    const x = 570 + i * 188;
    roundedRect(ctx, x, 331, 43, 21, 5, '#63b8e1');
    roundedRect(ctx, x, 342, 103, 72, 6, '#7acdf0');
    const front = ctx.createLinearGradient(0, 350, 0, 414);
    front.addColorStop(0, '#b1e7fa');
    front.addColorStop(1, '#6bc2ec');
    roundedRect(ctx, x, 355, 103, 59, 5, front);
    text(ctx, name, x + 51, 445, `17px ${FONT}`, '#495a68', 'center');
  });

  // A pinned note
  roundedRect(ctx, 567, 494, 480, 176, 7, '#e2e8ec');
  text(ctx, 'A NOTE TO SELF', 597, 532, `500 16px ${FONT}`, '#90a5b4');
  text(ctx, 'Leave room for a little magic.', 597, 585, `500 35px ${FONT}`, '#3f5969');
  text(ctx, 'Even in the everyday.', 597, 625, `18px ${FONT}`, '#788e9b');
}

function paintNowPlaying(ctx) {
  ctx.save();
  ctx.shadowColor = '#08253855';
  ctx.shadowBlur = 28;
  ctx.shadowOffsetY = 12;
  roundedRect(ctx, 1070, 560, 363, 245, 20, '#fbfbfce8');
  ctx.restore();

  const art = ctx.createLinearGradient(1090, 580, 1210, 700);
  art.addColorStop(0, '#f7d4a2');
  art.addColorStop(0.5, '#d68159');
  art.addColorStop(1, '#8b382f');
  roundedRect(ctx, 1094, 584, 99, 99, 10, art);
  ctx.strokeStyle = '#f2cf9b';
  ctx.lineWidth = 2;
  for (let i = 0; i < 8; i++) {
    ctx.beginPath();
    ctx.arc(1144, 634, 9 + i * 6, 0, Math.PI * 2);
    ctx.stroke();
  }

  text(ctx, 'Slow mornings', 1213, 622, `600 19px ${FONT}`, '#293c48');
  text(ctx, 'A moment to unwind', 1213, 651, `16px ${FONT}`, '#7c858c');
  text(ctx, '◀   Ⅱ   ▶', 1168, 732, `26px ${FONT}`, '#59646e');
  roundedRect(ctx, 1100, 764, 296, 3, 2, '#cbd1d7');
  roundedRect(ctx, 1100, 764, 136, 3, 2, '#697b89');
}

function paintDock(ctx) {
  roundedRect(ctx, 515, 939, 670, 92, 23, '#d2e7ef75', '#effbff50');
  const colors = ['#379bdf', '#f5f9fc', '#eb625a', '#f2b334', '#8db6d4', '#f5798c', '#2e3b4e', '#9da9b5'];
  const glyphs = ['☺', '◉', '12', '▤', '✉', '♫', '⌘', '⚙'];
  colors.forEach((color, i) => {
    roundedRect(ctx, 532 + i * 81, 952, 65, 65, 14, color);
    text(ctx, glyphs[i], 564 + i * 81, 997, `500 35px ${FONT}`, i === 1 ? '#429dcd' : '#fff', 'center');
  });
}

/** @returns {HTMLCanvasElement} the sharp desktop texture */
export function createDesktopTexture() {
  const canvas = document.createElement('canvas');
  canvas.width = TEXTURE_WIDTH;
  canvas.height = TEXTURE_HEIGHT;
  const ctx = canvas.getContext('2d');
  paintWallpaper(ctx, TEXTURE_WIDTH, TEXTURE_HEIGHT);
  paintMenuBar(ctx, TEXTURE_WIDTH);
  paintFinderWindow(ctx);
  paintNowPlaying(ctx);
  paintDock(ctx);
  return canvas;
}

/**
 * A softened copy of the texture for the Frost preset.
 *
 * Repeated halving and doubling through bilinear scaling approximates a
 * gaussian blur without `ctx.filter`, which Safari does not support.
 *
 * @returns {HTMLCanvasElement} half-resolution blurred texture
 */
export function createFrostedTexture(source) {
  const scaleTo = (image, width, height) => {
    const c = document.createElement('canvas');
    c.width = width;
    c.height = height;
    c.getContext('2d').drawImage(image, 0, 0, width, height);
    return c;
  };
  let w = source.width;
  let h = source.height;
  let image = source;
  for (let i = 0; i < 4; i++) {
    w = Math.round(w / 2);
    h = Math.round(h / 2);
    image = scaleTo(image, w, h);
  }
  for (let i = 0; i < 3; i++) {
    w *= 2;
    h *= 2;
    image = scaleTo(image, w, h);
  }
  return image;
}
