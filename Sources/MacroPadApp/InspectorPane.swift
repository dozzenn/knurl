import SwiftUI
import MacroPadCore

/// What the selected control does. One column, dense rows, no nested cards —
/// the surface stays flat so the eye goes straight to the sequence.
struct InspectorPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            head
            Hairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch model.editorTab {
                    case .keys:  KeysEditor()
                    case .media: MediaEditor()
                    case .mouse: MouseEditor()
                    case .led:   LedEditor()
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.black.opacity(0.12))
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text(model.selectedAction.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Theme.text)
                Spacer()
                if model.binding(for: model.selectedAction).isSet {
                    Button {
                        model.clearBinding()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textFaint)
                    }
                    .buttonStyle(PressableStyle())
                    .help("Clear this mapping")
                }
            }

            Segmented(selection: $model.editorTab,
                      items: EditorTab.allCases.map { ($0, $0.title, $0.icon) })
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 11)
    }
}

// MARK: - Keys

private struct KeysEditor: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SectionLabel(text: "Sequence")

        SequenceStrip()

        HStack(spacing: 6) {
            RecordButton()
            BarAction(title: "Backspace", keys: ["⌫"]) { model.removeLastKey() }
                .disabled(model.sequence.isEmpty)
                .opacity(model.sequence.isEmpty ? 0.4 : 1)
            Spacer()
            Text("\(model.sequence.count)/\(model.layout.maxCharacters)")
                .font(Theme.mono)
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.top, 8)

        ManualKeyRow()

        if model.layout.supportsDelay {
            SectionLabel(text: "Repeat delay")
            HStack(spacing: 10) {
                Slider(value: Binding(
                    get: { Double(model.delay) },
                    set: { model.delay = UInt16($0); model.commit() }
                ), in: 0...2000, step: 10)
                .controlSize(.small)
                .tint(Theme.accent)
                Text("\(model.delay) ms")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 54, alignment: .trailing)
            }
            .padding(.horizontal, 9)
        }
    }
}

/// Recording is a mode, and a mode needs to be unmistakable — the button turns
/// red and a live line explains that keys are being swallowed, not executed.
private struct RecordButton: View {
    @EnvironmentObject private var model: AppModel
    @State private var hovering = false

    var body: some View {
        Button {
            model.isRecording.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.isRecording ? Theme.accent : Theme.textMuted)
                    .frame(width: 7, height: 7)
                Text(model.isRecording ? "Recording — press keys" : "Record")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(model.isRecording ? Theme.text : Theme.textMuted)
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(model.isRecording ? Theme.accent.opacity(0.22)
                          : (hovering ? Theme.rowHover : Theme.fill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(model.isRecording ? Theme.accent.opacity(0.55) : Theme.hairline,
                                  lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .onHover { h in withAnimation(Theme.hover) { hovering = h } }
    }
}

/// Recorded steps are drawn with the same keycaps used for shortcut hints, so a
/// macro looks like the shortcut it will type.
private struct SequenceStrip: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if model.sequence.isEmpty {
                    Text(model.isRecording ? "Press the keys you want on this button…"
                                           : "Nothing recorded yet")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.leading, 3)
                } else {
                    ForEach(model.sequence) { stroke in
                        StrokeChip(stroke: stroke)
                    }
                }
            }
            .padding(.horizontal, 9)
            .frame(minHeight: 46)
        }
        .frame(height: 46)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(model.isRecording ? Theme.accent.opacity(0.45) : Theme.hairline,
                              lineWidth: 1)
        )
    }
}

private struct StrokeChip: View {
    let stroke: KeyStroke

    private var caps: [String] {
        var out: [String] = []
        let m = stroke.modifiers
        if m.contains(.leftCtrl) || m.contains(.rightCtrl) { out.append("⌃") }
        if m.contains(.leftAlt) || m.contains(.rightAlt) { out.append("⌥") }
        if m.contains(.leftShift) || m.contains(.rightShift) { out.append("⇧") }
        if m.contains(.leftGui) || m.contains(.rightGui) { out.append("⌘") }
        if stroke.usage != 0 { out.append(HIDKeyboard.name(for: stroke.usage)) }
        return out
    }

    var body: some View {
        ShortcutHint(keys: caps, emphasized: true)
    }
}

/// Keys a Mac keyboard cannot produce — Print Screen, Num Lock, F13+ — still
/// need a way in, one level down from recording.
private struct ManualKeyRow: View {
    @EnvironmentObject private var model: AppModel
    @State private var usage: UInt8 = 0x04
    @State private var mods: Modifier = .none

    var body: some View {
        SectionLabel(text: "Add a key by name")

        HStack(spacing: 7) {
            Picker("", selection: $usage) {
                ForEach(HIDKeyboard.selectable, id: \.self) { u in
                    Text(HIDKeyboard.name(for: u)).tag(u)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 132)

            BarAction(title: "Add", prominent: true) {
                model.addKey(usage: usage, modifiers: mods)
            }
            Spacer()
        }
        .padding(.horizontal, 9)

        ModifierRow(modifiers: $mods)
            .padding(.horizontal, 9)
            .padding(.top, 7)
    }
}

/// Modifiers as togglable keycaps rather than checkboxes — the control looks
/// like the thing it produces.
struct ModifierRow: View {
    @Binding var modifiers: Modifier
    var onChange: (() -> Void)?

