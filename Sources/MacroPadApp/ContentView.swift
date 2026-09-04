import SwiftUI
import MacroPadCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showLog = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Hairline()

            HStack(spacing: 0) {
                PadPane()
                    .frame(minWidth: 420, maxWidth: .infinity)
                Rectangle().fill(Theme.hairline).frame(width: 1)
                InspectorPane()
                    .frame(width: 372)
            }
            .frame(maxHeight: .infinity)

            if showLog {
                Hairline()
                LogPane()
                    .frame(height: 176)
            }

            Hairline()
            BottomBar(showLog: $showLog)
        }
        .background(Color.clear)
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            DeviceMenu()
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 18)
            ProfileMenu()

            Spacer(minLength: 12)

            if model.layout.layerCount > 1 {
                Segmented(selection: $model.layer,
                          items: (0..<Int(model.layout.layerCount)).map {
                              (UInt8($0), "Layer \($0 + 1)", nil)
                          })
            }
        }
        .padding(.leading, Theme.trafficLightInset)
        .padding(.trailing, Theme.gutter)
        .frame(height: Theme.barHeight)
    }
}

/// Device status and picker in one control — the dot answers "is it plugged
/// in", the menu answers everything else, so the common question costs no click.
private struct DeviceMenu: View {
    @EnvironmentObject private var model: AppModel
    @State private var hovering = false

    private var label: String {
        if let c = model.selectedCandidate, !c.product.isEmpty { return c.product }
        return model.candidates.isEmpty ? "No pad found" : "Select device"
    }

    var body: some View {
        Menu {
            if model.visibleCandidates.isEmpty {
                Text("No macro pad detected")
            }
            ForEach(model.visibleCandidates) { candidate in
                Button {
                    model.selectedCandidateID = candidate.id
                    model.connect()
                } label: {
                    Text(candidate.id == model.selectedCandidateID
                         ? "✓ \(candidate.displayName)" : candidate.displayName)
                }
            }
            Divider()
            if let c = model.selectedCandidate {
                Text(c.detail)
                Text("Protocol: \(model.activeProtocol.displayName) · report id \(model.reportId)")
            }
            Divider()
            Toggle("Show all HID interfaces", isOn: $model.showAllInterfaces)
            Button("Refresh") { model.refreshDevices() }
            Button(model.isConnected ? "Disconnect" : "Connect") {
                model.isConnected ? model.disconnect() : model.connect()
            }
        } label: {
            HStack(spacing: 7) {
                StatusDot(color: model.isConnected ? Theme.online : Theme.textFaint)
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(hovering ? Theme.rowHover : .clear)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { h in withAnimation(Theme.hover) { hovering = h } }
    }
}

private struct ProfileMenu: View {
    @EnvironmentObject private var model: AppModel
    @State private var hovering = false
    @State private var showSaveSheet = false
    @State private var newName = ""

    var body: some View {
        Menu {
            if model.profiles.isEmpty {
                Text("No saved profiles")
            }
            ForEach(model.profiles) { entry in
                Button {
                    model.switchTo(entry)
                } label: {
                    Text(entry.name == model.activeProfileName ? "✓ \(entry.name)" : entry.name)
                }
            }
            Divider()
            Button("Save as…") {
                newName = model.activeProfileName ?? model.profile.name
                showSaveSheet = true
            }
            if let active = model.profiles.first(where: { $0.name == model.activeProfileName }) {
                Button("Update “\(active.name)”") { model.saveProfile(named: active.name) }
                Divider()
                Button("Delete “\(active.name)”", role: .destructive) { model.deleteProfile(active) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textMuted)
                Text(model.activeProfileName ?? "Unsaved profile")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(model.activeProfileName == nil ? Theme.textMuted : Theme.text)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(hovering ? Theme.rowHover : .clear)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { h in withAnimation(Theme.hover) { hovering = h } }
        .sheet(isPresented: $showSaveSheet) {
            SaveProfileSheet(name: $newName) { name in
                model.saveProfile(named: name)
            }
        }
    }
}

private struct SaveProfileSheet: View {
    @Binding var name: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save profile")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.fill))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.hairline))
                .onSubmit { save() }
            HStack {
                Spacer()
                BarAction(title: "Cancel") { dismiss() }
                BarAction(title: "Save", keys: ["⏎"], prominent: true) { save() }
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(WindowBackground())
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}

// MARK: - Bottom bar

private struct BottomBar: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showLog: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.statusIsError ? "exclamationmark.triangle.fill" : "info.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(model.statusIsError ? Theme.warning : Theme.textFaint)
            Text(model.status)
                .font(.system(size: 12))
                .foregroundStyle(model.statusIsError ? Theme.text : Theme.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            BarAction(title: "HID log", keys: [], prominent: showLog) {
                showLog.toggle()
            }
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 18)
            BarAction(title: "Upload all", keys: ["⇧", "⌘", "U"]) { model.uploadAll() }
            BarAction(title: "Upload", keys: ["⌘", "U"], prominent: true) { model.uploadSelected() }
        }
        .padding(.horizontal, Theme.gutter)
        .frame(height: Theme.barHeight)
    }
}

// MARK: - Log

private struct LogPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("HID traffic")
                    .font(Theme.sectionLabel)
                    .tracking(0.3)
                    .foregroundStyle(Theme.textFaint)
                Spacer()
                Text("\(model.log.count)")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textFaint)
                BarAction(title: "Clear") { model.clearLog() }
            }
            .padding(.horizontal, Theme.gutter)
            .frame(height: 30)

            Hairline()

            if model.log.isEmpty {
                EmptyStateView(icon: "waveform",
                               title: "Nothing sent yet",
                               message: "Every frame written to the pad shows up here, byte for byte.")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(model.log) { entry in
                                HStack(alignment: .top, spacing: 7) {
                                    Text(entry.outgoing ? "→" : "←")
                                        .foregroundStyle(entry.ok
                                                         ? (entry.outgoing ? Theme.accent : Theme.online)
                                                         : Theme.warning)
                                    Text(entry.text)
                                        .foregroundStyle(entry.ok ? Theme.textMuted : Theme.text)
                                        .textSelection(.enabled)
                                }
                                .font(Theme.mono)
                                .padding(.vertical, 1.5)
                                .id(entry.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.gutter)
                        .padding(.vertical, 6)
                    }
                    .onChange(of: model.log.count) { _ in
                        // No animation: frames arrive in bursts during an upload.
                        if let last = model.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
        .background(Color.black.opacity(0.18))
    }
}
