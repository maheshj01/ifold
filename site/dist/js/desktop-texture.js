/**
 * The desktop shown on the MacBook's screen: a real macOS screenshot, loaded
 * as an image, plus a softened copy for the Frost preset.
 */

const SOURCES = ['assets/desktop.webp', 'assets/desktop.jpg'];

function loadImage(src) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.decoding = 'async';
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error(`Could not load ${src}`));
    image.src = src;
  });
}

/** Try each source in turn (WebP first, JPEG as the fallback). */
async function loadFirst(sources) {
  let lastError;
  for (const src of sources) {
    try {
      return await loadImage(src);
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
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

/**
 * Load the desktop and prepare both variants the renderer needs.
 * @returns {Promise<{sharp: HTMLImageElement, frosted: HTMLCanvasElement}>}
 */
export async function loadDesktopTextures() {
  const sharp = await loadFirst(SOURCES);
  return { sharp, frosted: createFrostedTexture(sharp) };
}
