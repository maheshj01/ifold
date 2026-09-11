# iFold

iPhone Duo's fold, for the MacBook lid you already have.

iFold reads the hinge angle from your MacBook's built-in lid sensor and bends
your live desktop as the lid comes down: the picture tilts away in perspective
(so it "holds its place" in space), blurs and shades, then springs flat with a
soft click when you open the lid past the clear angle.

## Requirements

- Apple silicon MacBook with a lid-angle sensor (M2 Air and later, 14"/16" Pro).
- macOS 14 Sonoma or later.
- **Screen Recording** permission — the desktop is captured with ScreenCaptureKit.
  Frames never leave the GPU; nothing is saved or uploaded.

## Build & run

```bash
./build.sh --run        # build, assemble build/iFold.app, launch
./build.sh --install    # same, then copy to /Applications
```

On first launch macOS asks for Screen Recording. Grant it under
**System Settings → Privacy & Security → Screen & System Audio Recording**,
then relaunch (the menu bar popover has a Relaunch button).

## Using it

iFold lives in the menu bar (laptop icon). The popover shows the live hinge
angle and lets you tune:

| Control      | What it does                                                         |
|--------------|----------------------------------------------------------------------|
| Follow lid / Manual | Track the real hinge, or drag the angle yourself to preview.  |
| Clears at    | Hinge angle at which the desktop is flat again (default 100°).        |
| Perspective  | How far the picture leans per degree of lid travel.                   |
| Bend         | 0 = rigid plank hinged at the bottom, 100 = flat at the hinge, curling toward the top. |
| Motion blur  | Directional smear while the lid is moving; crisp once it settles.     |
| Frost        | Static blur that builds as the lid comes down.                        |
| Shade        | Lighting falloff on the parts of the sheet facing away.               |
| Silk / Shade / Frost | Presets.                                                      |

Click anywhere on the bent desktop to pause until the lid opens again.

## Privacy & security posture

- **On device, in GPU memory only.** Captured frames are IOSurfaces handed
  straight to Core Animation. Nothing is encoded, written to disk, or sent
  anywhere — the binary links no networking framework and opens no sockets.
- **No entitlements, hardened runtime.** Not sandboxed (the lid sensor and
  ScreenCaptureKit need that), but no Input Monitoring, Accessibility,
  camera, microphone, or file-system grants are requested. The HID match is
  pinned to the lid sensor (VID 0x05AC / PID 0x8104 / Sensor·Orientation); it
  cannot see keyboard or trackpad traffic.
- **Frames are dropped on sleep, display sleep, screen lock and fast user
  switch**, and the capture stream stops. The overlay never outlives the
  session it was captured in.
- **The overlay only captures your own display**, with iFold's own windows
  excluded, and it is itself invisible to other screen recorders
  (`sharingType = .none`).
- **Developer snapshot hook is compiled out.** `./build.sh --debug-tools`
  adds a Darwin-notification-triggered screenshot for debugging renders; it is
  intentionally absent from normal builds because it would let any local
  process borrow iFold's Screen Recording grant.
- **Distribution note.** `build.sh` signs with your Apple Development identity,
  which is fine for your own Macs. To hand the app to anyone else, sign with
  Developer ID and notarize, or Gatekeeper will refuse it.

Known limitation: while the desktop is bent, the overlay sits above every
other window (like Bendy). A system dialog that appears at that moment is
underneath it until you click (pause) or open the lid.

## Performance

Measured on an M4 MacBook Pro 14":

| State | iFold CPU | RSS | Notes |
|---|---|---|---|
| Idle, lid parked | ~1.5% | ~70 MB (mostly shared framework pages) | 30 Hz sensor poll + 20 Hz display link; capture stopped; no measurable WindowServer load |
| Bending | ~30% | +~2 MB | ScreenCaptureKit at 60 fps full Retina; frames live in ~5 IOSurfaces (GPU); WindowServer +~10–15% for the composite |

The capture stream starts only when the lid is actually closing toward the
threshold (startup ≈ 130 ms) and stops 3 s after the desktop clears, so a lid
resting at a normal working angle costs nothing beyond the idle poll.

## Debugging

Logs go to the unified log under subsystem `com.mahesh.ifold`
(note: `log` is a zsh builtin, use the full path):

```bash
/usr/bin/log stream --predicate 'subsystem == "com.mahesh.ifold"' --info
```

To see exactly what the overlay renders, ask the running app for a screenshot
of the built-in display *including* its own window:

```bash
defaults write com.mahesh.ifold snapshotPath ~/Desktop/ifold.png && notifyutil -p com.mahesh.ifold.snapshot
```

## How it works

- `LidAngleSensor` — reads HID feature report #1 from the Apple sensor hub
  (VID 0x05AC, PID 0x8104, Sensor/Orientation usage). Public IOKit only.
- `ScreenCapturer` — ScreenCaptureKit stream of the built-in display,
  excluding iFold's own windows.
- `FoldView` — the desktop as a flexible sheet: 18 horizontal strips
  (IOSurface contents + `contentsRect`) chained end to end and rotated
  progressively so the surface curves away from the hinge, under a perspective
  `sublayerTransform`. Each strip carries a Lambert-style shade gradient and a
  specular sheen band. A `CIMotionBlur` on the container smears the projected
  sheet in screen space while it moves. Zero copies — frames are IOSurfaces set
  straight as layer contents.
- `FoldController` — idle → engaged → releasing state machine, driven by the
  display's `CADisplayLink` (120 Hz on ProMotion). The lean follows the hinge
  through a second-order spring (a touch of inertia, a whisper of overshoot);
  motion-blur radius is derived from the spring's velocity with a fast attack
  and slow release so the picture smears the instant it moves and resolves as
  it settles. Pre-warms the capture stream as the lid nears the threshold so
  the bend starts without a black flash; releases through the same spring and
  stops the stream once flat.
