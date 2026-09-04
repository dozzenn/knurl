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
                    if let note = model.unsupportedNote {
                        EmptyStateView(icon: "exclamationmark.triangle",
                                       title: "Not supported on this device",
                                       message: note)
                    } else {
                        switch model.editorTab {
                        case .keys:  KeysEditor()
                        case .media: MediaEditor()
                        case .mouse: MouseEditor()
                        case .led:   LedEditor()
                        }
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
        SectionLabel(text: "Shortcut")
        SequenceStrip()

        RecordButton()
            .padding(.top, 8)

        HStack(spacing: 8) {
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if !model.sequence.isEmpty {
                Button("Clear") { model.clearBinding() }
                    .buttonStyle(BarButtonStyle())
            }
        }
        .padding(.horizontal, 3)
        .padding(.top, 7)

        ManualKeySection()

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

    private var hint: String {
        if model.isRecording {
            return "Keys you press are captured here instead of doing what they normally do."
        }
        if model.maxKeystrokes == 1 {
            return "This keypad stores one shortcut per key."
        }
        return "Up to \(model.maxKeystrokes) keystrokes, played back in order."
    }
}

/// Recording is a mode, so the control states plainly which mode you are in and
/// what will happen next — "Start recording" rather than a bare "Record".
private struct RecordButton: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var pulsing = false

    var body: some View {
        Button {
            model.isRecording.toggle()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.isRecording ? Theme.accent : Theme.textMuted)
                    .frame(width: 8, height: 8)
                    .opacity(model.isRecording && pulsing && !reduceMotion ? 0.35 : 1)
                Text(model.isRecording ? "Stop recording" : "Start recording")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                ShortcutHint(keys: model.isRecording ? ["esc"] : [], emphasized: false)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(model.isRecording ? Theme.accent.opacity(0.24)
                          : (hovering ? Theme.fillStrong : Theme.fill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(model.isRecording ? Theme.accent.opacity(0.6) : Theme.hairline,
                                  lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .onHover { h in withAnimation(Theme.hover) { hovering = h } }
        .onChange(of: model.isRecording) { on in
            guard !reduceMotion else { return }
            if on {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulsing = true }
            } else {
                pulsing = false
            }
        }
    }
}

/// Recorded steps use the same keycaps as the shortcut hints, so a mapping
/// looks like the shortcut it will type.
private struct SequenceStrip: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if model.sequence.isEmpty {
                    Text(model.isRecording ? "Press the keys now…" : "No shortcut set")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textFaint)
                        .padding(.leading, 3)
                } else {
                    ForEach(model.sequence) { stroke in
                        StrokeChip(stroke: stroke)
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 52)
        }
        .frame(height: 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(model.isRecording ? Theme.accent.opacity(0.5) : Theme.hairline,
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

/// Some keys cannot be recorded because a Mac keyboard has no way to send them.
/// This is the way in for those, and it says so rather than calling itself
/// "add a key by name".
private struct ManualKeySection: View {
    @EnvironmentObject private var model: AppModel
    @State private var usage: UInt8 = 0x68     // F13 — the common reason to be here
    @State private var mods: Modifier = .none

    private var preview: [String] {
        var out: [String] = []
        if mods.contains(.leftCtrl) { out.append("⌃") }
        if mods.contains(.leftAlt) { out.append("⌥") }
        if mods.contains(.leftShift) { out.append("⇧") }
        if mods.contains(.leftGui) { out.append("⌘") }
        out.append(HIDKeyboard.name(for: usage))
        return out
    }

    var body: some View {
        SectionLabel(text: "Key your Mac can't type")

        Text("F13–F24, Print Screen, Num Lock and the numeric keypad have no key on a Mac keyboard, so pick them here instead of recording.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.textFaint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 3)
            .padding(.bottom, 9)

        HStack(spacing: 8) {
            ModifierRow(modifiers: $mods)
                .fixedSize()
            Picker("", selection: $usage) {
                ForEach(HIDKeyboard.selectable, id: \.self) { u in
                    Text(HIDKeyboard.name(for: u)).tag(u)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 3)

        HStack(spacing: 9) {
            ShortcutHint(keys: preview, emphasized: true)
            Spacer()
            BarAction(title: "Add to shortcut", prominent: true) {
                model.addKey(usage: usage, modifiers: mods)
            }
        }
        .padding(.horizontal, 3)
        .padding(.top, 9)
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
        if model.activeProtocol == .webHub {
            WebHubBacklightEditor()
        } else {
            LegacyLedEditor()
        }
    }
}

/// The backlight as this firmware actually models it: one effect plus the
/// handful of parameters that effect uses. Controls that the current effect
/// ignores are hidden rather than shown doing nothing.
private struct WebHubBacklightEditor: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SectionLabel(text: "Effect")

        VStack(spacing: 1) {
            ForEach(Array(BacklightState.modeNames.enumerated()), id: \.offset) { index, name in
                Row(title: name,
                    icon: index == 0 ? "lightbulb.slash" : "lightbulb.fill",
                    selected: model.backlight.mode == UInt8(index),
                    action: {
                        model.backlight.mode = UInt8(index)
                        model.applyBacklight()
                    }) {
                    if model.backlight.mode == UInt8(index) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }

        if !model.backlight.isOff {
            LabeledSlider(title: "Brightness",
                          readout: "\(model.backlight.brightness)",
                          value: Binding(
                            get: { Double(model.backlight.brightness) },
                            set: { model.backlight.brightness = UInt8($0.rounded()) }
                          ),
                          range: 0...Double(BacklightState.maxBrightness),
                          ticks: Int(BacklightState.maxBrightness) + 1) {
                model.applyBacklight()
            }

            if model.backlight.usesSpeed {
                LabeledSlider(title: "Speed",
                              readout: "\(model.backlight.speed)",
                              value: Binding(
                                get: { Double(model.backlight.speed) },
                                set: { model.backlight.speed = UInt8($0.rounded()) }
                              ),
                              range: 0...Double(BacklightState.maxSpeed),
                              ticks: Int(BacklightState.maxSpeed) + 1) {
                    model.applyBacklight()
                }
            }

            if model.backlight.usesColor {
                SectionLabel(text: "Colour")
                Segmented(selection: Binding(
                    get: { model.backlight.color },
                    set: { model.backlight.color = $0; model.applyBacklight() }
                ), items: [(UInt8(0), "Rainbow", "circle.hexagongrid.fill"),
                           (UInt8(1), "One colour", "paintpalette.fill")])
                .padding(.horizontal, 3)

                if model.backlight.color == 1 {
                    HueBand(hue: Binding(
                        get: { Double(model.backlight.hue) },
                        set: { model.backlight.hue = UInt8($0) }
                    ), onCommit: { model.applyBacklight() })
                    .padding(.top, 12)
                    .padding(.horizontal, 3)
                }
            }
        }

        Text(model.backlightIsLive
             ? "These are the keypad's current settings, read from the hardware. Changes are written straight away."
             : "Connect the keypad to read its current backlight.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.textFaint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 3)
            .padding(.top, 14)
    }
}

/// A section header with its current value on the right, over a slider — so the
/// number is there when you want it and out of the way when you don't.
private struct LabeledSlider: View {
    let title: String
    let readout: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var ticks: Int
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(Theme.sectionLabel)
                    .tracking(0.3)
                    .foregroundStyle(Theme.textFaint)
                Spacer()
                Text(readout)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 3)

            GlassSlider(value: $value, range: range, ticks: ticks, onCommit: onCommit)
                .padding(.horizontal, 3)
        }
        .padding(.top, 12)
    }
}

private struct LegacyLedEditor: View {
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

        Text("Backlight applies to the whole pad, not to one key. Press Save to send it.")
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
