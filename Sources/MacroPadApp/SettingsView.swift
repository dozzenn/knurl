import SwiftUI
import MacroPadCore

/// Settings in the shape a Mac user expects: a sidebar of sections on the left,
/// one section's controls on the right. Everything the app can be told to do
/// is reachable from here, so nothing hides behind a menu the user has to guess at.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var section: Section = .general

    enum Section: String, CaseIterable, Identifiable {
        case general, keypad, backlight, stats, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .keypad: return "Keypad"
            case .backlight: return "Backlight"
            case .stats: return "Stats"
            case .about: return "About"
            }
        }
        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .keypad: return "keyboard.fill"
            case .backlight: return "lightbulb.fill"
            case .stats: return "chart.bar.fill"
            case .about: return "info.circle.fill"
            }
        }
        var tint: Color {
            switch self {
            case .general: return Color(red: 0.55, green: 0.56, blue: 0.60)
            case .keypad: return Color(red: 0.36, green: 0.55, blue: 0.95)
            case .backlight: return Color(red: 0.95, green: 0.62, blue: 0.25)
            case .stats: return Color(red: 0.28, green: 0.78, blue: 0.60)
            case .about: return Color(red: 0.62, green: 0.45, blue: 0.90)
            }
        }
        /// Sections that are settings for the device rather than for the app.
        var group: String { self == .general || self == .about ? "MacroPad" : "Device" }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.hairline).frame(width: 1)
            detail
        }
        .frame(width: 720, height: 500)
        .background(WindowBackground())
        .preferredColorScheme(.dark)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarRow(section: .general, selected: section == .general) { section = .general }
                .padding(.top, 14)

            groupLabel("Device")
            ForEach([Section.keypad, .backlight, .stats]) { s in
                SidebarRow(section: s, selected: section == s) { section = s }
            }

            groupLabel("MacroPad")
            SidebarRow(section: .about, selected: section == .about) { section = .about }

            Spacer()
        }
        .padding(.horizontal, 9)
        .frame(width: 208)
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.sectionLabel)
            .tracking(0.3)
            .foregroundStyle(Theme.textFaint)
            .padding(.horizontal, 10)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    // MARK: Detail

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: section.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(section.tint))
                    Text(section.title)
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Theme.text)
                }
                .padding(.bottom, 14)

                switch section {
                case .general: general
                case .keypad: keypad
                case .backlight: backlight
                case .stats: stats
                case .about: about
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var general: some View {
        VStack(spacing: 1) {
            SettingRow(title: "Open at login",
                       detail: "Start MacroPad when you log in") {
                Toggle("", isOn: Binding(get: { model.launchAtLogin },
                                         set: { model.setLaunchAtLogin($0) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            SettingRow(title: "Menu bar only",
                       detail: "Hide the Dock icon and live in the menu bar") {
                Toggle("", isOn: $model.hideDockIcon)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            SettingRow(title: "Follow the front app",
                       detail: "Load an app's keys onto the keypad when you switch to it") {
                Toggle("", isOn: $model.autoSwitchEnabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
        }
    }

    private var keypad: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Try these in order if saving is accepted but the keypad does not change.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            VStack(spacing: 1) {
                SettingRow(title: "Frame format", detail: "How a mapping is packed into a report") {
                    Picker("", selection: Binding(get: { model.protocolOverride },
                                                  set: { model.protocolOverride = $0 })) {
                        Text("Auto").tag(PadProtocol?.none)
                        ForEach(PadProtocol.allCases, id: \.self) { p in
                            Text(p.displayName).tag(PadProtocol?.some(p))
                        }
                    }
                    .labelsHidden().controlSize(.small).frame(width: 170)
                }
                SettingRow(title: "Channel", detail: "Output reports suit most firmware") {
                    Picker("", selection: $model.channel) {
                        ForEach(ReportChannel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden().controlSize(.small).frame(width: 170)
                }
                SettingRow(title: "Report id", detail: "0 when the descriptor declares none") {
                    Picker("", selection: $model.reportId) {
                        ForEach([UInt8(0), 2, 3], id: \.self) { Text("\($0)").tag($0) }
                    }
                    .labelsHidden().controlSize(.small).frame(width: 170)
                }
                SettingRow(title: "Media encoding", detail: "Firmware revisions disagree here") {
                    Picker("", selection: $model.mediaEncoding) {
                        ForEach(MediaEncoding.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden().controlSize(.small).frame(width: 170)
                }
            }

            HStack(spacing: 10) {
                BarAction(title: "Probe report ids", prominent: true) { model.probeReportIds() }
                Text("Writes an empty frame on each id and reports which the device takes.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 14)
        }
    }

    private var backlight: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The backlight is edited on the LED tab in the main window; these are the limits this firmware imposes.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 1) {
                SettingRow(title: "Speed range", detail: "0–4, except Tide which only steps evenly to 2") {
                    Text("0–\(BacklightState.maxSpeed)")
                        .font(Theme.mono).foregroundStyle(Theme.textMuted)
                }
                SettingRow(title: "Brightness", detail: "Written and read back, but has no visible effect on this keypad") {
                    Text("not offered")
                        .font(Theme.mono).foregroundStyle(Theme.textFaint)
                }
            }
        }
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 1) {
                SettingRow(title: "Count presses",
                           detail: "Watches this keypad's own interface, nothing else you type") {
                    Toggle("", isOn: $model.statsEnabled)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }

            if model.statsEnabled {
                HStack(spacing: 16) {
                    DotMatrixNumber(text: "\(model.totalPresses)", dot: 5, gap: 2.5, color: Theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("presses")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textMuted)
                        Text("attributed by matching each report to your mappings")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textFaint)
                    }
                    Spacer()
                    BarAction(title: "Reset") { model.resetStats() }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .recessed(radius: 12)

                VStack(spacing: 1) {
                    ForEach(model.layout.controls) { control in
                        ForEach(control.actions, id: \.self) { action in
                            if model.presses(for: action) > 0 {
                                SettingRow(title: action.displayName,
                                           detail: model.binding(for: action).summary) {
                                    DotMatrixNumber(text: "\(model.presses(for: action))",
                                                    dot: 2.5, gap: 1.4, color: Theme.textMuted)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.text)
                    .frame(width: 46, height: 46)
                    .raised(radius: 11, depth: 0.7)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacroPad")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("A native macOS configurator for cheap USB macro keypads.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textMuted)
                }
            }

            VStack(spacing: 1) {
                SettingRow(title: "Connected keypad",
                           detail: model.isConnected ? model.deviceDetail : "nothing connected") {
                    Text(model.isConnected ? model.deviceLabel : "—")
                        .font(Theme.mono).foregroundStyle(Theme.textMuted)
                }
                SettingRow(title: "Protocol", detail: "worked out from the vendor's own configurator") {
                    Text(model.activeProtocol.displayName)
                        .font(Theme.mono).foregroundStyle(Theme.textMuted)
                }
            }
        }
    }
}

private struct SidebarRow: View {
    let section: SettingsView.Section
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 21, height: 21)
                    .background(RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                        .fill(section.tint))
                Text(section.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.text : Theme.textMuted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Theme.fillStrong : (hovering ? Theme.rowHover : .clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Theme.hover) { hovering = h } }
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.text)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 46)
    }
}
