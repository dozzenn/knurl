import AppKit
import SwiftUI
import MacroPadCore

// MARK: - Backlight

struct BacklightSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Panel(title: "Effect") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                              spacing: 10) {
                        ForEach(Array(BacklightState.modeNames.enumerated()), id: \.offset) { index, name in
                            EffectTile(title: name,
                                       mode: index,
                                       selected: model.backlight.mode == UInt8(index),
                                       colour: model.backlight.color == 1
                                       ? Color(hue: Double(model.backlight.hue) / 255,
                                               saturation: 0.85, brightness: 1)
                                       : nil) {
                                model.backlight.mode = UInt8(index)
                                model.applyBacklight()
                            }
                        }
                    }
                }

                if !model.backlight.isOff {
                    if model.backlight.usesSpeed {
                        let steps = model.backlight.speedSteps
                        Panel(title: "Speed", readout: "\(model.backlight.speed)") {
                            PanelSlider(value: Binding(
                                get: { Double(min(max(model.backlight.speed, steps.lowerBound), steps.upperBound)) },
                                set: { model.backlight.speed = UInt8($0.rounded()) }
                            ),
                                        range: Double(steps.lowerBound)...Double(steps.upperBound),
                                        ticks: Int(steps.upperBound - steps.lowerBound) + 1) {
                                model.applyBacklight()
                            }
                            if let note = model.backlight.speedNote {
                                Text(note)
                                    .font(Theme.rowDetail)
                                    .foregroundStyle(Theme.textFaint)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 8)
                            }
                        }
                    }

                    if model.backlight.usesColor {
                        Panel(title: "Colour") {
                            SegmentedSwitch(selection: Binding(
                                get: { model.backlight.color },
                                set: { model.backlight.color = $0; model.applyBacklight() }
                            ), items: [(UInt8(0), "Rainbow"), (UInt8(1), "One colour")])

                            if model.backlight.color == 1 {
                                HueBand(hue: Binding(
                                    get: { Double(model.backlight.hue) },
                                    set: { model.backlight.hue = UInt8($0) }
                                ), onCommit: { model.applyBacklight() })
                                .padding(.top, 14)
                            }
                        }
                    }
                }

                Text(model.backlightIsLive
                     ? "Read from the keypad. Changes are written as you make them."
                     : "Connect the keypad to read its backlight.")
                    .font(Theme.rowDetail)
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(Theme.gutter)
        }
    }
}

/// One wide band of colour; the gradient is the track, so there is nothing to
/// map from a second strip.
struct HueBand: View {
    @Binding var hue: Double
    var onCommit: (() -> Void)?
    @State private var dragging = false

    private var fraction: Double { min(1, max(0, hue / 255)) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let knob: CGFloat = 26

            ZStack(alignment: .leading) {
                LinearGradient(colors: (0...24).map {
                    Color(hue: Double($0) / 24, saturation: 0.9, brightness: 1)
                }, startPoint: .leading, endPoint: .trailing)
                .frame(height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Theme.outline, lineWidth: 1))

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hue: fraction, saturation: 0.9, brightness: 1))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 2))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Theme.outline, lineWidth: 1))
                    .shadow(color: Theme.dropShadow, radius: dragging ? 5 : 3, x: 1, y: 2)
                    .frame(width: knob, height: 34)
                    .offset(x: (w - knob) * fraction)
            }
            .frame(height: 36)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        dragging = true
                        let usable = max(1, w - knob)
                        hue = min(255, max(0, (g.location.x - knob / 2) / usable * 255))
                    }
                    .onEnded { _ in dragging = false; onCommit?() }
            )
        }
        .frame(height: 36)
        .animation(Theme.press, value: dragging)
    }
}

