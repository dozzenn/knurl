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
.build/debug/macropad-probe list        # candidate configuration interfaces
.build/debug/macropad-probe interfaces  # every HID interface, keyboards included
.build/debug/macropad-probe info        # ask a WebHub device to describe itself
.build/debug/macropad-probe readkeys 0  # dump the key table for a layer
.build/debug/macropad-probe setkey 0 0 32 00 1D 00   # index, layer, type, c1, c2, c3
.build/debug/macropad-probe sniff 6D7B DCFA 60       # watch what the pad emits
```

`info`, `readkeys`, `interfaces` and `sniff` only read; `setkey` writes.

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

Three wire formats are supported. Two are ported from the original project; the
third was reverse engineered for this app.

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

**WebHub (SDCX / Huali family)** — used by pads that the vendor configures with
its browser-based WebHID tool at huali-tech.com / sdcx-tech.com. Frames are 64
bytes on report id 0; byte 0 is always `06` and byte 1 the sub-command:

| Frame | Meaning |
|---|---|
| `06 05` | read device info — replies `AA 05 <len> …` with pid, firmware, profile and layer counts |
| `06 08 3A <offLo> <offHi> 00 <layer>` | read a 56-byte block of the key table |
| `06 10 07 <offLo> <offHi> 00 <layer> 00 <type> <c1> <c2> <c3>` | write one key, offset = `4 × keyIndex` |
| `06 09 <len> <offLo> <offHi> 00 <layer> 00 …` | write a block of entries |
| `06 0F FF` | factory reset |
| `06 FB <n>` | select stored profile |

Each key is four bytes, `[type, code1, code2, code3]`. Types: `0x13` disabled,
`0x20` a standard key (`code1` = HID modifier mask, `code2` = HID usage),
`0x30` a consumer key (`code1`/`code2` = little-endian consumer usage), `0x11`
mouse move, `0x60` macro, `0x80` open a website, `0xFF` custom combination.
Buttons occupy table indices 0–15; each knob owns three consecutive slots from
16 (press, then the two rotations).

Not yet implemented for this family: mouse actions, backlight, and multi-key
macros — macros live in a separate table addressed by its own commands. The app
refuses to write those rather than guessing at the encoding.

Note that sub-command `0x5A` on this family jumps the device into its bootloader,
which is why blind command sweeping is a bad way to explore it.

The one deliberate deviation from the original two protocols: keypad Enter is
sent as HID usage `0x58` rather than `0x64`, and non-US backslash as `0x64`,
which is what the USB HID usage tables actually specify.

## Known devices

| VID:PID | Interface | Protocol |
|---|---|---|
| 1189:8840 | 1 | Extended |
| 1189:8890 | 1 | Legacy |
| 1189:8830–8833 | 0 | Extended |
| 1189:8810 | 0 | Extended |
| 6D7B:DCFA (SDINNOVATION SIDE-KEYBOARD) | 2 | WebHub |
| 6D7C:DCFB, 6D7D:DCFC, 6D7E:DCFD, 6D7F:DCFE, 68BD:DCFC | 2 | WebHub |

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
