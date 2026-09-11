/**
 * Native <dialog> wiring: open buttons, close buttons, click-outside-to-close,
 * body scroll lock, and the copy-to-clipboard buttons ([data-copy]) in the setup dialog.
 */

function isOutside(dialog, event) {
  const r = dialog.getBoundingClientRect();
  return event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom;
}

function openDialog(dialog) {
  dialog.showModal();
  document.body.classList.add('modal-open');
  const video = dialog.querySelector('video');
  if (video) {
    video.currentTime = 0;
    video.play().catch(() => {}); // autoplay with sound can be refused; controls remain
  }
}

export function setupDialogs() {
  const openers = [
    ['#nav-download', '#setup-dialog'],
    ['#get-download', '#setup-dialog'],
    ['#view-video', '#video-dialog'],
  ];
  for (const [buttonSelector, dialogSelector] of openers) {
    const dialog = document.querySelector(dialogSelector);
    document.querySelector(buttonSelector).addEventListener('click', () => openDialog(dialog));
  }

  for (const dialog of document.querySelectorAll('dialog')) {
    dialog.querySelector('.dialog-close').addEventListener('click', () => dialog.close());
    dialog.addEventListener('close', () => {
      document.body.classList.remove('modal-open');
      dialog.querySelector('video')?.pause();
    });
    dialog.addEventListener('click', (event) => {
      if (event.target === dialog && isOutside(dialog, event)) dialog.close();
    });
  }

  for (const button of document.querySelectorAll('[data-copy]')) setupCopyButton(button, button.dataset.copy);
}

function setupCopyButton(button, command) {
  button.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(command);
      button.textContent = 'Copied';
    } catch {
      button.textContent = 'Select to copy';
    }
    setTimeout(() => (button.textContent = 'Copy'), 2000);
  });
}
