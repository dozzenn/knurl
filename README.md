# MacroPad for macOS

A native macOS app for configuring cheap USB macro keypads — the same job the
Windows-only [rOzzy1987/MacroPad](https://github.com/rOzzy1987/MacroPad) does,
rewritten in Swift/SwiftUI on top of IOKit HID.

No installer, no drivers, no `hidapi`. Just `MacroPad.app`.

## What it does

* Auto-detects the pad's vendor-defined HID configuration interface
* Maps each button and each knob action (turn left / press / turn right) to:
  * a **key sequence** with modifiers, recorded live or picked from a list
  * a **media key** (play/pause, volume, and more)
  * a **mouse action** (clicks, scroll) with held modifiers
* Multi-layer support on devices that have layers
* LED mode and colour
* Per-control upload, or upload the whole profile at once
* Profiles saved as JSON
* A live HID log showing the exact bytes on the wire

## Build

```bash
./scripts/build-app.sh
open build/MacroPad.app
```

Requires the Xcode command line tools. The result is `build/MacroPad.app`.

There is also a diagnostic CLI:

```bash
swift build
.build/debug/macropad-probe list     # show candidate configuration interfaces
.build/debug/macropad-probe probe    # open the pad, test each report id/channel
.build/debug/macropad-probe listen   # dump input reports from the pad
```

## First run

1. Plug in the pad and open the app. The device menu in the toolbar should
   already show it; a green dot means connected.
2. Click a button (or a knob's ↺ / ⏺ / ↻ segment) in the pad view.
3. In the inspector, hit **Record** and type the shortcut. Keys typed while
   recording are captured, not executed.
4. Press **Upload** (⌘U) to write that one control, or **Upload all** (⇧⌘U) for
   the whole profile.

## If uploads are accepted but nothing changes

These pads come in two protocol families and the difference is not detectable
from the descriptor, so the app makes a best guess and lets you correct it.
Open **Settings** (⌘,) and try, in order:

1. **Frame format** — switch between Extended and Legacy
2. **Channel** — switch between Output report and Feature report
3. **Report id** — 0 for devices whose descriptor declares no report ids,
   otherwise 2 or 3

Turn on the HID log at the bottom of the window to watch what is sent. A `→`
line in red means macOS rejected the write; a red-free line that changes nothing
means the device took the frame but did not understand it, which is the signal
to try the next setting above.

## Protocol notes

Both wire formats are ported from the original project.

**Extended** — one 64-byte frame per mapping:

```
FE <action> <layer> <type> <delayLo> <delayHi> 00 00 00 <count> <payload…>
```

`type` is 1 = keys, 2 = media/mouse, 8 = LED. `action` is 1–12 for buttons and
13–21 for knob actions. The key payload is a sequence of `<modifiers> <usage>`
pairs using standard HID keyboard usage ids.

**Legacy** — several frames per mapping, bracketed by an optional layer-select
frame (`A1 <layer>`) and a flash-write frame (`AA AA`). Frame 0 announces the
sequence length, frames 1..n carry one keystroke each.

The one deliberate deviation from the original: keypad Enter is sent as HID
usage `0x58` rather than `0x64`, and non-US backslash as `0x64`, which is what
the USB HID usage tables actually specify.

## Known devices

| VID:PID | Interface | Protocol |
|---|---|---|
| 1189:8840 | 1 | Extended |
| 1189:8890 | 1 | Legacy |
| 1189:8830–8833 | 0 | Extended |
| 1189:8810 | 0 | Extended |
| 6D7B:DCFA (SDINNOVATION SIDE-KEYBOARD) | 2 | Extended |

Any other pad is still found automatically: the app looks for a HID interface
on a vendor-defined usage page (≥ 0xFF00) with 64-byte reports, belonging to a
device that also exposes a keyboard interface. Turn on **Show all HID
interfaces** in the device menu to pick one by hand.

## Layout

`Sources/MacroPadCore` holds everything device-related — the two report
composers, the IOKit transport, the HID usage tables, the pad layouts.
`Sources/MacroPadApp` is the SwiftUI front end. `Sources/macropad-probe` is the
CLI.

## Licence

The protocol is derived from rOzzy1987/MacroPad, which is GPL-3.0. This
reimplementation follows the same licence.
