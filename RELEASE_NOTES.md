## What's new in 1.2.1

**No more flicker at your working angle.** If the lid sat right around the *Clears at* angle, a degree of hinge flex from typing could make the effect pop in and out. The effect now needs the lid a few degrees below the threshold (and steady there, unless it's clearly closing) before it starts, lets go a degree under the threshold, and is already flat at that point — so a wobble never triggers it and there's no pop on the way out.

**A way back in when the icon is hidden.** On a notched MacBook, macOS hides menu bar items that don't fit. Open iFold Mac again — Spotlight, Launchpad, or double-click in Applications — and the settings window appears, Quit included.

## What's new in 1.2.0

**Seven styles.** Pick how the desktop goes as the lid comes down — *Style* in the menu bar popover:

- **Fold** — leans away from the hinge, curling toward the top (the original)
- **Curl** — the top edge rolls over and away, like a page curling toward the hinge
- **Genie** — drawn down into the hinge, the way windows minimize into the Dock
- **Notch** — pulled up into the notch (the real one, measured from the display) and back out when you open the lid
- **Cube** — one face of a cube turning with the lid
- **Scale** — shrinks toward the hinge and settles into the dark
- **Fade** — dims and drains of colour, like a display drifting to sleep

All seven ride the same spring, motion blur and frost; Silk / Shade / Frost are now *looks* you can layer on any style.

**Under the hood.** Genie and Notch use a per-pixel funnel (no stepping); each style only drives the strips it needs, so Fold costs what it did before and the rigid styles cost less. The overlay window now exists from launch so the capture stream always excludes it.
