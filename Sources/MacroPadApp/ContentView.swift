import SwiftUI
import MacroPadCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showLog = false
    @State private var showTemplates = false
    @AppStorage("hasSeenTemplates") private var hasSeenTemplates = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar(showTemplates: $showTemplates)
            Hairline()
            ScopeBar()
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
    @Binding var showTemplates: Bool

    var body: some View {
        HStack(spacing: 8) {
            DeviceCard()

            Spacer(minLength: 12)

            BarAction(title: "Templates", prominent: true) { showTemplates = true }

            Menu {
                Button("Import preset…") { model.importPreset() }
                Button("Export preset…") { model.exportPreset() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)

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
            DevicePopover().environmentObject(model)
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

// MARK: - Scope bar

/// Which app the mappings below belong to. Global is the fallback; an app tab
/// holds keys that only apply while that app is in front.
struct ScopeBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.scopes) { scope in
                        ScopeChip(scope: scope)
                    }
                    AddAppChip()
                }
                .padding(.vertical, 1)
            }

            Spacer(minLength: 10)
            FollowToggle()
        }
        .padding(.leading, Theme.gutter)
        .padding(.trailing, Theme.gutter)
        .frame(height: 46)
    }
}

private struct ScopeChip: View {
    @EnvironmentObject private var model: AppModel
    let scope: MappingScope

    @State private var hovering = false

    private var selected: Bool { model.currentScopeKey == scope.key }
    private var isLive: Bool { model.liveScopeKey == scope.key && model.isConnected }

    var body: some View {
        HStack(spacing: 7) {
            if scope.isGlobal {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected ? Theme.text : Theme.textMuted)
            } else if let icon = appIcon {
                Image(nsImage: icon).resizable().frame(width: 15, height: 15)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
            }

            Text(scope.name)
                .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Theme.text : Theme.textMuted)
                .lineLimit(1)

            if isLive {
                Circle().fill(Theme.online).frame(width: 5, height: 5)
                    .help("This is what the keypad is holding right now")
            } else if !model.scopeHasMappings(scope) {
                Text("empty")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textFaint)
            }

            if !scope.isGlobal && selected {
                Button { model.removeScope(scope) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                }
                .buttonStyle(PressableStyle())
                .help("Remove this app")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Theme.fillStrong : (hovering ? Theme.rowHover : Theme.fill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Color.white.opacity(0.2) : Theme.hairline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture { model.selectScope(scope.key) }
        .onHover { h in withAnimation(Theme.hover) { hovering = h } }
    }

    private var appIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: scope.key) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private struct AddAppChip: View {
    @EnvironmentObject private var model: AppModel
    @State private var hovering = false

    var body: some View {
        Button(action: pickApp) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text("Add application")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(hovering ? Theme.text : Theme.textMuted)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Theme.rowHover : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            )
        }
        .buttonStyle(PressableStyle())
        .onHover { h in withAnimation(Theme.hover) { hovering = h } }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.title = "Choose an app"
        panel.message = "Keys you set for this app apply only while it is in front."
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        model.addAppScope(bundleId: id, name: name)
    }
}

/// Says plainly what the automation does, because "auto switch" on its own does
/// not tell you what switches or when.
private struct FollowToggle: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                Text("Follow the front app")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(model.autoSwitchEnabled ? Theme.text : Theme.textMuted)
                Text(model.autoSwitchEnabled
                     ? "keypad loads an app's keys when you switch to it"
                     : "keypad keeps whatever you last saved")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textFaint)
            }
            Toggle("", isOn: $model.autoSwitchEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
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