struct EffectTile: View {
    let title: String
    let mode: Int
    let selected: Bool
    var colour: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    preview
                    if mode == 5 { DotField(spacing: 6, radius: 1.2, color: .white, opacity: 0.25) }
                }
                .frame(height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Theme.outline, lineWidth: 1))
                .padding(5)

                HStack(spacing: 6) {
                    Text(title.uppercased())
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 0)
                    Lamp(on: selected, size: 6)
                }
                .padding(.horizontal, 7)
                .padding(.bottom, 7)
            }
            .lifted(radius: Theme.radius, pressed: selected, depth: selected ? 0.4 : 0.9)
        }
        .buttonStyle(PressableStyle(scale: 0.985))
    }

    private var band: [Color] {
        if let colour { return [colour, colour] }
        return (0...6).map { Color(hue: Double($0) / 6, saturation: 0.85, brightness: 1) }
    }

    @ViewBuilder
    private var preview: some View {
        switch mode {
        case 0: Theme.well
        case 1: LinearGradient(colors: band, startPoint: .leading, endPoint: .trailing)
        case 2: LinearGradient(colors: [Theme.well, colour ?? .purple],
                               startPoint: .bottom, endPoint: .top)
        case 3: HStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { i in
                        (i.isMultiple(of: 2) ? (colour ?? Color.indigo) : Theme.well)
                    }
                }
        case 4: LinearGradient(colors: band + band.reversed(),
                               startPoint: .leading, endPoint: .trailing)
        default: LinearGradient(colors: [Color(red: 0.32, green: 0.22, blue: 0.62),
                                         Color(red: 0.62, green: 0.26, blue: 0.72)],
                                startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct DotField: View {
    var spacing: CGFloat = 5
    var radius: CGFloat = 1
    var color: Color = .white
    var opacity: Double = 0.16

    var body: some View {
        Canvas { context, size in
            let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2))
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    context.translateBy(x: x, y: y)
                    context.fill(dot, with: .color(color.opacity(opacity)))
                    context.translateBy(x: -x, y: -y)
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Apps

struct AppsSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Panel(title: "Follow the front app") {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.autoSwitchEnabled
                                 ? "The keypad loads an app's keys when you switch to it."
                                 : "The keypad keeps whatever you last saved.")
                                .font(Theme.rowTitle)
                                .foregroundStyle(Theme.text)
                            Text("Apps without their own keys fall back to Global. A set already on the keypad is not rewritten.")
                                .font(Theme.rowDetail)
                                .foregroundStyle(Theme.textFaint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        PanelSwitch(isOn: $model.autoSwitchEnabled)
                    }
                }

                Panel(title: "Key sets") {
                    VStack(spacing: 1) {
                        ForEach(model.scopes) { scope in
                            HStack(spacing: 10) {
                                if scope.isGlobal {
                                    Image(systemName: "globe")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.textMuted)
                                        .frame(width: 20)
                                } else if let icon = appIcon(for: scope.key) {
                                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                                } else {
                                    Image(systemName: "app.dashed")
                                        .foregroundStyle(Theme.textFaint).frame(width: 20)
                                }

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(scope.name)
                                        .font(Theme.rowTitle)
                                        .foregroundStyle(Theme.text)
                                    Text(scope.isGlobal ? "everywhere else" : scope.key)
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(Theme.textFaint)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 8)

                                if model.liveScopeKey == scope.key && model.isConnected {
                                    PanelLabel(text: "on keypad", colour: Theme.textFaint, size: 9)
                                    Lamp(on: true, colour: Theme.lampGood, size: 7)
                                } else if !model.scopeHasMappings(scope) {
                                    PanelLabel(text: "empty", colour: Theme.textFaint, size: 9)
                                }

                                PanelButton(title: "Edit", compact: true) {
                                    model.selectScope(scope.key)
                                }
                                if !scope.isGlobal {
                                    PanelButton(title: "Remove", compact: true) {
                                        model.removeScope(scope)
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 46)
                        }
                    }

                    PanelButton(title: "Add application", prominent: true) { pickApp(model) }
                        .padding(.top, 10)
                }
            }
            .padding(Theme.gutter)
        }
    }
}

// MARK: - Presets

