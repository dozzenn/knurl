import AppKit
import UniformTypeIdentifiers
import ServiceManagement
import Combine
import SwiftUI
import MacroPadCore

enum EditorTab: String, CaseIterable, Identifiable {
    case keys, media, mouse, led
    var id: String { rawValue }
    var title: String {
        switch self {
        case .keys: return "Keys"
        case .media: return "Media"
        case .mouse: return "Mouse"
        case .led: return "LED"
        }
    }
    var icon: String {
        switch self {
        case .keys: return "keyboard"
        case .media: return "play.circle"
        case .mouse: return "computermouse"
        case .led: return "lightbulb"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {

    // MARK: Device

    @Published private(set) var candidates: [PadCandidate] = []
    @Published var selectedCandidateID: String?
    @Published private(set) var isConnected = false
    @Published var showAllInterfaces = false
    @Published private(set) var status = "Not connected"
    @Published private(set) var statusIsError = false

    // MARK: Transport settings

    @Published var protocolOverride: PadProtocol?
    @Published var reportId: UInt8 = 0
    @Published var channel: ReportChannel = .output
    @Published var mediaEncoding: MediaEncoding = .auto

    // MARK: Configuration

    @Published var layout: KeyboardLayout = LayoutLibrary.default {
        didSet { if layer >= layout.layerCount { layer = 0 } }
    }
    @Published var layer: UInt8 = 0 { didSet { loadEditor() } }
    @Published var selectedAction: InputAction = .key1 { didSet { loadEditor() } }
    @Published var profile = Profile()

    // MARK: Saved profiles

    @Published private(set) var profiles: [ProfileStore.Entry] = []
    @Published var activeProfileName: String? {
        didSet { UserDefaults.standard.set(activeProfileName, forKey: "activeProfileName") }
    }
    private let profileStore = ProfileStore()

    // MARK: Editor state

    @Published var editorTab: EditorTab = .keys
    @Published var sequence: [KeyStroke] = []
    @Published var delay: UInt16 = 0
    @Published var mediaKey: MediaKey = MediaKey.all[0]
    @Published var mouseButton: MouseButton = .left
    @Published var mouseModifiers: Modifier = .none
    @Published var isRecording = false { didSet { isRecording ? startRecording() : stopRecording() } }

    // MARK: Log

    @Published private(set) var log: [HIDLogEntry] = []

    private let transport = PadTransport()
    private var recorderMonitor: Any?

    /// Per-device nicknames, keyed by vendor:product so the name survives
    /// unplugging and re-plugging.
    @Published private var nicknames: [String: String] = [:]
    private static let nicknameKey = "deviceNicknames"

    var visibleCandidates: [PadCandidate] {
        showAllInterfaces ? candidates : candidates.filter(\.isLikelyPad)
    }

    var selectedCandidate: PadCandidate? {
        candidates.first { $0.id == selectedCandidateID }
    }

    // MARK: - Device names

    private func nicknameKey(for candidate: PadCandidate) -> String {
        String(format: "%04X:%04X", candidate.vendorId, candidate.productId)
    }

    func nickname(for candidate: PadCandidate) -> String? {
        nicknames[nicknameKey(for: candidate)]
    }

    func setNickname(_ name: String?, for candidate: PadCandidate) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = nicknameKey(for: candidate)
        if let trimmed, !trimmed.isEmpty {
            nicknames[key] = trimmed
        } else {
            nicknames.removeValue(forKey: key)
        }
        UserDefaults.standard.set(nicknames, forKey: Self.nicknameKey)
    }

    /// What a device is called: the nickname the user gave it, else the name it
    /// reports, else a placeholder.
    func displayName(for candidate: PadCandidate) -> String {
        if let n = nickname(for: candidate) { return n }
        return candidate.product.isEmpty ? "HID device" : candidate.product
    }

    var deviceLabel: String {
        guard let c = selectedCandidate else {
            return candidates.isEmpty ? "No keypad found" : "Choose keypad"
        }
        return displayName(for: c)
    }

    /// One line under the device name: what it is and how many keys it has.
    var deviceDetail: String {
        guard let c = selectedCandidate else { return "Plug one in to get started" }
        let keys = layout.controls.filter { if case .button = $0.kind { return true }; return false }.count
        let knobs = layout.controls.count - keys
        var parts = ["\(keys) keys"]
        if knobs > 0 { parts.append(knobs == 1 ? "1 knob" : "\(knobs) knobs") }
        parts.append(activeProtocol.displayName)
        _ = c
        return parts.joined(separator: " · ")
    }

    /// Protocol actually used for composing: explicit override, else the
    /// known-device table, else Extended (what most current devices speak).
    var activeProtocol: PadProtocol {
        protocolOverride ?? selectedCandidate?.knownProtocol ?? .extended
    }

    var composer: ReportComposer {
        ComposerFactory.make(activeProtocol, reportId: reportId, mediaEncoding: mediaEncoding)
    }

    /// Keystrokes one mapping can hold, given both the device layout and what
    /// the protocol itself can express.
    var maxKeystrokes: Int {
        min(layout.maxCharacters, activeProtocol.maxKeystrokesPerControl)
    }

    /// Which editors this protocol can actually write. Showing a control that
    /// silently does nothing is worse than saying it is not supported yet.
    func supports(_ tab: EditorTab) -> Bool {
        guard activeProtocol == .webHub else { return true }
        switch tab {
        case .keys, .media, .led: return true
        case .mouse: return false
        }
    }

    var unsupportedNote: String? {
        guard activeProtocol == .webHub, !supports(editorTab) else { return nil }
        return "Mouse actions are not supported on this device yet — its encoding for them has not been worked out, and writing a guess would corrupt the key table."
    }

    init() {
        transport.onDeviceListChanged = { [weak self] in
            Task { @MainActor in self?.deviceListChanged() }
        }
        transport.onLog = { [weak self] entry in
            Task { @MainActor in self?.append(entry) }
        }
        nicknames = (UserDefaults.standard.dictionary(forKey: Self.nicknameKey) as? [String: String]) ?? [:]
        activeProfileName = UserDefaults.standard.string(forKey: "activeProfileName")
        transport.startMonitoring()
        deviceListChanged()
        refreshProfiles()
        loadEditor()
    }

    // MARK: - Device handling

    private func deviceListChanged() {
        candidates = transport.candidates
        isConnected = transport.isOpen
        if selectedCandidate == nil {
            selectedCandidateID = transport.bestCandidate?.id
            adoptLayoutForSelection()
        }
        if !isConnected && transport.openedCandidate == nil && status.hasPrefix("Connected") {
            setStatus("Device disconnected", error: true)
        }
    }

    private func adoptLayoutForSelection() {
        guard let c = selectedCandidate else { return }
        if let match = LayoutLibrary.best(forVendorId: c.vendorId, productId: c.productId) {
            layout = match
        }
    }

    func refreshDevices() {
        transport.refresh()
        deviceListChanged()
    }

    func connect() {
        guard let candidate = selectedCandidate ?? transport.bestCandidate else {
            setStatus("No macro pad found", error: true)
            return
        }
        selectedCandidateID = candidate.id
        switch transport.open(candidate) {
        case .success:
            isConnected = true
            adoptLayoutForSelection()
            setStatus("Connected — \(displayName(for: candidate)), \(activeProtocol.displayName)")
            syncFromDevice()
        case .failure(let error):
            isConnected = false
            setStatus(error.localizedDescription, error: true)
        }
    }

    func disconnect() {
        transport.close()
        isConnected = false
        setStatus("Not connected")
    }

    // MARK: - Reading the keypad

    private var pendingReplies: [[UInt8]] = []

    /// True while the editor is showing exactly what was read off the keypad.
    @Published private(set) var loadedFromDevice = false

    private func matchingProfileName(for candidate: Profile) -> String? {
        for entry in profiles {
            guard let saved = try? ProfileStore().load(entry) else { continue }
            if saved.bindings == candidate.bindings { return entry.name }
        }
        return nil
    }

    /// Pulls what is actually stored on the keypad into the editor.
    ///
    /// Without this the window opens showing an empty profile next to a keypad
    /// that is full of mappings, which reads as "my mappings are gone".
    func syncFromDevice() {
        guard activeProtocol == .webHub, isConnected else { return }
        pendingReplies.removeAll()
        transport.onInputReport = { [weak self] bytes in
            Task { @MainActor in self?.pendingReplies.append(bytes) }
        }

        for block in 0..<3 {
            _ = transport.write(WebHubComposer.keyTableRequest(blockOffset: block * 56, layer: layer),
                                channel: channel)
            usleep(60_000)
        }
        _ = transport.write(WebHubComposer.backlightRequest(), channel: channel)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.applyReplies()
        }
    }

    private func applyReplies() {
        transport.onInputReport = nil
        let replies = pendingReplies
        pendingReplies.removeAll()

        if let lightReply = replies.first(where: { $0.count > 1 && $0[0] == 0xAA && $0[1] == 10 }),
           let light = BacklightState(reply: lightReply) {
            backlight = light
            backlightIsLive = true
        }

        // Key table blocks arrive in request order and each carries 56 payload
        // bytes from index 8.
        var table: [UInt8] = []
        for r in replies where r.count > 8 && r.first == 0xAA && r[1] == 8 {
            table.append(contentsOf: r[8...])
        }
        guard table.count >= 4 else { return }

        var found = 0
        var restored = Profile(name: profile.name, layoutName: layout.name)
        for i in 0..<(table.count / 4) {
            let entry = Array(table[(i * 4)..<(i * 4 + 4)])
            guard let action = WebHubComposer.action(forKeyIndex: i),
                  let binding = WebHubComposer.binding(fromEntry: entry) else { continue }
            restored[layer, action] = binding
            found += 1
        }
        guard found > 0 else { return }

        restored.ledMode = profile.ledMode
        restored.ledColor = profile.ledColor
        profile = restored
        loadedFromDevice = true

        // If what the keypad holds is exactly one of the saved profiles, say so;
        // otherwise the card says the mappings came off the hardware rather than
        // implying unsaved edits.
        activeProfileName = matchingProfileName(for: restored)
        loadEditor()
        setStatus("Read \(found) mapping\(found == 1 ? "" : "s") from the keypad")
    }

    // MARK: - Editor <-> profile

    var currentBinding: ControlBinding {
        profile[layer, selectedAction]
    }

    private func loadEditor() {
        switch currentBinding {
        case .unset:
            sequence = []
            delay = 0
            editorTab = .keys
        case .keys(let seq, let d):
            sequence = seq
            delay = d
            editorTab = .keys
        case .media(let key):
            mediaKey = key
            editorTab = .media
        case .mouse(let button, let mods):
            mouseButton = button
            mouseModifiers = mods
            editorTab = .mouse
        }
    }

    /// Writes the editor state back into the profile for the selected control.
    func commit() {
        loadedFromDevice = false
        switch editorTab {
        case .keys:
            profile[layer, selectedAction] = sequence.isEmpty ? .unset : .keys(sequence: sequence, delay: delay)
        case .media:
            profile[layer, selectedAction] = .media(mediaKey)
        case .mouse:
            profile[layer, selectedAction] = .mouse(button: mouseButton, modifiers: mouseModifiers)
        case .led:
            break   // LED is device-wide, not per control
        }
    }

    func clearBinding() {
        loadedFromDevice = false
        sequence = []
        delay = 0
        profile[layer, selectedAction] = .unset
    }

    func binding(for action: InputAction) -> ControlBinding {
        profile[layer, action]
    }

    // MARK: - Recording

    private func startRecording() {
        guard recorderMonitor == nil else { return }
        recorderMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            self.record(event)
            return nil   // swallow the key so it doesn't reach the UI
        }
    }

