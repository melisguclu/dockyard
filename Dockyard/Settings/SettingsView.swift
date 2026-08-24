import DockCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            displays
                .tabItem { Label("Displays", systemImage: "display.2") }
            about
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 320)
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Launch Dockyard at login", isOn: $preferences.launchesAtLogin)
                Toggle(
                    "Hide Dockyard on the display showing the real Dock",
                    isOn: $preferences.suppressOnSystemDockDisplay
                )
            } footer: {
                Text("Dockyard mirrors the system Dock and never modifies it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App commands and minimized windows")
                        Text(appMenuStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !preferences.appMenusAuthorized {
                        Button("Grant Access…") {
                            preferences.requestAppMenuAuthorization()
                        }
                    }
                }
            } footer: {
                Text(
                    """
                    Accessibility access lets a tile's menu list the app's own \
                    windows and commands, such as New Window or Next Track, and \
                    gives every minimized window a tile before the Trash.
                    """
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var appMenuStatus: String {
        preferences.appMenusAuthorized
            ? "Enabled. Minimized windows have tiles, and a right-click lists an app's own commands."
            : "Off. No minimized windows, and tile menus show only Dockyard's own commands."
    }

    private var displays: some View {
        Form {
            Section {
                if preferences.knownDisplays.isEmpty {
                    Text("No displays detected yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(preferences.knownDisplays) { display in
                        Toggle(isOn: binding(for: display)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(display.name)
                                Text(subtitle(for: display))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Show a dock on")
            } footer: {
                Text("Per-display choices are remembered across disconnects.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.bottomthird.inset.filled")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("Dockyard")
                .font(.title2.weight(.semibold))
            Text(versionString)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("A dock on every display. No network, no polling, no required permissions.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            Spacer()
        }
        .padding(.top, 30)
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "Version \(version) (\(build))"
    }

    private func subtitle(for display: DisplayDescriptor) -> String {
        var parts: [String] = [display.isBuiltIn ? "Built-in" : "External"]
        if display.hostsSystemDock {
            parts.append("currently hosts the system Dock")
        }
        if !display.identity.hasStableHardwareIdentity {
            parts.append("no unique hardware identifier")
        }
        return parts.joined(separator: " · ")
    }

    private func binding(for display: DisplayDescriptor) -> Binding<Bool> {
        Binding(
            get: { preferences.isEnabled(display.identity) },
            set: { preferences.setEnabled($0, for: display.identity) }
        )
    }
}