struct PresetsSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSave = false
    @State private var name = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Panel(title: "Your presets") {
                    if model.presets.isEmpty {
                        Text("Nothing saved yet. Saving keeps whatever keys are on screen so you can drop them onto any app later.")
                            .font(Theme.rowDetail)
                            .foregroundStyle(Theme.textFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                            ForEach(model.presets) { preset in
                                SetCard(title: preset.name,
                                        summary: preset.summary.isEmpty
                                        ? "\(preset.profile.bindings.count) keys saved" : preset.summary,
                                        icon: "bookmark.fill",
                                        tint: .identity(for: preset.name),
                                        lines: [],
                                        note: nil,
                                        onUse: { model.apply(preset) },
                                        onDelete: { model.deletePreset(preset) })
                            }
                        }
                    }
                    PanelButton(title: "Save current keys", prominent: true) {
                        name = model.currentScope.name
                        showSave = true
                    }
                    .padding(.top, 12)
                }

                Panel(title: "Built in") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                        ForEach(TemplateLibrary.all) { template in
                            SetCard(title: template.name,
                                    summary: template.summary,
                                    icon: template.icon,
                                    tint: Color(hex: template.tint),
                                    lines: lines(for: template),
                                    note: template.note,
                                    onUse: { model.apply(template) },
                                    onDelete: nil)
                        }
                    }
                }
            }
            .padding(Theme.gutter)
        }
        .sheet(isPresented: $showSave) {
            SavePresetSheet(name: $name) { model.savePreset(named: $0, summary: $1) }
        }
    }

    private func lines(for template: MacroTemplate) -> [(String, String)] {
        var out = template.buttons.enumerated().map { ("\($0.offset + 1)", $0.element.label) }
        for (i, step) in template.knob.enumerated() {
            if let step { out.append((["↺", "⏺", "↻"][i], step.label)) }
        }
        return out
    }
}

private struct SetCard: View {
    let title: String
    let summary: String
    let icon: String
    let tint: Color
    let lines: [(String, String)]
    let note: String?
    let onUse: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // A colour bar across the top: a wall of these should read as a set
            // of distinct objects, not one grey list.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(LinearGradient(colors: [tint, tint.opacity(0.55)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 5)
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.28), lineWidth: 0.75))
                .padding(.bottom, 11)

            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(LinearGradient(colors: [tint.opacity(0.92), tint],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.30), lineWidth: 1))
                    .shadow(color: tint.opacity(0.45), radius: 4, y: 1)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textFaint)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.bottom, 8)

            Text(summary)
                .font(Theme.rowDetail)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 7) {
                            KeyCap(text: line.0)
                            Text(line.1)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.textMuted)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 9)
            }

            if let note {
                Text(note)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Theme.text.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            Spacer(minLength: 10)
            PanelButton(title: "Use this", prominent: true, action: onUse)
                .frame(maxWidth: .infinity)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .lifted(radius: Theme.radiusPanel, depth: 0.8)
    }
}

