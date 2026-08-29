import DockCore
import SwiftUI

enum SettingsPane: CaseIterable {
    case general
    case displays
    case about

    var title: String {
        switch self {
        case .general:
            return DockyardText.string("settings.tab.general")
        case .displays:
            return DockyardText.string("settings.tab.displays")
        case .about:
            return DockyardText.string("settings.tab.about")
        }
    }

    var symbol: String {
        switch self {
        case .general:
            return "gearshape"
        case .displays:
            return "display.2"
        case .about:
            return "info.circle"
        }
    }
}

enum SettingsMetrics {
    static let paneWidth: CGFloat = 500
}

struct GeneralSettingsView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $preferences.launchesAtLogin) { text("settings.launchAtLogin") }
                Toggle(isOn: $preferences.suppressOnSystemDockDisplay) {
                    text("settings.suppressOnDockDisplay")
                    text("settings.mirrorFooter")
                }
            }

            Section {
                LabeledContent {
                    if !preferences.appMenusAuthorized {
                        Button {
                            preferences.requestAppMenuAuthorization()
                        } label: {
                            text("settings.accessibility.grant")
                        }
                    }
                } label: {
                    text("settings.accessibility.title")
                    text(authorizationStatus)
                }
            } footer: {
                text("settings.accessibility.footer")
            }

            Section {
                Toggle(isOn: $preferences.reservesScreenSpace) {
                    text("settings.reserveSpace")
                    text("settings.reserveSpace.footer")
                }
                .disabled(!preferences.appMenusAuthorized)

                Toggle(isOn: $preferences.reordersLocally) {
                    text("settings.localReordering")
                    text("settings.localReordering.footer")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsMetrics.paneWidth)
    }

    private var authorizationStatus: LocalizedStringKey {
        preferences.appMenusAuthorized
            ? "settings.accessibility.on"
            : "settings.accessibility.off"
    }
}

struct DisplaysSettingsView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section {
                if preferences.knownDisplays.isEmpty {
                    text("settings.displays.none")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(preferences.knownDisplays) { display in
                        Toggle(isOn: binding(for: display)) {
                            Text(display.name)
                            Text(subtitle(for: display))
                        }
                    }
                }
            } header: {
                text("settings.displays.header")
            } footer: {
                text("settings.displays.footer")
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsMetrics.paneWidth)
    }

    private func subtitle(for display: DisplayDescriptor) -> String {
        var parts: [String] = [
            DockyardText.string(display.isBuiltIn ? "display.builtIn" : "display.external")
        ]
        if display.hostsSystemDock {
            parts.append(DockyardText.string("display.hostsSystemDock"))
        }
        if !display.identity.hasStableHardwareIdentity {
            parts.append(DockyardText.string("display.noHardwareIdentity"))
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

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                text("app.name")
                    .font(.title2.weight(.semibold))
                Text(version)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            text("settings.about.tagline")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 40)
        .frame(width: SettingsMetrics.paneWidth)
    }

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return String(format: DockyardText.string("settings.about.version"), short, build)
    }
}

private func text(_ key: LocalizedStringKey) -> Text {
    DockyardText.text(key)
}
