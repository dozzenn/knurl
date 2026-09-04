import AppKit
import SwiftUI
import MacroPadCore

/// Ties an app to a profile, so the keypad follows what is on screen.
struct AppRulesSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.profiles.isEmpty {
                        EmptyStateView(icon: "square.stack.3d.up.slash",
                                       title: "Save a profile first",
                                       message: "A rule points an app at a saved profile, so there needs to be at least one.")
                    } else if model.appRules.isEmpty {
                        EmptyStateView(icon: "app.badge",
                                       title: "No rules yet",
                                       message: "Add an app and choose which profile the keypad should load for it.")
                    }

                    ForEach(model.appRules) { rule in
                        RuleRow(rule: rule)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }

            Hairline()
            footer
        }
        .frame(width: 520, height: 440)
        .background(PopoverBackground())
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Switch by app")
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Theme.text)
                    Text("Load a profile onto the keypad when an app comes to the front.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Theme.fill))
                }
                .buttonStyle(PressableStyle())
            }

            Toggle(isOn: $model.autoSwitchEnabled) {
                Text("Follow the front app")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.text)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(14)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            BarAction(title: "Add app…", prominent: true) { pickApp() }
            Text("Each switch writes to the keypad's flash, so a profile that is already loaded is skipped.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.title = "Choose an app"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        let name = (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        guard let first = model.profiles.first else { return }
        model.addRule(bundleId: id, appName: name, profileName: first.name)
    }
}

private struct RuleRow: View {
    @EnvironmentObject private var model: AppModel
    let rule: AppModel.AppRule

    var body: some View {
        HStack(spacing: 10) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "app.dashed")
                    .foregroundStyle(Theme.textFaint)
                    .frame(width: 22)
            }

            Text(rule.appName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textFaint)

            Picker("", selection: Binding(
                get: { rule.profileName },
                set: { model.addRule(bundleId: rule.bundleId, appName: rule.appName, profileName: $0) }
            )) {
                ForEach(model.profiles) { entry in
                    Text(entry.name).tag(entry.name)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 150)

            Button { model.removeRule(rule) } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textFaint)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 9)
        .frame(height: 40)
    }

    private var appIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleId) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
