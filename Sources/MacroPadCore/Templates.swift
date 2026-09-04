import Foundation

/// A ready-made set of mappings, so a new keypad does something useful before
/// the user has learned what a HID usage is.
///
/// Templates are written against slots rather than a specific pad: the buttons
/// are filled in order and the knob gets its three actions, so the same
/// template lands sensibly on a three-key pad and a twelve-key one.
public struct MacroTemplate: Identifiable, Sendable {
    public struct Step: Sendable {
        public let label: String
        public let binding: ControlBinding
        public init(_ label: String, _ binding: ControlBinding) {
            self.label = label
            self.binding = binding
        }
    }

    public let id: String
    public let name: String
    public let summary: String
    public let category: String
    public let icon: String
    /// A colour identity, so a wall of cards reads as distinct objects rather
    /// than as one grey list. Stored as a hex string to keep the model free of
    /// any UI framework.
    public let tint: String
    /// Filled into buttons 1, 2, 3 … in order.
    public let buttons: [Step]
    /// Knob actions, in the order left (counter-clockwise), press, right.
    public let knob: [Step?]
    /// Shown when the shortcuts are app-specific rather than system-wide.
    public let note: String?

    public init(id: String, name: String, summary: String, category: String, icon: String,
                tint: String = "8A8A8F",
                buttons: [Step], knob: [Step?] = [nil, nil, nil], note: String? = nil) {
        self.id = id
        self.name = name
        self.summary = summary
        self.category = category
        self.icon = icon
        self.tint = tint
        self.buttons = buttons
        self.knob = knob
        self.note = note
    }

    /// Lays the template onto a specific pad, skipping slots it does not have.
    public func apply(to profile: inout Profile, layout: KeyboardLayout, layer: UInt8) {
        let buttonIndices = layout.controls.compactMap { control -> Int? in
            if case .button(let i) = control.kind { return i }
            return nil
        }.sorted()

        for (offset, index) in buttonIndices.enumerated() {
            guard offset < buttons.count else { break }
            profile[layer, .key(index)] = buttons[offset].binding
        }

        let knobIndices = layout.controls.compactMap { control -> Int? in
            if case .knob(let i) = control.kind { return i }
            return nil
        }.sorted()

        if let first = knobIndices.first {
            for (slot, part) in [KnobPart.left, .push, .right].enumerated() {
                guard slot < knob.count, let step = knob[slot] else { continue }
                profile[layer, .knob(first, part)] = step.binding
            }
        }
    }
}

// MARK: - Shorthands

private func k(_ usage: UInt8, _ modifiers: Modifier = .none) -> ControlBinding {
    .keys(sequence: [KeyStroke(usage: usage, modifiers: modifiers)], delay: 0)
}

private func m(_ name: String) -> ControlBinding {
    .media(MediaKey.all.first { $0.name == name } ?? MediaKey.all[0])
}

private enum U {
    static let a: UInt8 = 0x04, b: UInt8 = 0x05, c: UInt8 = 0x06, i: UInt8 = 0x0C
    static let o: UInt8 = 0x12, r: UInt8 = 0x15, s: UInt8 = 0x16, t: UInt8 = 0x17, v: UInt8 = 0x19
    static let w: UInt8 = 0x1A, x: UInt8 = 0x1B, z: UInt8 = 0x1D
    static let one: UInt8 = 0x1E, three: UInt8 = 0x20, four: UInt8 = 0x21, five: UInt8 = 0x22
    static let zero: UInt8 = 0x27
    static let space: UInt8 = 0x2C, minus: UInt8 = 0x2D, equal: UInt8 = 0x2E
    static let tab: UInt8 = 0x2B
    static let right: UInt8 = 0x4F, left: UInt8 = 0x50
}

private let cmd: Modifier = .leftGui
private let shift: Modifier = .leftShift
private let opt: Modifier = .leftAlt
private let ctrl: Modifier = .leftCtrl

