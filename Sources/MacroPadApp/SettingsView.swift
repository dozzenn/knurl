import SwiftUI
import MacroPadCore

/// The escape hatch for firmware differences. Nothing here is needed on a
/// device the app already recognises, so it lives one level down — but when a
/// pad ignores uploads, this is the whole fix, so it stays plain and ordered
/// the way you would try things.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Protocol")
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 4)

            Text("Try these in order if uploads are accepted but the pad does not change.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            VStack(spacing: 1) {
                SettingRow(title: "Frame format", detail: "How a mapping is packed into a report") {
                    Picker("", selection: Binding(
                        get: { model.protocolOverride },
                        set: { model.protocolOverride = $0 }
                    )) {
                        Text("Auto").tag(PadProtocol?.none)
                        ForEach(PadProtocol.allCases, id: \.self) { p in
                            Text(p.displayName).tag(PadProtocol?.some(p))
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 150)
                }

                SettingRow(title: "Channel", detail: "Output reports suit most firmware") {
                    Picker("", selection: $model.channel) {
                        ForEach(ReportChannel.allCases, id: \.self) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 150)
                }

                SettingRow(title: "Report id", detail: "0 when the descriptor declares none") {
                    Picker("", selection: $model.reportId) {
                        ForEach([UInt8(0), 2, 3], id: \.self) { Text("\($0)").tag($0) }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 150)
                }

                SettingRow(title: "Media encoding", detail: "Firmware revisions disagree here") {
                    Picker("", selection: $model.mediaEncoding) {
                        ForEach(MediaEncoding.allCases, id: \.self) { e in
                            Text(e.displayName).tag(e)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 150)
                }
            }
            .padding(.horizontal, 10)

            Divider().background(Theme.hairline).padding(.vertical, 14)

            HStack(spacing: 8) {
                BarAction(title: "Probe report ids", prominent: true) { model.probeReportIds() }
                Text("Writes an empty frame on each id and reports which ones the device takes.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 16)
        }
        .frame(width: 480, height: 400)
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
        .frame(height: 44)
    }
}
