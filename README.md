# Knurl

*Knurling is the milled ridging on a knob — the texture that tells your fingers
there is something to turn.*

A native macOS app for configuring cheap USB macro keypads. It began as a port
of the Windows-only [rOzzy1987/MacroPad](https://github.com/rOzzy1987/MacroPad),
rewritten in Swift/SwiftUI on top of IOKit HID, and grew a third wire protocol
that project does not cover.

No installer, no drivers, no `hidapi`. Just `Knurl.app`.

## Install

Download `Knurl.zip` from [Releases](../../releases), unzip it, and move
`Knurl.app` to your Applications folder.

**The first launch needs one extra step.** Knurl is not signed with an Apple
Developer ID — that needs a paid account — so macOS will refuse to open it and
say it is damaged or from an unidentified developer. It is neither; the message
is what macOS says about any app it cannot check a signature for.

Right-click the app and choose **Open**, then **Open** again in the dialog. You
only have to do this once. If macOS still refuses, run:

```bash
xattr -dr com.apple.quarantine /Applications/Knurl.app
```

That removes the quarantine flag the browser attached to the download. Do not
run that on software you have not decided to trust — here, you can read every
line of what you are running in this repository, and build it yourself with
`./scripts/build-app.sh` if you would rather not take the binary.

## What it does

* Templates that fill the whole pad at once — music, clipboard, design, video
  editing, screenshots, browser tabs
* Global keys plus per-app overrides — the keypad follows whichever app is in front

* Lives in the menu bar, with one-click switching between key sets

* Auto-detects the pad's vendor-defined HID configuration interface
* Maps each button and each knob action (turn left / press / turn right) to:
  * a **key sequence** with modifiers, recorded live or picked from a list
  * a **media key** (play/pause, volume, and more)
  * a **mouse action** (clicks, scroll) with held modifiers
* Multi-layer support on devices that have layers
* Backlight: effect, speed and colour, read from the keypad and written back live
* Light and dark, switched from the bottom of the sidebar
* The pad reacts on screen as you press it, while the window is focused
* Per-control upload, or upload the whole profile at once
* Profiles saved as JSON
* A live HID log showing the exact bytes on the wire

## Build

```bash
./scripts/build-app.sh
open build/Knurl.app
```

Requires the Xcode command line tools. The result is `build/Knurl.app`.

There is also a diagnostic CLI:

```bash
swift build
.build/debug/knurl-probe list        # candidate configuration interfaces
.build/debug/knurl-probe interfaces  # every HID interface, keyboards included
.build/debug/knurl-probe info        # ask a WebHub device to describe itself
.build/debug/knurl-probe readkeys 0  # dump the key table for a layer
.build/debug/knurl-probe setkey 0 0 32 00 1D 00   # index, layer, type, c1, c2, c3
.build/debug/knurl-probe sniff 6D7B DCFA 60       # watch what the pad emits
```

`info`, `readkeys`, `interfaces` and `sniff` only read; `setkey` writes.

## First run

1. Plug in the pad and open the app. The device menu in the toolbar should
   already show it; a green dot means connected.
2. Click a button (or a knob's ↺ / ⏺ / ↻ segment) in the pad view.
3. In the inspector, hit **Start recording** and type the shortcut. Keys typed
   while recording are captured, not executed; Escape leaves the mode. Keys a
   Mac keyboard cannot send (F13–F24, Print Screen, Num Lock, keypad) are picked
   from the list underneath instead.
4. Press **Save to keypad** (⌘S). **Save this key** (⌥⌘S) writes only the
   selected control.

Give the keypad a nickname from the device card in the top left, and keep whole
sets of mappings as profiles from the card next to it — switching a profile
writes it to the hardware. Profiles can also be exported to and imported from
files as presets.

## Templates and per-app profiles

Templates are written against slots rather than a specific pad — buttons are
filled in order and the knob gets its three actions — so the same template lands
sensibly on a three-key pad and a twelve-key one. Choosing one writes it to the
keypad immediately. Each card lists exactly what it will put on every key, and
templates whose shortcuts are app-specific say so.

Mappings live in **scopes**: `Global`, plus one per app you add. Global is the
fallback; an app scope holds keys that only apply while that app is in front.
The scope bar under the toolbar is the whole model — pick a scope and the editor
below edits that scope.

The editor never moves on its own: you edit the scope you picked, and only the
keypad follows the front app. When an app with its own mappings comes forward
its scope is written to the hardware, otherwise Global is. Each write is a write
to the keypad's flash, so a scope already on the device is skipped.

Writing a scope also clears the slots it leaves empty, so a key from the
previous scope cannot linger.

Connecting reads the key table off the keypad, but only *adopts* it into a scope
that is still empty — once you have set keys, your work outranks whatever the
pad happens to be carrying.

## One window

Everything lives in a single window with its sections down the left: Keys,
Backlight, Apps, Presets, General and About. Settings are a section
there rather than a separate ⌘, window, so every switch the app has can be
found by looking rather than by remembering a menu. The menu bar item is a
shortcut to switching key sets, not the only route to anything.

The surface is a control panel: a light neutral ground, parts lifted off it by
a light from the top-left and a thin dark outline, dark wells for anything that
holds data, monospaced labels in small caps, and indicator lamps that light up.
Readouts and the wordmark are plotted as dot fields rather than typeset, because
macOS ships no pixel face.

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

Backlight is one read/write block: `06 0A` reads it, and
`06 0B 0B 00 00 <type> 00 <mode> <brightness> <speed> <direction> <color> 00 <h> <s> <v>`
writes it. `color` is a flag — `0` runs the palette and ignores the hue, `1`
uses the `h`/`s`/`v` triple. Effects are 0 off, 1 solid, 2 breathing, 3 blink,
4 tide, and a fifth the app does not offer because nothing it can send drives it.
Tide always runs the palette, so it is given no colour control. Speed is **0–4**: the firmware stores a 5 without complaint
but then behaves erratically, so the app does not offer one. The brightness byte
is written and read back faithfully but has no visible effect on the
SIDE-KEYBOARD, so the app does not offer a control for it.

The app reads the key table and the backlight off the keypad whenever it
connects, so the window shows what the hardware actually holds instead of an
empty profile.

Not yet implemented for this family: mouse actions and multi-key macros —
macros live in a separate table addressed by its own commands. The app refuses
to write those rather than guessing at the encoding.

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

`Sources/KnurlCore` holds everything device-related — the two report
composers, the IOKit transport, the HID usage tables, the pad layouts.
`Sources/KnurlApp` is the SwiftUI front end. `Sources/knurl-probe` is the
CLI.

## Adding a keypad

If your pad is not recognised, the diagnostic CLI will say what it looks like:

```bash
swift build
.build/debug/knurl-probe interfaces   # every HID interface on the machine
.build/debug/knurl-probe list         # the ones that could carry a config frame
```

A pad this app can drive has a vendor-defined interface (usage page `FF00`) with
64-byte reports, alongside the plain keyboard interfaces it types through. If
yours only has keyboard interfaces, it is configured some other way — over
Bluetooth, or by a drive it exposes — and none of this will reach it.

Issues and pull requests with new vendor/product ids are welcome, especially
with the output of `knurl-probe interfaces` attached.

## Licence

Two of the three wire protocols are derived from
[rOzzy1987/MacroPad](https://github.com/rOzzy1987/MacroPad), which is GPL-3.0,
so this reimplementation follows the same licence. The third was reverse
engineered here.
