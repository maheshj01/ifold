/**
 * Animation state for one MacBook canvas: a target lid angle, a spring that
 * chases it, an optional scripted "replay", and a shared rAF loop.
 */

import { drawMacBook } from './macbook.js';

const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

export const OPEN_ANGLE = 108;
const REPLAY_SECONDS = 4.8;
const REPLAY_DEPTH = 65; // degrees the lid drops during a replay

/**
 * Second-order spring, ported from the macOS app's `Spring`: the picture carries
 * a little inertia behind the hinge and settles with a whisper of overshoot.
 */
const SPRING_RESPONSE = 0.32; // seconds to reach the target, roughly
const SPRING_DAMPING = 0.82; // < 1 → slight overshoot

/**
 * Motion blur, also ported from the app: the smear scales with angular speed
 * (deg/s), attacks fast so the first moment of motion smears, and releases
 * slowly so the picture "resolves" as it settles. Radius is in app points.
 */
const BLUR_PER_DEG_PER_SEC = 0.12;
const MAX_MOTION_BLUR = 28;
const BLUR_ATTACK = 0.03;
const BLUR_RELEASE = 0.14;

export class FoldView {
  /**
   * @param {HTMLCanvasElement} canvas
   * @param {{ angle: number, dark: boolean, onAngle?: (angle: number) => void }} options
   *   `onAngle` fires while a replay drives the angle, so controls can follow.
   */
  constructor(canvas, { angle, dark, onAngle }) {
    this.canvas = canvas;
    this.dark = dark;
    this.onAngle = onAngle;
    this.angle = angle;
    this.target = angle;
    this.velocity = 0;
    this.motionBlur = 0;
    this.preset = 'silk';
    this.visible = true;
    this.replayStart = null;
    /** Angle to return to once a replay finishes. */
    this.restingTarget = () => angle;
  }

  get isReplaying() {
    return this.replayStart !== null;
  }

  setTarget(angle) {
    this.replayStart = null;
    this.target = angle;
  }

  /** Close the lid and open it again over a few seconds. */
  replay(now) {
    if (reducedMotion.matches) {
      // No animation: toggle between two discrete states instead
      this.target = this.target < 80 ? OPEN_ANGLE : 50;
      this.onAngle?.(this.target);
      return;
    }
    this.replayStart = now;
  }

  cancelReplay() {
    this.replayStart = null;
  }

  /**
   * Advance the simulation.
   * @returns {boolean} true while still moving
   */
  step(now, dt) {
    if (this.isReplaying) {
      const t = (now - this.replayStart) / 1000;
      if (t > REPLAY_SECONDS) {
        this.replayStart = null;
        this.target = this.restingTarget();
      } else {
        this.target = OPEN_ANGLE - REPLAY_DEPTH * Math.sin((Math.PI * t) / REPLAY_SECONDS) ** 2;
        this.onAngle?.(this.target);
      }
    }

    if (reducedMotion.matches) {
      this.angle = this.target;
      this.velocity = 0;
      this.motionBlur = 0;
      return false;
    }

    const diff = this.target - this.angle;
    const moving = Math.abs(diff) > 0.05 || Math.abs(this.velocity) > 1.5;
    if (moving) {
      const w = (2 * Math.PI) / SPRING_RESPONSE;
      const acceleration = w * w * diff - 2 * SPRING_DAMPING * w * this.velocity;
      this.velocity += acceleration * dt;
      this.angle += this.velocity * dt;
    } else {
      this.velocity = 0;
    }

    const wanted = Math.min(MAX_MOTION_BLUR, Math.abs(this.velocity) * BLUR_PER_DEG_PER_SEC);
    const k = wanted > this.motionBlur ? 1 - Math.exp(-dt / BLUR_ATTACK) : 1 - Math.exp(-dt / BLUR_RELEASE);
    this.motionBlur += (wanted - this.motionBlur) * k;
    if (this.motionBlur < 0.2) this.motionBlur = 0;

    return moving || this.isReplaying || this.motionBlur > 0;
  }

  render(textures) {
    drawMacBook(this.canvas, {
      angle: this.angle,
      preset: this.preset,
      dark: this.dark,
      motionBlur: this.motionBlur,
      textures,
    });
  }
}

/**
 * One requestAnimationFrame loop shared by every view. It runs only while
 * something is moving or a redraw was requested, then goes idle.
 */
export class Animator {
  constructor(views, textures) {
    this.views = views;
    this.textures = textures;
    this.frame = 0;
    this.lastTime = 0;
    this.dirty = true;
    this.tick = this.tick.bind(this);
  }

  /** Request a redraw (and keep animating if anything is in motion). */
  wake() {
    this.dirty = true;
    if (!this.frame) this.frame = requestAnimationFrame(this.tick);
  }

  tick(now) {
    this.frame = 0;
    const dt = Math.min((now - this.lastTime) / 1000 || 1 / 60, 0.033);
    this.lastTime = now;

    let ongoing = false;
    for (const view of this.views) {
      const moving = view.step(now, dt);
      ongoing ||= moving;
      if (view.visible && (this.dirty || moving)) view.render(this.textures);
    }
    this.dirty = false;
    if (ongoing) this.frame = requestAnimationFrame(this.tick);
  }
}

export { reducedMotion };