    private func stopRecording() {
        if let m = recorderMonitor { NSEvent.removeMonitor(m) }
        recorderMonitor = nil
    }

    private func record(_ event: NSEvent) {
        // Escape leaves the mode. Escape itself can still be mapped from the
        // key picker, which is the only way to reach several keys anyway.
        if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            isRecording = false
            return
        }
        guard sequence.count < maxKeystrokes else {
            setStatus(maxKeystrokes == 1
                      ? "This device stores one keystroke per key — clear it to record a different one"
                      : "This device holds at most \(maxKeystrokes) keystrokes", error: true)
            return
        }
        guard let usage = HIDKeyboard.virtualKeyToUsage[event.keyCode] else { return }

        var mods = HIDKeyboard.modifiers(from: event.modifierFlags.rawValue)
        if mods.isEmpty {
            // Fall back to the layout-independent flags if the device-specific
            // bits are missing (some synthetic events don't carry them).
            let f = event.modifierFlags
            if f.contains(.control) { mods.insert(.leftCtrl) }
            if f.contains(.shift) { mods.insert(.leftShift) }
            if f.contains(.option) { mods.insert(.leftAlt) }
            if f.contains(.command) { mods.insert(.leftGui) }
        }

        sequence.append(KeyStroke(usage: usage, modifiers: mods))
        editorTab = .keys
        commit()
    }

    func addKey(usage: UInt8, modifiers: Modifier) {
        guard sequence.count < maxKeystrokes else { return }
        sequence.append(KeyStroke(usage: usage, modifiers: modifiers))
        commit()
    }

    func removeLastKey() {
        guard !sequence.isEmpty else { return }
        sequence.removeLast()
        commit()
    }

    // MARK: - Upload

    /// Writes just the selected control to the hardware.
    func saveSelectedKey() {
        isRecording = false
        guard ensureConnected() else { return }
        commit()

        if editorTab == .led, activeProtocol == .webHub {
            applyBacklight()
            return
        }

        let reports: [PadReport]
        if editorTab == .led {
            reports = composer.led(layer: layer, mode: profile.ledMode, color: profile.ledColor)
            if reports.isEmpty {
                setStatus("This firmware only supports LED modes 0–2", error: true)
                return
            }
        } else {
            guard selectedAction != .none else {
                setStatus("Select a key or knob action first", error: true)
                return
            }
            if let note = unsupportedNote {
                setStatus(note, error: true)
                return
            }
            if case .unset = currentBinding, let webhub = composer as? WebHubComposer {
                // "Nothing" is a real state on this protocol: write the disabled entry.
                reports = webhub.clear(action: selectedAction, layer: layer)
            } else {
                reports = composer.reports(for: currentBinding, action: selectedAction, layer: layer)
            }
            if reports.isEmpty {
                setStatus("Nothing mapped to \(selectedAction.displayName)", error: true)
                return
            }
        }
        send(reports, describing: editorTab == .led ? "backlight" : selectedAction.displayName)
    }

    /// Writes the whole profile to the hardware — the everyday action.
    func saveToKeyboard() {
        isRecording = false
        guard ensureConnected() else { return }
        commit()

        var reports: [PadReport] = []
        for entry in profile.configured(layerCount: layout.layerCount) {
            reports.append(contentsOf: composer.reports(for: entry.binding, action: entry.action, layer: entry.layer))
        }
        reports.append(contentsOf: composer.led(layer: layer, mode: profile.ledMode, color: profile.ledColor))
        guard !reports.isEmpty else {
            setStatus("Nothing to save yet — map a key first", error: true)
            return
        }
        let n = profile.configured(layerCount: layout.layerCount).count
        send(reports, describing: n == 1 ? "1 key" : "\(n) keys")
    }

    private func ensureConnected() -> Bool {
        if isConnected { return true }
        connect()
        return isConnected
    }

    private func send(_ reports: [PadReport], describing what: String) {
        for report in reports {
            if case .failure(let error) = transport.write(report, channel: channel) {
                setStatus("Could not save: \(error.localizedDescription)", error: true)
                return
            }
            // The firmware drops frames that arrive back to back.
            usleep(15_000)
        }
        setStatus("Saved \(what) to the keypad")
    }

    /// Sends a zero frame on each report id to see which ones the device takes.
    func probeReportIds() {
        guard ensureConnected() else { return }
        let accepted = ReportChannel.allCases.flatMap { ch in
            ([0, 2, 3] as [UInt8]).compactMap { id -> String? in
                if case .success = transport.write(ComposerFactory.versionProbe(reportId: id), channel: ch) {
                    return "\(ch.rawValue) id \(id)"
                }
                return nil
            }
        }
        setStatus(accepted.isEmpty ? "No report id accepted" : "Accepted: \(accepted.joined(separator: ", "))",
                  error: accepted.isEmpty)
    }

    // MARK: - Saved profiles

    func refreshProfiles() {
        profiles = profileStore.list()
    }

    /// Loads a saved profile and, when a pad is connected, pushes it straight to
    /// the hardware — switching profiles is the whole point of having them.
    func switchTo(_ entry: ProfileStore.Entry) {
        do {
            let loaded = try profileStore.load(entry)
            profile = loaded
            activeProfileName = entry.name
            loadedFromDevice = false
            if let match = LayoutLibrary.all.first(where: { $0.name == loaded.layoutName }) { layout = match }
            loadEditor()
            if isConnected {
                saveToKeyboard()
            } else {
                setStatus("Loaded “\(entry.name)” — connect the pad to apply it")
            }
        } catch {
            setStatus("Could not open “\(entry.name)”: \(error.localizedDescription)", error: true)
        }
    }

    func saveProfile(named name: String) {
        commit()
        var p = profile
        p.layoutName = layout.name
        do {
            let entry = try profileStore.save(p, as: name)
            profile.name = name
            activeProfileName = entry.name
            refreshProfiles()
            setStatus("Saved “\(entry.name)”")
        } catch {
            setStatus("Could not save: \(error.localizedDescription)", error: true)
        }
    }

    func deleteProfile(_ entry: ProfileStore.Entry) {
        do {
            try profileStore.delete(entry)
            if activeProfileName == entry.name { activeProfileName = nil }
            refreshProfiles()
            setStatus("Deleted “\(entry.name)”")
        } catch {
            setStatus("Could not delete: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: - Backlight

    @Published var backlight = BacklightState()
    @Published private(set) var backlightIsLive = false

    func applyBacklight() {
        guard let webhub = composer as? WebHubComposer else {
            setStatus("Backlight is not supported on this device", error: true)
            return
        }
        guard ensureConnected() else { return }
        send(webhub.backlight(backlight), describing: "backlight")
    }

    // MARK: - Open at login

    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            setStatus(launchAtLogin ? "MacroPad will open at login" : "MacroPad will not open at login")
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            setStatus("Could not change the login item: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: - Menu bar and hot key

    @Published var hotKeyEnabled: Bool = UserDefaults.standard.object(forKey: "hotKeyEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(hotKeyEnabled, forKey: "hotKeyEnabled")
            applyHotKey()
        }
    }

    @Published var hideDockIcon: Bool = UserDefaults.standard.bool(forKey: "hideDockIcon") {
        didSet {
            UserDefaults.standard.set(hideDockIcon, forKey: "hideDockIcon")
            applyActivationPolicy()
        }
    }

    private var hotKey: GlobalHotKey?

    /// Registered late enough that a failure (another app already owns the
    /// combination) can be reported instead of silently doing nothing.
    func applyHotKey() {
        hotKey = nil
        guard hotKeyEnabled else { return }
        hotKey = GlobalHotKey(.default) {
            PaletteController.shared.toggle()
        }
        if hotKey == nil {
            setStatus("Could not register ⌃⌥⌘K — another app is already using it", error: true)
        }
    }

    func applyActivationPolicy() {
        NSApp.setActivationPolicy(hideDockIcon ? .accessory : .regular)
    }

    var hotKeyDisplay: [String] { GlobalHotKey.Combination.default.display }

    // MARK: - Command palette

    /// Everything the palette can run. Profiles come first because switching
    /// the whole keypad in one keystroke is the reason the palette exists.
    var paletteCommands: [PaletteCommand] {
        var out: [PaletteCommand] = []

        for entry in profiles {
            out.append(PaletteCommand(
                id: "profile:\(entry.id)",
                title: entry.name,
                subtitle: entry.name == activeProfileName ? "already loaded" : "load onto the keypad",
                icon: "square.stack.3d.up",
                group: "Profiles",
                run: { [weak self] in self?.switchTo(entry) }
            ))
        }

        out.append(PaletteCommand(
            id: "save.all",
            title: "Save to keypad",
            subtitle: "write every mapping in this profile",
            icon: "arrow.down.circle",
            group: "Actions",
            keys: ["⌘", "S"],
            run: { [weak self] in self?.saveToKeyboard() }
        ))
        out.append(PaletteCommand(
            id: "device.toggle",
            title: isConnected ? "Disconnect keypad" : "Connect keypad",
            subtitle: isConnected ? deviceLabel : "look for a keypad and open it",
            icon: isConnected ? "cable.connector.slash" : "cable.connector",
            group: "Actions",
            run: { [weak self] in
                guard let self else { return }
                self.isConnected ? self.disconnect() : self.connect()
            }
        ))
        out.append(PaletteCommand(
            id: "window.open",
            title: "Open MacroPad",
            subtitle: "the full editor",
            icon: "macwindow",
            group: "Actions",
            run: { NSApp.activate(ignoringOtherApps: true)
                   NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil) }
        ))
        out.append(PaletteCommand(
            id: "preset.import",
            title: "Import preset…",
            icon: "square.and.arrow.down",
            group: "Presets",
            run: { [weak self] in self?.importPreset() }
        ))
        out.append(PaletteCommand(
            id: "preset.export",
            title: "Export preset…",
            icon: "square.and.arrow.up",
            group: "Presets",
            run: { [weak self] in self?.exportPreset() }
        ))
        return out
    }

    // MARK: - Presets

    /// Writes the current profile to a file the user picks, so it can be moved
    /// between Macs or shared.
    func exportPreset() {
        commit()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(activeProfileName ?? "MacroPad preset").json"
        panel.title = "Export preset"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var p = profile
            p.layoutName = layout.name
            p.name = activeProfileName ?? p.name
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(p).write(to: url, options: .atomic)
            setStatus("Exported to \(url.lastPathComponent)")
        } catch {
            setStatus("Export failed: \(error.localizedDescription)", error: true)
        }
    }

    /// Loads a preset file into the editor. It is not written to the keypad
    /// until the user saves, so an imported preset can be reviewed first.
    func importPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = "Import preset"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let p = try JSONDecoder().decode(Profile.self, from: Data(contentsOf: url))
            profile = p
            activeProfileName = nil
            if let match = LayoutLibrary.all.first(where: { $0.name == p.layoutName }) { layout = match }
            loadEditor()
            setStatus("Imported \(url.lastPathComponent) — review it, then Save to keypad")
        } catch {
            setStatus("Import failed: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: - Status & log

    private func setStatus(_ text: String, error: Bool = false) {
        status = text
        statusIsError = error
    }

    private func append(_ entry: HIDLogEntry) {
        log.append(entry)
        if log.count > 400 { log.removeFirst(log.count - 400) }
    }

    func clearLog() { log.removeAll() }
}
