import SwiftUI
import MacroPadCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showLog = false
    @State private var showTemplates = false
    @AppStorage("hasSeenTemplates") private var hasSeenTemplates = false

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
            BottomBar(showLog: $showLog, showTemplates: $showTemplates)
        }
        .sheet(isPresented: $showTemplates) {
            TemplateGallery().environmentObject(model)
        }
        .onAppear {
            // Offer templates once, to a pad that has nothing on it yet.
            guard !hasSeenTemplates else { return }
            hasSeenTemplates = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if model.profile.configured(layerCount: model.layout.layerCount).isEmpty {
                    showTemplates = true
                }
            }
        }
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            DeviceCard()
            ProfileCard()

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
        .frame(height: 58)
    }
}

/// The keypad, named and described. The dot answers "is it plugged in" without
/// a click; the second line says what the app thinks it is talking to.
private struct DeviceCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var showing = false

    var body: some View {
        Pill(active: showing) {
            HStack(spacing: 9) {
                StatusDot(color: model.isConnected ? Theme.online : Theme.textFaint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.deviceLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(model.deviceDetail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
        } action: {
            showing.toggle()
        }
        .popover(isPresented: $showing, arrowEdge: Edge.bottom) {
            DevicePopover()
                .environmentObject(model)
        }
    }
}

private struct DevicePopover: View {
    @EnvironmentObject private var model: AppModel
    @State private var draftNickname = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Keypads")

            if model.visibleCandidates.isEmpty {
                EmptyStateView(icon: "cable.connector.slash",
                               title: "No keypad found",
                               message: "Plug one in — it should appear here within a second.")
            }

            ForEach(model.visibleCandidates) { candidate in
                Row(title: model.displayName(for: candidate),
                    subtitle: candidate.detail,
                    icon: "keyboard",
                    selected: candidate.id == model.selectedCandidateID,
                    action: {
                        model.selectedCandidateID = candidate.id
                        model.connect()
                        draftNickname = model.nickname(for: candidate) ?? ""
                    }) {
                    if candidate.id == model.selectedCandidateID {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            if let candidate = model.selectedCandidate {
                Divider().background(Theme.hairline).padding(.vertical, 8)
                SectionLabel(text: "Nickname")
                HStack(spacing: 7) {
                    TextField(candidate.product.isEmpty ? "My keypad" : candidate.product,
                              text: $draftNickname)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.fill))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.hairline))
                        .onSubmit { model.setNickname(draftNickname, for: candidate) }
                    BarAction(title: "Save", prominent: true) {
                        model.setNickname(draftNickname, for: candidate)
                    }
                }
                .padding(.horizontal, 9)
                Text("Only changes what this app calls it.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.horizontal, 9)
                    .padding(.top, 5)
            }

            Divider().background(Theme.hairline).padding(.vertical, 8)

            Toggle("Show every HID interface", isOn: $model.showAllInterfaces)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .padding(.horizontal, 9)

            HStack(spacing: 6) {
                BarAction(title: "Refresh") { model.refreshDevices() }
                BarAction(title: model.isConnected ? "Disconnect" : "Connect") {
                    model.isConnected ? model.disconnect() : model.connect()
                }
                Spacer()
            }
            .padding(.horizontal, 5)
            .padding(.top, 6)
        }
        .padding(.vertical, 8)
        .frame(width: 340)
        .background(PopoverBackground())
        .onAppear {
            draftNickname = model.selectedCandidate.flatMap { model.nickname(for: $0) } ?? ""
        }
    }
}

