/**
 * Styles section: one recorded take per style. Only the selected clip loads;
 * clips autoplay (muted) while the section is in view and pause when it isn't.
 * With reduced motion nothing autoplays — the active clip shows controls.
 */
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');

export function setupStyles() {
  const section = document.querySelector('#styles');
  if (!section) return;
  const clips = [...section.querySelectorAll('.style-clip')];
  const tabs = [...section.querySelectorAll('[role="tab"]')];
  const tablist = section.querySelector('[role="tablist"]');
  const caption = section.querySelector('#styles-caption');
  let inView = false;

  function attachSource(clip) {
    if (!clip.dataset.src || clip.querySelector('source')) return;
    const source = document.createElement('source');
    source.src = clip.dataset.src;
    source.type = 'video/mp4';
    clip.appendChild(source);
    clip.load();
  }

  function play(clip) {
    attachSource(clip);
    if (reducedMotion.matches || !inView) return;
    clip.play().catch(() => {});
  }

  function select(name, focus = false) {
    for (const tab of tabs) {
      const on = tab.dataset.style === name;
      tab.setAttribute('aria-selected', String(on));
      tab.tabIndex = on ? 0 : -1;
      if (on) {
        caption.textContent = tab.dataset.caption;
        if (focus) tab.focus();
      }
    }
    for (const clip of clips) {
      const on = clip.dataset.style === name;
      clip.classList.toggle('is-active', on);
      clip.controls = on && reducedMotion.matches;
      if (on) play(clip);
      else clip.pause();
    }
  }

  tabs.forEach((tab) => tab.addEventListener('click', () => select(tab.dataset.style)));
  tablist.addEventListener('keydown', (event) => {
    const step = { ArrowRight: 1, ArrowLeft: -1 }[event.key];
    if (!step) return;
    const current = tabs.findIndex((t) => t.getAttribute('aria-selected') === 'true');
    select(tabs[(current + step + tabs.length) % tabs.length].dataset.style, true);
    event.preventDefault();
  });

  new IntersectionObserver(
    ([entry]) => {
      inView = entry.isIntersecting;
      const active = clips.find((c) => c.classList.contains('is-active'));
      if (inView) play(active);
      else clips.forEach((c) => c.pause());
    },
    { threshold: 0.35 },
  ).observe(section);

  const selected = () => tabs.find((t) => t.getAttribute('aria-selected') === 'true')?.dataset.style ?? 'fold';
  select(selected());
  reducedMotion.addEventListener('change', () => select(selected()));
}
