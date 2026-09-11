/**
 * iFold site entry point.
 *
 *  - Hero: the MacBook's lid follows scroll progress through the sticky section.
 *  - Playground: a slider and presets drive a second MacBook by hand.
 *  - Both can "replay" a scripted close-and-open.
 */

import { createDesktopTexture, createFrostedTexture } from './desktop-texture.js';
import { FoldView, Animator, OPEN_ANGLE, reducedMotion } from './fold-view.js';
import { setupDialogs } from './dialogs.js';

const clamp = (n, min, max) => Math.max(min, Math.min(max, n));
const smoothstep = (t) => t * t * (3 - 2 * t);

/** How far the hero lid drops when the section is fully scrolled. */
const HERO_DROP = 62;

const sharp = createDesktopTexture();
const textures = { sharp, frosted: createFrostedTexture(sharp) };

const hero = document.querySelector('.hero');
const heroCopy = document.querySelector('.hero-copy');
const stage = document.querySelector('.product-stage');
const angleInput = document.querySelector('#angle');
const angleNumber = document.querySelector('#angle-number');

// --- Views -----------------------------------------------------------------

const heroView = new FoldView(document.querySelector('#hero-canvas'), { angle: OPEN_ANGLE, dark: false });
heroView.restingTarget = scrollAngle;

const demoView = new FoldView(document.querySelector('#demo-canvas'), {
  angle: Number(angleInput.value),
  dark: true,
  onAngle: (angle) => {
    angleInput.value = Math.round(angle);
    updateReadout(angle);
  },
});
demoView.restingTarget = () => Number(angleInput.value);
demoView.visible = false; // until it scrolls into view

const animator = new Animator([heroView, demoView], textures);

// --- Hero scroll -----------------------------------------------------------

function scrollProgress() {
  const { top } = hero.getBoundingClientRect();
  return clamp(-top / Math.max(1, hero.offsetHeight - window.innerHeight), 0, 1);
}

function scrollAngle() {
  return reducedMotion.matches ? OPEN_ANGLE : OPEN_ANGLE - smoothstep(scrollProgress()) * HERO_DROP;
}

function updateScroll() {
  const p = scrollProgress();
  if (!heroView.isReplaying) heroView.target = scrollAngle();

  if (reducedMotion.matches) {
    heroCopy.style.opacity = '1';
    heroCopy.style.transform = 'none';
    stage.style.transform = 'none';
  } else {
    heroCopy.style.opacity = String(1 - clamp(p * 1.9, 0, 0.96));
    heroCopy.style.transform = `translateY(${-p * 80}px)`;
    stage.style.transform = `translateY(${-p * 80}px) scale(${1 + p * 0.12})`;
  }
  animator.wake();
}

window.addEventListener('scroll', updateScroll, { passive: true });
window.addEventListener('resize', () => animator.wake(), { passive: true });
new ResizeObserver(() => animator.wake()).observe(stage);

// Only draw canvases that are on screen
const visibility = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      const view = animator.views.find((v) => v.canvas === entry.target);
      if (view) view.visible = entry.isIntersecting;
    }
    animator.wake();
  },
  { rootMargin: '100px' },
);
animator.views.forEach((view) => visibility.observe(view.canvas));

// --- Playground controls ---------------------------------------------------

function updateReadout(angle) {
  const rounded = Math.round(angle);
  angleNumber.textContent = rounded;
  angleInput.setAttribute('aria-valuetext', `${rounded} degrees`);
}

angleInput.addEventListener('input', () => {
  demoView.setTarget(Number(angleInput.value));
  updateReadout(angleInput.value);
  animator.wake();
});

const presetButtons = document.querySelectorAll('[data-preset]');
presetButtons.forEach((button) =>
  button.addEventListener('click', () => {
    presetButtons.forEach((b) => b.setAttribute('aria-pressed', String(b === button)));
    demoView.preset = button.dataset.preset;
    animator.wake();
  }),
);

document.querySelector('#hero-replay').addEventListener('click', () => {
  heroView.replay(performance.now());
  animator.wake();
});
document.querySelector('#demo-replay').addEventListener('click', () => {
  demoView.replay(performance.now());
  animator.wake();
});

reducedMotion.addEventListener('change', () => {
  animator.views.forEach((view) => view.cancelReplay());
  updateScroll();
});

// --- Go --------------------------------------------------------------------

setupDialogs();
updateScroll();
animator.wake();
