import AppKit
import UniformTypeIdentifiers
import ServiceManagement
import Combine
import SwiftUI
import KnurlCore

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
        Migration.runIfNeeded()
        nicknames = (UserDefaults.standard.dictionary(forKey: Self.nicknameKey) as? [String: String]) ?? [:]
        scopes = scopeStore.scopes
        profile = scopeStore.profile(for: currentScopeKey)
        if autoSwitchEnabled { startWatchingApps() }
        refreshPresets()
        applyAppearance()
        transport.startMonitoring()
        deviceListChanged()
        for delay in [0.35, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshDevices()
            }
        }
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
        autoConnectIfPossible()
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

    /// Opens a recognised keypad without being asked.
    ///
    /// IOKit's device list is not complete the instant the manager opens, so the
    /// first look at launch can come up empty; this runs again on the hot-plug
    /// callback and on a couple of short delays after start-up.
    private func autoConnectIfPossible() {
        guard !isConnected, let candidate = selectedCandidate ?? transport.bestCandidate else { return }
        guard candidate.isKnownHardware || candidate.isVendorInterface else { return }
        selectedCandidateID = candidate.id
        if case .success = transport.open(candidate) {
            isConnected = true
            adoptLayoutForSelection()
            setStatus("Connected — \(displayName(for: candidate)), \(activeProtocol.displayName)")
            syncFromDevice()
        }
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

        // Adopt what the hardware holds only when this scope is empty. Once the
        // user has set keys here, their work outranks whatever the pad happens
        // to be carrying — overwriting it on connect would destroy it.
        guard profile.configured(layerCount: layout.layerCount).isEmpty else {
            setStatus("Keypad is holding \(found) mapping\(found == 1 ? "" : "s") — Save to write what you see here")
            return
        }

        restored.ledMode = profile.ledMode
        restored.ledColor = profile.ledColor
        profile = restored
        loadedFromDevice = true
        persistCurrentScope()
        loadEditor()
        setStatus("Read \(found) mapping\(found == 1 ? "" : "s") off the keypad")
    }

    /// Which knob the selection belongs to, if any.
    var selectedKnobIndex: Int? {
        guard selectedAction.rawValue >= 23 else { return nil }
        return (Int(selectedAction.rawValue) - 23) / 3 + 1
    }

    var selectedKnobPart: KnobPart? {
        guard selectedAction.rawValue >= 23 else { return nil }
        return KnobPart(rawValue: (Int(selectedAction.rawValue) - 23) % 3)
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

    // MARK: - Watching the keypad live

    /// The control the keypad just fired, so the drawing of it can react.
    ///
    /// This works without any permission because it watches the app's own key
    /// events: while the window is focused, a press on the pad arrives here the
    /// same way any keystroke does. It follows that it only works while Knurl
    /// is in front — and that a knob mapped to volume will not show, because
    /// the system takes media keys before an app sees them.
    @Published private(set) var livePress: InputAction?

    private var liveMonitor: Any?
    private var liveClearWork: DispatchWorkItem?

    func startLiveWatch() {
        guard liveMonitor == nil else { return }
        liveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, !self.isRecording else { return event }
            let usage = HIDKeyboard.virtualKeyToUsage[event.keyCode]
            let mods = HIDKeyboard.modifiers(from: event.modifierFlags.rawValue)
            if let usage, let action = self.action(matchingUsage: usage, modifiers: mods) {
                self.flash(action)
                return nil   // it was the pad talking to us, not a shortcut
            }
            return event
        }
    }

    func stopLiveWatch() {
        if let liveMonitor { NSEvent.removeMonitor(liveMonitor) }
        liveMonitor = nil
        livePress = nil
    }

    private func flash(_ action: InputAction) {
        livePress = action
        liveClearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.livePress = nil }
        liveClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
    }

    private func action(matchingUsage usage: UInt8, modifiers: Modifier) -> InputAction? {
        for control in layout.controls {
            for action in control.actions {
                if case .keys(let sequence, _) = profile[layer, action],
                   let first = sequence.first,
                   first.usage == usage, first.modifiers == modifiers {
                    return action
                }
            }
        }
        return nil
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
        persistCurrentScope()
        guard writeToDevice(profile, describing: currentScope.name) else { return }
        liveScopeKey = currentScopeKey
    }

    /// Sends every mapping in a profile, plus the entries that clear the slots
    /// it leaves empty — otherwise a key from the previous scope would linger.
    @discardableResult
    func writeToDevice(_ source: Profile, describing what: String) -> Bool {
        guard let webhub = composer as? WebHubComposer else {
            var reports: [PadReport] = []
            for entry in source.configured(layerCount: layout.layerCount) {
                reports.append(contentsOf: composer.reports(for: entry.binding,
                                                            action: entry.action,
                                                            layer: entry.layer))
            }
            guard !reports.isEmpty else {
                setStatus("Nothing to save yet — map a key first", error: true)
                return false
            }
            send(reports, describing: what)
            return true
        }

        var reports: [PadReport] = []
        var written = 0
        for control in layout.controls {
            for action in control.actions {
                let binding = source[layer, action]
                if binding.isSet {
                    reports.append(contentsOf: webhub.reports(for: binding, action: action, layer: layer))
                    written += 1
                } else {
                    reports.append(contentsOf: webhub.clear(action: action, layer: layer))
                }
            }
        }
        guard !reports.isEmpty else {
            setStatus("Nothing to save yet — map a key first", error: true)
            return false
        }
        send(reports, describing: "\(what) — \(written) key\(written == 1 ? "" : "s")")
        return true
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

    // MARK: - Backlight

    @Published var backlight = BacklightState()
    @Published private(set) var backlightIsLive = false

    func applyBacklight() {
        let steps = backlight.speedSteps
        backlight.speed = min(max(backlight.speed, steps.lowerBound), steps.upperBound)
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
            setStatus(launchAtLogin ? "Knurl will open at login" : "Knurl will not open at login")
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            setStatus("Could not change the login item: \(error.localizedDescription)", error: true)
        }
    }

    /// Which section the window is showing. Held here so the menu bar can send
    /// the user somewhere specific instead of just raising the window.
    @Published var section: PanelSection = .keys

    // MARK: - Appearance

    enum Appearance: String, CaseIterable {
        case system, light, dark
        var title: String { rawValue.capitalized }
    }

    @Published var appearance: Appearance =
        Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "dark") ?? .dark {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            applyAppearance()
        }
    }

    /// What a view should force, or nil to follow the system.
    var colorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: - Dock icon

    @Published var hideDockIcon: Bool = UserDefaults.standard.bool(forKey: "hideDockIcon") {
        didSet {
            UserDefaults.standard.set(hideDockIcon, forKey: "hideDockIcon")
            applyActivationPolicy()
        }
    }

    func applyActivationPolicy() {
        NSApp.setActivationPolicy(hideDockIcon ? .accessory : .regular)
    }

    // MARK: - Scopes: global, and one per app

    private let scopeStore = ScopeStore()

    @Published private(set) var scopes: [MappingScope] = []
    /// Which scope the editor is showing. The editor never moves on its own —
    /// the user picks what they are editing; only the keypad follows the front app.
    @Published private(set) var currentScopeKey = MappingScope.globalKey

    @Published var autoSwitchEnabled: Bool = UserDefaults.standard.object(forKey: "autoSwitchEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoSwitchEnabled, forKey: "autoSwitchEnabled")
            autoSwitchEnabled ? startWatchingApps() : stopWatchingApps()
        }
    }

    /// The scope the keypad is currently holding, which is not necessarily the
    /// one on screen.
    @Published private(set) var liveScopeKey = MappingScope.globalKey

    private var workspaceObserver: Any?

    var currentScope: MappingScope {
        scopes.first { $0.key == currentScopeKey } ?? .global
    }

    func scopeHasMappings(_ scope: MappingScope) -> Bool {
        scope.key == currentScopeKey
            ? !profile.configured(layerCount: layout.layerCount).isEmpty
            : scopeStore.hasMappings(scope.key, layerCount: layout.layerCount)
    }

    func selectScope(_ key: String) {
        guard key != currentScopeKey else { return }
        persistCurrentScope()
        currentScopeKey = key
        profile = scopeStore.profile(for: key)
        loadedFromDevice = false
        loadEditor()
    }

    /// Shows a scope in the editor and writes it to the keypad.
    func load(_ scope: MappingScope) {
        selectScope(scope.key)
        if isConnected { saveToKeyboard() }
    }

    func addAppScope(bundleId: String, name: String) {
        _ = scopeStore.addScope(key: bundleId, name: name)
        scopes = scopeStore.scopes
        selectScope(bundleId)
        setStatus("Added \(name) — the keys you set here apply only in that app")
    }

    func removeScope(_ scope: MappingScope) {
        guard !scope.isGlobal else { return }
        scopeStore.removeScope(key: scope.key)
        scopes = scopeStore.scopes
        if currentScopeKey == scope.key {
            currentScopeKey = MappingScope.globalKey
            profile = scopeStore.profile(for: MappingScope.globalKey)
            loadEditor()
        }
    }

    private func persistCurrentScope() {
        scopeStore.setProfile(profile, for: currentScopeKey)
    }

    // MARK: Following the front app

    func startWatchingApps() {
        guard workspaceObserver == nil else { return }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleId = app?.bundleIdentifier
            Task { @MainActor in self?.frontmostAppChanged(to: bundleId) }
        }
    }

    func stopWatchingApps() {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        workspaceObserver = nil
    }

    private func frontmostAppChanged(to bundleId: String?) {
        guard autoSwitchEnabled, isConnected else { return }
        persistCurrentScope()

        // An app with its own mappings wins; everything else falls back to Global.
        let target: String
        if let bundleId, scopes.contains(where: { $0.key == bundleId }),
           scopeStore.hasMappings(bundleId, layerCount: layout.layerCount) {
            target = bundleId
        } else {
            target = MappingScope.globalKey
        }

        // Every write is a write to the keypad's flash, so a scope that is
        // already on the device is left alone.
        guard target != liveScopeKey else { return }
        let wanted = target == currentScopeKey ? profile : scopeStore.profile(for: target)
        writeToDevice(wanted, describing: scopes.first { $0.key == target }?.name ?? "Global")
        liveScopeKey = target
    }

    // MARK: - Presets you saved

    private let presetStore = PresetStore()
    @Published private(set) var presets: [Preset] = []

    func refreshPresets() { presets = presetStore.all() }

    func savePreset(named name: String, summary: String) {
        commit()
        var p = profile
        p.layoutName = layout.name
        p.name = name
        do {
            try presetStore.save(Preset(name: name, summary: summary, profile: p))
            refreshPresets()
            setStatus("Saved “\(name)” as a preset")
        } catch {
            setStatus("Could not save the preset: \(error.localizedDescription)", error: true)
        }
    }

    func deletePreset(_ preset: Preset) {
        try? presetStore.delete(preset)
        refreshPresets()
    }

    /// Drops a saved preset onto the scope on screen, and writes it.
    func apply(_ preset: Preset) {
        isRecording = false
        var next = preset.profile
        next.layoutName = layout.name
        next.ledMode = profile.ledMode
        next.ledColor = profile.ledColor
        profile = next
        loadedFromDevice = false
        persistCurrentScope()
        loadEditor()
        if isConnected {
            saveToKeyboard()
        } else {
            setStatus("Loaded “\(preset.name)” — connect the keypad to write it")
        }
    }

    /// Whether the keys on screen are exactly this set.
    ///
    /// Worked out by comparing the mappings rather than remembering the last
    /// card that was clicked, so the marker cannot drift out of step with what
    /// the scope actually holds — editing one key drops the match immediately.
    func isActive(_ preset: Preset) -> Bool {
        !profile.bindings.isEmpty && preset.profile.bindings == profile.bindings
    }

    func isActive(_ template: MacroTemplate) -> Bool {
        guard !profile.bindings.isEmpty else { return false }
        var candidate = Profile()
        template.apply(to: &candidate, layout: layout, layer: layer)
        return candidate.bindings == profile.bindings
    }

    // MARK: - Templates

    /// Lays a template over the whole pad and, if a keypad is connected, writes
    /// it immediately — choosing a template should produce a working keypad,
    /// not homework.
    func apply(_ template: MacroTemplate) {
        isRecording = false
        var next = Profile(name: template.name, layoutName: layout.name)
        template.apply(to: &next, layout: layout, layer: layer)
        next.ledMode = profile.ledMode
        next.ledColor = profile.ledColor
        profile = next
        loadedFromDevice = false
        persistCurrentScope()
        loadEditor()

        if isConnected {
            saveToKeyboard()
        } else {
            setStatus("Loaded “\(template.name)” — connect the keypad to write it")
        }
    }

    // MARK: - Presets

    /// Writes the current profile to a file the user picks, so it can be moved
    /// between Macs or shared.
    func exportPreset() {
        commit()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(currentScope.name) keys.json"
        panel.title = "Export preset"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var p = profile
            p.layoutName = layout.name
            p.name = currentScope.name
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
            persistCurrentScope()
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