public enum TemplateLibrary {
    public static let all: [MacroTemplate] = [
        MacroTemplate(
            id: "music",
            name: "Music control",
            summary: "Skip tracks with the keys, volume on the knob",
            category: "Media",
            icon: "music.note",
            tint: "E8483F",
            buttons: [
                .init("Previous track", m("Previous track")),
                .init("Play / Pause", m("Play / Pause")),
                .init("Next track", m("Next track")),
            ],
            knob: [
                .init("Volume down", m("Volume down")),
                .init("Mute", m("Mute")),
                .init("Volume up", m("Volume up")),
            ]
        ),

        MacroTemplate(
            id: "clipboard",
            name: "Cut, copy, paste",
            summary: "The three you reach for most, plus undo on the knob",
            category: "Editing",
            icon: "doc.on.clipboard",
            tint: "2F7BE8",
            buttons: [
                .init("Cut", k(U.x, cmd)),
                .init("Copy", k(U.c, cmd)),
                .init("Paste", k(U.v, cmd)),
            ],
            knob: [
                .init("Undo", k(U.z, cmd)),
                .init("Paste as plain text", k(U.v, [cmd, shift, opt])),
                .init("Redo", k(U.z, [cmd, shift])),
            ]
        ),

        MacroTemplate(
            id: "design",
            name: "Design: undo & zoom",
            summary: "Undo and redo on the keys, zoom on the knob",
            category: "Creative",
            icon: "paintbrush.pointed",
            tint: "7A44D6",
            buttons: [
                .init("Undo", k(U.z, cmd)),
                .init("Redo", k(U.z, [cmd, shift])),
                .init("Fit to screen", k(U.one, [cmd, shift])),
            ],
            knob: [
                .init("Zoom out", k(U.minus, cmd)),
                .init("Zoom to 100%", k(U.one, cmd)),
                .init("Zoom in", k(U.equal, cmd)),
            ],
            note: "Zoom and fit shortcuts differ between Figma, Photoshop and Illustrator — adjust any key that does not match yours."
        ),

        MacroTemplate(
            id: "video",
            name: "Video editing",
            summary: "Cut and mark on the keys, scrub the timeline with the knob",
            category: "Creative",
            icon: "scissors",
            tint: "E07B1E",
            buttons: [
                .init("Split clip", k(U.b, cmd)),
                .init("Mark in", k(U.i)),
                .init("Mark out", k(U.o)),
            ],
            knob: [
                .init("Step back", k(U.left)),
                .init("Play / Pause", k(U.space)),
                .init("Step forward", k(U.right)),
            ],
            note: "Written for Premiere Pro. Resolve and Final Cut use different cut keys — change the first button to match your editor."
        ),

        MacroTemplate(
            id: "screenshot",
            name: "Screenshots",
            summary: "Grab a region, a window, or the whole screen",
            category: "System",
            icon: "camera.viewfinder",
            tint: "1D9E6B",
            buttons: [
                .init("Capture region", k(U.four, [cmd, shift])),
                .init("Capture options", k(U.five, [cmd, shift])),
                .init("Capture screen", k(U.three, [cmd, shift])),
            ],
            knob: [
                .init("Volume down", m("Volume down")),
                .init("Mute", m("Mute")),
                .init("Volume up", m("Volume up")),
            ]
        ),

        MacroTemplate(
            id: "browser",
            name: "Browser tabs",
            summary: "New and close on the keys, walk the tabs with the knob",
            category: "Productivity",
            icon: "safari",
            tint: "D6A314",
            buttons: [
                .init("New tab", k(U.t, cmd)),
                .init("Reopen closed tab", k(U.t, [cmd, shift])),
                .init("Close tab", k(U.w, cmd)),
            ],
            knob: [
                .init("Previous tab", k(U.tab, [ctrl, shift])),
                .init("Reload", k(U.r, cmd)),
                .init("Next tab", k(U.tab, ctrl)),
            ]
        ),
    ]

    public static var categories: [String] {
        var seen: [String] = []
        for t in all where !seen.contains(t.category) { seen.append(t.category) }
        return seen
    }
}
