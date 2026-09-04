import Foundation

/// Carries a user's work across the rename from MacroPad to Knurl.
///
/// Renaming the app changes both where its files live and which preferences
/// domain it reads, so without this a user who had already set the keypad up
/// would open the new build to an empty one.
public enum Migration {

    /// Keys worth carrying over. Anything not listed is either derivable or not
    /// worth keeping.
    private static let defaultsKeys = [
        "deviceNicknames", "hideDockIcon", "autoSwitchEnabled",
        "appearance", "hasSeenTemplates",
    ]

    private static let oldBundleId = "local.macropad.mac"
    private static let doneKey = "migratedFromMacroPad"

    public static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)

        moveSupportDirectory()
        copyPreferences()
    }

    private static func moveSupportDirectory() {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let old = base.appendingPathComponent("MacroPad", isDirectory: true)
        let new = base.appendingPathComponent("Knurl", isDirectory: true)
        guard fm.fileExists(atPath: old.path) else { return }

        if fm.fileExists(atPath: new.path) {
            // Both exist: copy anything the new one is missing rather than
            // clobbering work already done under the new name.
            let items = (try? fm.contentsOfDirectory(at: old, includingPropertiesForKeys: nil)) ?? []
            for item in items {
                let target = new.appendingPathComponent(item.lastPathComponent)
                if !fm.fileExists(atPath: target.path) {
                    try? fm.copyItem(at: item, to: target)
                }
            }
        } else {
            try? fm.copyItem(at: old, to: new)
        }
    }

    private static func copyPreferences() {
        guard let old = UserDefaults(suiteName: oldBundleId) else { return }
        let defaults = UserDefaults.standard
        for key in defaultsKeys where defaults.object(forKey: key) == nil {
            if let value = old.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
    }
}
