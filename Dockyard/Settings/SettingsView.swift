import DockCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        TabView {
            general
                .tabItem { tab("settings.tab.general", symbol: "gearshape") }
            displays
                .tabItem { tab("settings.tab.displays", symbol: "display.2") }
            about
                .tabItem { tab("settings.tab.about", symbol: "info.circle") }
        }
        .frame(width: 480, height: 380)
    }

    private var general: some View {
        Form {
            Section {
                Toggle(isOn: $preferences.launchesAtLogin) { text("settings.launchAtLogin") }
                Toggle(isOn: $preferences.suppressOnSystemDockDisplay) { text("settings.suppressOnDockDisplay") }
            } footer: {
                footnote("settings.mirrorFooter")
            }

            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        text("settings.accessibility.title")
                        text(appMenuStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !preferences.appMenusAuthorized {
                        Button {
                            preferences.requestAppMenuAuthorization()
                        } label: {
                            text("settings.accessibility.grant")
                        }
                    }
                }
            } footer: {
                footnote("settings.accessibility.footer")
            }

            Section {
                Toggle(isOn: $preferences.reservesScreenSpace) { text("settings.reserveSpace") }
                    .disabled(!preferences.appMenusAuthorized)
            } footer: {
                footnote("settings.reserveSpace.footer")
            }
        }
        .formStyle(.grouped)
    }

    private var appMenuStatus: LocalizedStringKey {
        preferences.appMenusAuthorized
            ? "settings.accessibility.on"
            : "settings.accessibility.off"
    }

    private var displays: some View {
        Form {
            Section {
                if preferences.knownDisplays.isEmpty {
                    text("settings.displays.none")
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
                text("settings.displays.header")
            } footer: {
                footnote("settings.displays.footer")
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.bottomthird.inset.filled")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            text("app.name")
                .font(.title2.weight(.semibold))
            Text(versionString)
                .font(.callout)
                .foregroundStyle(.secondary)
            text("settings.about.tagline")
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
        return String(format: DockyardText.string("settings.about.version"), version, build)
    }

    private func tab(_ key: LocalizedStringKey, symbol: String) -> some View {
        Label {
            text(key)
        } icon: {
            Image(systemName: symbol)
        }
    }

    private func text(_ key: LocalizedStringKey) -> Text {
        DockyardText.text(key)
    }

    private func footnote(_ key: LocalizedStringKey) -> some View {
        DockyardText.text(key)
            .font(.footnote)
            .foregroundStyle(.secondary)
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
