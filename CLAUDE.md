# Working on Knurl

Context for anyone — or any agent — picking this up cold.

## What it is

A macOS app that configures cheap USB macro keypads over HID. It writes the
mapping into the device's own flash; once written, the pad works with Knurl
closed. The app is a configurator, not an input interceptor, and that line is
worth holding: proposals to translate keystrokes at runtime change what the
product is and drag in permissions that do not survive an unsigned build.

## Layout

- `Sources/KnurlCore` — everything device-related: the three report composers,
  the IOKit transport, HID usage tables, keyboard-layout resolution, the pad
  layouts, scope and preset storage.
- `Sources/KnurlApp` — the SwiftUI front end. `Theme.swift` is the design system.
- `Sources/knurl-probe` — a CLI for talking to hardware directly. This is how
  every protocol question got answered; reach for it before guessing.

```bash
swift build
.build/debug/knurl-probe interfaces        # every HID interface
.build/debug/knurl-probe list              # ones that could carry a config frame
.build/debug/knurl-probe info              # ask a WebHub device to describe itself
.build/debug/knurl-probe readkeys 0        # dump the key table
.build/debug/knurl-probe layout "+-"       # what types a character on this layout
.build/debug/knurl-probe setkey 0 0 32 00 1D 00
```

`info`, `readkeys`, `interfaces`, `layout` and `sniff` only read.

## The hardware this was built against

An SDINNOVATION SIDE-KEYBOARD, `6D7B:DCFA` — three keys and one knob. Its
configuration channel is interface 2, a vendor-defined HID interface with
64-byte reports and no report ids, so the effective report id is 0.

Its protocol (called WebHub here) was read out of the vendor's own WebHID
configurator at huali-tech.com and verified against the hardware. The frame
format is in the README. Sub-command `0x5A` jumps the device into its
bootloader, which is why blind command sweeping is not a way to explore one of
these.

A second pad tried during development — a Jieli device, `4C4A:4155` — has no
writable interface at all: one boot keyboard plus a mass-storage interface with
no media. Nothing here can reach it. Pads with only keyboard interfaces are
configured some other way and are out of scope.

## Traps that cost time

**Key positions are not characters.** A pad sends HID usages, which are physical
positions, and macOS reads them through the active layout. A template written
for a US keyboard types something else on a Turkish one. `LayoutResolver` maps a
character to the key that types it here — and prefers unshifted keys, because a
shifted resolution plus command lands on system shortcuts (on a Turkish layout
`+` is shift-4, and `⇧⌘4` is the screenshot crosshair).

**`KeyStroke.id` is not part of what a keystroke is.** It exists for SwiftUI
lists. It is deliberately excluded from equality; including it made every
"is this preset loaded?" comparison false as soon as a profile came off disk.

**A `MenuBarExtra` declared first becomes the primary scene** and the app
launches with no window. It also keeps the app alive after the window is closed,
so reopening has to be handled explicitly — see `AppDelegate`.

**SwiftUI hover does not fire in a menu bar window**, neither `onHover` nor
`onContinuousHover`. `HoverTracker` uses an `NSTrackingArea`.

**A `ScrollView` in a menu bar window does not size itself from its content.**
Give it an explicit height or it collapses.

**The macro table's header is 64 bytes and a keyboard step's kind is 3.**
Neither is guessable from the reader: it treats anything that is not 2, 4 or 5
as a keyboard step, so a wrong kind decodes as one and reads back looking
correct while the firmware does nothing with it. The encoder — `E` in the vendor
bundle — is the only place both facts appear. When a macro writes and reads back
cleanly but the key does nothing, suspect a value the reader is lenient about.

**Writing the macro table clears the key table.** Blob first, key entries
after — which is the order `writeToDevice` uses. A probe command that writes a
blob and only one key entry will appear to wipe the pad.

**Unsigned builds change identity on every rebuild**, so TCC grants never stick.
This is why press counting was removed rather than shipped as a switch that
quietly does nothing.

## Dead end: macros

**Macros do not run on this hardware, and the path is switched off.** The code
to write them is still in `MacroTable` and `writeToDevice`, and it is correct as
far as anything can tell: the blob writes, reads back byte for byte, and the key
entry points at the right slot. Pressing the key does nothing. Four variations
were tried on the device, each from evidence rather than guesswork:

- step kind 1, then 3 — the encoder's value for a recorded key step
- step kind 2 — what the vendor's own hand-built Win+R macro emits
- `code3 = 1` on the key entry, on the theory that it is a repeat count

None ran. What is left unexplored is `code2` on the key entry, which the vendor's
editor feeds from a control whose label is not in the JS bundle — the strings are
fetched at runtime.

`maxKeystrokesPerControl` for WebHub is 1 so that nobody can record a sequence
that silently does nothing. Raise it only after seeing a macro actually run.

## Conventions

- Say what the hardware actually does. Where a control would change nothing —
  tide's colour, brightness on this pad — it is not offered, and the README
  records why.
- Read state off the device rather than remembering it, but never overwrite a
  scope the user has already filled.
- Every write is a write to flash. Skip writes that would change nothing.
- Commit messages explain the reasoning, not the diff.

## Publishing

`./scripts/release.sh <version>` builds and zips. The build is ad-hoc signed;
notarising needs a paid Apple Developer account, and the README tells users
plainly what macOS will say and what to do about it.