/// Profiles are whole sets of mappings. Switching one writes it to the keypad,
/// so the card says which set is currently loaded.
private struct ProfileCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var showing = false

    var body: some View {
        Pill(active: showing) {
            HStack(spacing: 9) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(model.activeProfileName == nil ? Theme.textFaint : Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(model.activeProfileName == nil && !model.loadedFromDevice
                                         ? Theme.textMuted : Theme.text)
                        .lineLimit(1)
                    Text(mappedSummary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
        } action: {
            showing.toggle()
        }
        .popover(isPresented: $showing, arrowEdge: Edge.bottom) {
            ProfilePopover()
                .environmentObject(model)
        }
    }

    /// Never leave the user guessing whether their mappings survived: say
    /// where what they are looking at came from.
    private var title: String {
        if let name = model.activeProfileName { return name }
        return model.loadedFromDevice ? "On the keypad" : "Unsaved changes"
    }

    private var mappedSummary: String {
        let n = model.profile.configured(layerCount: model.layout.layerCount).count
        let count = n == 0 ? "Nothing mapped" : (n == 1 ? "1 key mapped" : "\(n) keys mapped")
        if model.loadedFromDevice { return count + " · read from the keypad" }
        return count
    }
}

private struct ProfilePopover: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSaveSheet = false
    @State private var showRules = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Saved profiles")

            if model.profiles.isEmpty {
                EmptyStateView(icon: "square.stack.3d.up.slash",
                               title: "No profiles yet",
                               message: "Save the current mappings to switch between setups later.")
            }

            ForEach(model.profiles) { entry in
                Row(title: entry.name,
                    subtitle: "loads onto the keypad",
                    icon: "square.stack.3d.up",
                    selected: entry.name == model.activeProfileName,
                    action: { model.switchTo(entry) }) {
                    if entry.name == model.activeProfileName {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            Divider().background(Theme.hairline).padding(.vertical, 8)
            SectionLabel(text: "Manage")

            Row(title: "Save current mappings as…", icon: "plus.circle") {
                newName = model.activeProfileName ?? "New profile"
                showSaveSheet = true
            }
            if let active = model.profiles.first(where: { $0.name == model.activeProfileName }) {
                Row(title: "Update “\(active.name)”", icon: "arrow.triangle.2.circlepath") {
                    model.saveProfile(named: active.name)
                }
                Row(title: "Delete “\(active.name)”", icon: "trash", iconTint: Theme.accent) {
                    model.deleteProfile(active)
                }
            }

            Divider().background(Theme.hairline).padding(.vertical, 8)
            SectionLabel(text: "Automatic")

            Row(title: "Switch by app…",
                subtitle: model.autoSwitchEnabled ? "on, \(model.appRules.count) rule\(model.appRules.count == 1 ? "" : "s")" : "off",
                icon: "app.badge") {
                showRules = true
            }

            Divider().background(Theme.hairline).padding(.vertical, 8)
            SectionLabel(text: "Presets")

            Row(title: "Import preset…", subtitle: "from a file", icon: "square.and.arrow.down") {
                model.importPreset()
            }
            Row(title: "Export preset…", subtitle: "to a file", icon: "square.and.arrow.up") {
                model.exportPreset()
            }
        }
        .padding(.vertical, 8)
        .frame(width: 330)
        .background(PopoverBackground())
        .sheet(isPresented: $showSaveSheet) {
            SaveProfileSheet(name: $newName) { model.saveProfile(named: $0) }
        }
        .sheet(isPresented: $showRules) {
            AppRulesSheet().environmentObject(model)
        }
    }
}

private struct SaveProfileSheet: View {
    @Binding var name: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Name this profile")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            TextField("For example: Photoshop", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.fill))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.hairline))
                .onSubmit(save)
            HStack {
                Spacer()
                BarAction(title: "Cancel") { dismiss() }
                BarAction(title: "Save", keys: ["⏎"], prominent: true, action: save)
            }
        }
        .padding(16)
        .frame(width: 330)
        .background(PopoverBackground())
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
    @Binding var showTemplates: Bool

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

            BarAction(title: "Templates") { showTemplates = true }
            BarAction(title: "HID log", prominent: showLog) { showLog.toggle() }
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 18)
            BarAction(title: "Save this key", keys: ["⌥", "⌘", "S"]) { model.saveSelectedKey() }
            BarAction(title: "Save to keypad", keys: ["⌘", "S"], prominent: true) { model.saveToKeyboard() }
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
                               message: "Every frame written to the keypad shows up here, byte for byte.")
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
                        if let last = model.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
        .background(Color.black.opacity(0.18))
    }
}
