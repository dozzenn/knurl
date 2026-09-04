import SwiftUI
import MacroPadCore

/// What the selected control does. One column of panels, so the eye goes
/// straight to the shortcut and everything else is subordinate to it.
struct InspectorPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            head
            Hairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let note = model.unsupportedNote {
                        Panel(title: "Not supported") {
                            Text(note)
                                .font(Theme.rowDetail)
                                .foregroundStyle(Theme.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        switch model.editorTab {
                        case .keys:  KeysEditor()
                        case .media: MediaEditor()
                        case .mouse: MouseEditor()
                        case .led:   Panel(title: "Backlight") {
                            Text("The backlight is a whole-keypad setting — it lives in the Backlight section.")
                                .font(Theme.rowDetail)
                                .foregroundStyle(Theme.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        }
                    }
                }
                .padding(Theme.gutter)
            }
        }
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(model.selectedAction.displayName)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.text)
                Spacer()
                if model.binding(for: model.selectedAction).isSet {
                    PanelButton(title: "Clear", compact: true) { model.clearBinding() }
                }
            }

            SegmentedSwitch(selection: $model.editorTab,
                            items: [(EditorTab.keys, "Keys"),
                                    (EditorTab.media, "Media"),
                                    (EditorTab.mouse, "Mouse")])
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 12)
    }
}

// MARK: - Keys

private struct KeysEditor: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Panel(title: "Shortcut") {
            SequenceWell()

            HStack(spacing: 8) {
                RecordButton()
                PanelButton(title: "Backspace", compact: true) { model.removeLastKey() }
                    .disabled(model.sequence.isEmpty)
                    .opacity(model.sequence.isEmpty ? 0.4 : 1)
                Spacer()
                Readout(text: "\(model.sequence.count)/\(model.maxKeystrokes)")
            }
            .padding(.top, 10)

            Text(hint)
                .font(Theme.rowDetail)
                .foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }

        Panel(title: "Key your Mac can't type") {
            Text("F13–F24, Print Screen, Num Lock and the numeric keypad have no key on a Mac keyboard, so pick them here instead of recording.")
                .font(Theme.rowDetail)
                .foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            ManualKeyRow()
        }

        if model.layout.supportsDelay {
            Panel(title: "Repeat delay", readout: "\(model.delay) ms") {
                PanelSlider(value: Binding(
                    get: { Double(model.delay) },
                    set: { model.delay = UInt16($0) }
                ), range: 0...2000) { model.commit() }
            }
        }
    }

    private var hint: String {
        if model.isRecording {
            return "Keys you press are captured here instead of doing what they normally do. Escape leaves."
        }
        if model.maxKeystrokes == 1 { return "This keypad stores one shortcut per key." }
        return "Up to \(model.maxKeystrokes) keystrokes, played back in order."
    }
}

private struct RecordButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button { model.isRecording.toggle() } label: {
            HStack(spacing: 8) {
                Lamp(on: model.isRecording, colour: Theme.lampAlert, size: 8)
                Text(model.isRecording ? "STOP RECORDING" : "START RECORDING")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(model.isRecording ? Theme.textOnWell : Theme.text)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .modifier(RecordSurface(on: model.isRecording))
        }
        .buttonStyle(PressableStyle())
    }
}

private struct RecordSurface: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on {
            content
                .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(Theme.well))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .strokeBorder(Theme.outline, lineWidth: 1))
        } else {
            content.lifted(radius: Theme.radiusSmall, depth: 0.7)
        }
    }
}

/// The recorded shortcut, shown in the dark well the way a device shows what it
/// is holding.
private struct SequenceWell: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if model.sequence.isEmpty {
                    Text(model.isRecording ? "PRESS THE KEYS NOW…" : "NO SHORTCUT SET")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(Theme.textOnWellMuted)
                } else {
                    ForEach(model.sequence) { stroke in
                        WellCap(text: caps(for: stroke))
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
        }
        .frame(height: 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well(radius: Theme.radiusSmall)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .strokeBorder(model.isRecording ? Theme.lampAlert : .clear, lineWidth: 1.5)
        )
    }

    private func caps(for stroke: KeyStroke) -> [String] {
        var out: [String] = []
        let m = stroke.modifiers
        if m.contains(.leftCtrl) || m.contains(.rightCtrl) { out.append("⌃") }
        if m.contains(.leftAlt) || m.contains(.rightAlt) { out.append("⌥") }
        if m.contains(.leftShift) || m.contains(.rightShift) { out.append("⇧") }
        if m.contains(.leftGui) || m.contains(.rightGui) { out.append("⌘") }
        if stroke.usage != 0 { out.append(HIDKeyboard.name(for: stroke.usage)) }
        return out
    }
}

/// A key drawn on the dark well — light on dark, unlike the caps on the panel.
private struct WellCap: View {
    let text: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textOnWell)
                    .frame(minWidth: 20)
                    .frame(height: 22)
                    .padding(.horizontal, 5)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Theme.wellLift))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            }
        }
    }
}

private struct ManualKeyRow: View {
    @EnvironmentObject private var model: AppModel
    @State private var usage: UInt8 = 0x68
    @State private var mods: Modifier = .none

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ModifierRow(modifiers: $mods).fixedSize()
                Picker("", selection: $usage) {
                    ForEach(HIDKeyboard.selectable, id: \.self) { u in
                        Text(HIDKeyboard.name(for: u)).tag(u)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 9) {
                ShortcutHint(keys: preview)
                Spacer()
                PanelButton(title: "Add", compact: true) {
                    model.addKey(usage: usage, modifiers: mods)
                }
            }
        }
    }

    private var preview: [String] {
        var out: [String] = []
        if mods.contains(.leftCtrl) { out.append("⌃") }
        if mods.contains(.leftAlt) { out.append("⌥") }
        if mods.contains(.leftShift) { out.append("⇧") }
        if mods.contains(.leftGui) { out.append("⌘") }
        out.append(HIDKeyboard.name(for: usage))
        return out
    }
}

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
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(on ? Theme.textOnWell : Theme.textMuted)
                        .frame(width: 27, height: 25)
                        .modifier(RecordSurface(on: on))
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
        Panel(title: "Media key") {
            VStack(spacing: 1) {
                ForEach(available) { key in
                    Row(title: key.name,
                        selected: model.mediaKey == key,
                        action: { model.mediaKey = key; model.commit() }) {
                        Lamp(on: model.mediaKey == key, size: 7)
                    }
                }
            }
            if available.count == MediaKey.legacySafe.count {
                Text("Only these six have a known encoding for this firmware. Switch the media encoding in General for the full list.")
                    .font(Theme.rowDetail)
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
    }
}

// MARK: - Mouse

private struct MouseEditor: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Panel(title: "Mouse action") {
            VStack(spacing: 1) {
                ForEach(MouseButton.allCases) { button in
                    Row(title: button.displayName,
                        selected: model.mouseButton == button,
                        action: { model.mouseButton = button; model.commit() }) {
                        Lamp(on: model.mouseButton == button, size: 7)
                    }
                }
            }
        }
        Panel(title: "Held modifiers") {
            ModifierRow(modifiers: $model.mouseModifiers) { model.commit() }
        }
    }
}
