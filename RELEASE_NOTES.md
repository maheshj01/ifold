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