    private let items: [(String, Modifier)] = [
        ("⌃", .leftCtrl), ("⌥", .leftAlt), ("⇧", .leftShift), ("⌘", .leftGui),
    ]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(items, id: \.0) { symbol, flag in
                let on = modifiers.contains(flag)
                Button {
                    if on { modifiers.remove(flag) } else { modifiers.insert(flag) }
                    onChange?()
                } label: {
                    Text(symbol)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(on ? Theme.text : Theme.textFaint)
                        .frame(width: 26, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                .fill(on ? Theme.accent.opacity(0.26) : Theme.fill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                .strokeBorder(on ? Theme.accent.opacity(0.5) : Theme.hairline, lineWidth: 1)
                        )
                }
                .buttonStyle(PressableStyle())
            }
            Spacer()
        }
    }
}

// MARK: - Media

private struct MediaEditor: View {
    @EnvironmentObject private var model: AppModel

    private var available: [MediaKey] {
        let encoding = model.mediaEncoding == .auto
            ? (model.reportId == 3 ? MediaEncoding.consumerUsage : .legacyBitmask)
            : model.mediaEncoding
        return encoding == .consumerUsage ? MediaKey.all : MediaKey.legacySafe
    }

    var body: some View {
        SectionLabel(text: "Media key")

        VStack(spacing: 1) {
            ForEach(available) { key in
                Row(title: key.name,
                    icon: icon(for: key),
                    selected: model.mediaKey == key,
                    action: {
                        model.mediaKey = key
                        model.commit()
                    }) {
                    if model.mediaKey == key {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }

        if available.count == MediaKey.legacySafe.count {
            Text("Only these six have a known encoding for this firmware. Switch the media encoding to “HID consumer usage” in Settings for the full list.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 9)
                .padding(.top, 10)
        }
    }

    private func icon(for key: MediaKey) -> String {
        switch key.name {
        case "Play / Pause": return "playpause"
        case "Next track": return "forward.end"
        case "Previous track": return "backward.end"
        case "Mute": return "speaker.slash"
        case "Volume up": return "speaker.wave.3"
        case "Volume down": return "speaker.wave.1"
        case "Stop": return "stop"
        case "Fast forward": return "forward"
        case "Rewind": return "backward"
        case "Eject": return "eject"
        case "Brightness up": return "sun.max"
        case "Brightness down": return "sun.min"
        case "Mail": return "envelope"
        case "Calculator": return "function"
        case "File explorer": return "folder"
        case "Media player": return "music.note"
        default: return "safari"
        }
    }
}

// MARK: - Mouse

private struct MouseEditor: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SectionLabel(text: "Mouse action")

        VStack(spacing: 1) {
            ForEach(MouseButton.allCases) { button in
                Row(title: button.displayName,
                    icon: icon(for: button),
                    selected: model.mouseButton == button,
                    action: {
                        model.mouseButton = button
                        model.commit()
                    }) {
                    if model.mouseButton == button {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }

        SectionLabel(text: "Held modifiers")
        ModifierRow(modifiers: $model.mouseModifiers) { model.commit() }
            .padding(.horizontal, 9)
    }

    private func icon(for button: MouseButton) -> String {
        switch button {
        case .left: return "cursorarrow.click"
        case .middle: return "cursorarrow.click.2"
        case .right: return "cursorarrow.and.square.on.square.dashed"
        case .scrollUp: return "arrow.up"
        case .scrollDown: return "arrow.down"
        }
    }
}

// MARK: - LED

private struct LedEditor: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SectionLabel(text: "Backlight mode")

        VStack(spacing: 1) {
            ForEach(Array(LedMode.allCases.prefix(max(model.layout.ledModeCount, 1))), id: \.self) { mode in
                Row(title: mode.displayName,
                    icon: mode == .mode0 ? "lightbulb.slash" : "lightbulb",
                    selected: model.profile.ledMode == mode,
                    action: { model.profile.ledMode = mode }) {
                    if model.profile.ledMode == mode {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }

        if model.layout.supportsColor {
            SectionLabel(text: "Colour")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 7) {
                ForEach(LedColor.allCases) { color in
                    ColorSwatch(color: color, selected: model.profile.ledColor == color) {
                        model.profile.ledColor = color
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.top, 2)
        }

        Text("Backlight applies to the whole pad, not to one key. Press Upload to send it.")
            .font(Theme.caption)
            .foregroundStyle(Theme.textFaint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.top, 12)
    }
}

private struct ColorSwatch: View {
    let color: LedColor
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    private var swatch: some ShapeStyle {
        switch color {
        case .random:
            return AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                                 center: .center))
        case .red:    return AnyShapeStyle(Color(red: 1.00, green: 0.27, blue: 0.27))
        case .orange: return AnyShapeStyle(Color(red: 1.00, green: 0.58, blue: 0.20))
        case .yellow: return AnyShapeStyle(Color(red: 1.00, green: 0.84, blue: 0.25))
        case .green:  return AnyShapeStyle(Color(red: 0.30, green: 0.85, blue: 0.39))
        case .cyan:   return AnyShapeStyle(Color(red: 0.28, green: 0.83, blue: 0.89))
        case .blue:   return AnyShapeStyle(Color(red: 0.28, green: 0.55, blue: 1.00))
        case .purple: return AnyShapeStyle(Color(red: 0.70, green: 0.42, blue: 1.00))
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(swatch)
                    .frame(height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                            .strokeBorder(Color.white.opacity(selected ? 0.9 : 0.12),
                                          lineWidth: selected ? 1.5 : 1)
                    )
                Text(color.displayName)
                    .font(.system(size: 9.5))
                    .foregroundStyle(selected ? Theme.text : Theme.textFaint)
                    .lineLimit(1)
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(hovering ? Theme.rowHover : .clear)
            )
        }
        .buttonStyle(PressableStyle())
        .onHover { h in withAnimation(Theme.hover) { hovering = h } }
    }
}