private struct SavePresetSheet: View {
    @Binding var name: String
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var summary = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelLabel(text: "Save these keys", colour: Theme.text, size: 11)
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .font(Theme.rowTitle)
                .foregroundStyle(Theme.textOnWell)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .well(radius: Theme.radiusSmall)
            TextField("What is it for? (optional)", text: $summary)
                .textFieldStyle(.plain)
                .font(Theme.rowDetail)
                .foregroundStyle(Theme.textOnWell)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .well(radius: Theme.radiusSmall)
            HStack {
                Spacer()
                PanelButton(title: "Cancel") { dismiss() }
                PanelButton(title: "Save", prominent: true) {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSave(trimmed, summary.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(PopoverBackground())
    }
}

// MARK: - Stats

struct StatsSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Panel(title: "Count presses") {
                    HStack(spacing: 12) {
                        Text("Watches this keypad's own interface and attributes each press to the key that produced it. Nothing else you type is seen.")
                            .font(Theme.rowDetail)
                            .foregroundStyle(Theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        PanelSwitch(isOn: $model.statsEnabled)
                    }
                }

                if model.statsEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .bottom, spacing: 14) {
                            DotMatrixNumber(text: "\(model.totalPresses)", dot: 6, gap: 3,
                                            color: Theme.lampOn)
                            PanelLabel(text: "total presses", colour: Theme.textOnWellMuted, size: 10)
                                .padding(.bottom, 3)
                            Spacer()
                            PanelButton(title: "Reset", compact: true) { model.resetStats() }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .well(radius: Theme.radiusPanel)

                        Panel(title: "Per key") {
                            VStack(spacing: 1) {
                                ForEach(model.layout.controls) { control in
                                    ForEach(control.actions, id: \.self) { action in
                                        HStack(spacing: 10) {
                                            Text(action.displayName)
                                                .font(Theme.rowTitle)
                                                .foregroundStyle(Theme.text)
                                            Text(model.binding(for: action).summary)
                                                .font(Theme.rowDetail)
                                                .foregroundStyle(Theme.textFaint)
                                                .lineLimit(1)
                                            Spacer(minLength: 8)
                                            Readout(text: "\(model.presses(for: action))")
                                        }
                                        .padding(.horizontal, 10)
                                        .frame(height: 34)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.gutter)
        }
    }
}

// MARK: - General

struct GeneralSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Panel(title: "Startup") {
                    SwitchRow(title: "Open at login",
                              detail: "Start MacroPad when you log in",
                              isOn: Binding(get: { model.launchAtLogin },
                                            set: { model.setLaunchAtLogin($0) }))
                    SwitchRow(title: "Menu bar only",
                              detail: "Hide the Dock icon",
                              isOn: $model.hideDockIcon)
                }

                Panel(title: "Presets") {
                    HStack(spacing: 9) {
                        PanelButton(title: "Import preset") { model.importPreset() }
                        PanelButton(title: "Export preset") { model.exportPreset() }
                        Spacer()
                    }
                }

                Panel(title: "Protocol") {
                    Text("Try these in order if saving is accepted but the keypad does not change.")
                        .font(Theme.rowDetail)
                        .foregroundStyle(Theme.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 10)

                    PickerRow(title: "Frame format") {
                        Picker("", selection: Binding(get: { model.protocolOverride },
                                                      set: { model.protocolOverride = $0 })) {
                            Text("Auto").tag(PadProtocol?.none)
                            ForEach(PadProtocol.allCases, id: \.self) { p in
                                Text(p.displayName).tag(PadProtocol?.some(p))
                            }
                        }
                        .labelsHidden().controlSize(.small).frame(width: 170)
                    }
                    PickerRow(title: "Channel") {
                        Picker("", selection: $model.channel) {
                            ForEach(ReportChannel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden().controlSize(.small).frame(width: 170)
                    }
                    PickerRow(title: "Report id") {
                        Picker("", selection: $model.reportId) {
                            ForEach([UInt8(0), 2, 3], id: \.self) { Text("\($0)").tag($0) }
                        }
                        .labelsHidden().controlSize(.small).frame(width: 170)
                    }
                    PickerRow(title: "Media encoding") {
                        Picker("", selection: $model.mediaEncoding) {
                            ForEach(MediaEncoding.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden().controlSize(.small).frame(width: 170)
                    }

                    PanelButton(title: "Probe report ids") { model.probeReportIds() }
                        .padding(.top, 10)
                }
            }
            .padding(Theme.gutter)
        }
    }
}

private struct SwitchRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.rowTitle).foregroundStyle(Theme.text)
                Text(detail).font(Theme.rowDetail).foregroundStyle(Theme.textFaint)
            }
            Spacer(minLength: 8)
            PanelSwitch(isOn: $isOn)
        }
        .frame(height: 44)
    }
}

private struct PickerRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(Theme.rowTitle).foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            control
        }
        .frame(height: 38)
    }
}

// MARK: - About

struct AboutSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    DotMatrixNumber(text: "MACROPAD", dot: 4, gap: 2, color: Theme.textOnWell)
                    Text("A native macOS configurator for cheap USB macro keypads.")
                        .font(Theme.rowDetail)
                        .foregroundStyle(Theme.textOnWellMuted)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .well(radius: Theme.radiusPanel)

                Panel(title: "This keypad") {
                    InfoRow(title: "Name", value: model.isConnected ? model.deviceLabel : "—")
                    InfoRow(title: "Layout", value: model.layout.name)
                    InfoRow(title: "Protocol", value: model.activeProtocol.displayName)
                    InfoRow(title: "Interface", value: model.selectedCandidate?.detail ?? "—")
                }

                Text("The wire protocol for this keypad family was read out of the vendor's own browser configurator and verified against the hardware.")
                    .font(Theme.rowDetail)
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.gutter)
        }
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(Theme.rowTitle).foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
        }
        .frame(height: 32)
    }
}

// MARK: - Panel container

/// A titled part of the panel. Everything on this screen sits in one.
struct Panel<Content: View>: View {
    let title: String
    var readout: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                PanelLabel(text: title, colour: Theme.textMuted)
                Spacer()
                if let readout { Readout(text: readout) }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lifted(radius: Theme.radiusPanel, depth: 0.9)
    }
}
