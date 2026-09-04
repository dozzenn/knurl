import SwiftUI
import MacroPadCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsHeading("General")

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
                    SettingRow(title: "Count presses",
                               detail: "Watches only this keypad and tallies each key") {
                        Toggle("", isOn: $model.statsEnabled)
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                }
                .padding(.horizontal, 10)

                if model.statsEnabled {
                    HStack(spacing: 14) {
                        DotMatrixNumber(text: "\(model.totalPresses)", dot: 4, gap: 2,
                                        color: Theme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("presses on this keypad")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.textMuted)
                            Text("counted from its own keyboard interface, nothing else")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textFaint)
                        }
                        Spacer()
                        BarAction(title: "Reset") { model.resetStats() }
                    }
                    .padding(.horizontal, 19)
                    .padding(.top, 16)
                }

                Divider().background(Theme.hairline).padding(.vertical, 16)

                SettingsHeading("Protocol")
                Text("Try these in order if saving is accepted but the keypad does not change.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                VStack(spacing: 1) {
                    SettingRow(title: "Frame format",
                               detail: "How a mapping is packed into a report") {
                        Picker("", selection: Binding(get: { model.protocolOverride },
                                                      set: { model.protocolOverride = $0 })) {
                            Text("Auto").tag(PadProtocol?.none)
                            ForEach(PadProtocol.allCases, id: \.self) { p in
                                Text(p.displayName).tag(PadProtocol?.some(p))
                            }
                        }
                        .labelsHidden().controlSize(.small).frame(width: 160)
                    }
                    SettingRow(title: "Channel",
                               detail: "Output reports suit most firmware") {
                        Picker("", selection: $model.channel) {
                            ForEach(ReportChannel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden().controlSize(.small).frame(width: 160)
                    }
                    SettingRow(title: "Report id",
                               detail: "0 when the descriptor declares none") {
                        Picker("", selection: $model.reportId) {
                            ForEach([UInt8(0), 2, 3], id: \.self) { Text("\($0)").tag($0) }
                        }
                        .labelsHidden().controlSize(.small).frame(width: 160)
                    }
                    SettingRow(title: "Media encoding",
                               detail: "Firmware revisions disagree here") {
                        Picker("", selection: $model.mediaEncoding) {
                            ForEach(MediaEncoding.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden().controlSize(.small).frame(width: 160)
                    }
                }
                .padding(.horizontal, 10)

                HStack(spacing: 10) {
                    BarAction(title: "Probe report ids", prominent: true) { model.probeReportIds() }
                    Text("Writes an empty frame on each id and reports which ones the device takes.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 520, height: 560)
    }
}

private struct SettingsHeading: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .tracking(-0.2)
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 8)
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
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textFaint)
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 9)
        .frame(height: 46)
    }
}
