import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct CustomDocksSettingsView: View {
    @Default(.customDocks) var customDocks

    var body: some View {
        SettingsFormView {
            SettingsSection("Custom Docks", footer: "Small floating docks that sit alongside the system Dock. Drag a dock to move it.") {
                Button {
                    customDocks.append(CustomDockConfig(name: String(localized: "Dock \(customDocks.count + 1)")))
                } label: {
                    Label("Add Dock", systemImage: "plus")
                }
                .settingsSearchTarget("customDocks.add")
            }

            ForEach($customDocks) { $dock in
                CustomDockEditor(dock: $dock, isFirst: dock.id == customDocks.first?.id) {
                    customDocks.removeAll { $0.id == dock.id }
                }
            }
        }
    }
}

private struct CustomDockEditor: View {
    @Binding var dock: CustomDockConfig
    let isFirst: Bool
    let onDelete: () -> Void

    var body: some View {
        SettingsSection(LocalizedStringKey(dock.name)) {
            searchable("customDocks.name", TextField("Name", text: $dock.name))

            searchable("customDocks.layout", Picker("Layout", selection: $dock.isVertical) {
                Text("Horizontal").tag(false)
                Text("Vertical").tag(true)
            })

            searchable("customDocks.iconSize", LabeledContent("Icon Size") {
                HStack {
                    Slider(value: $dock.iconSize, in: 24 ... 96, step: 2)
                    Text(verbatim: "\(Int(dock.iconSize)) px").monospacedDigit().foregroundStyle(.secondary)
                }
            })

            ForEach(dock.bundleIDs, id: \.self) { bundleID in
                HStack {
                    Text(Self.displayName(for: bundleID))
                    Spacer()
                    Button {
                        dock.bundleIDs.removeAll { $0 == bundleID }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
            .onMove { dock.bundleIDs.move(fromOffsets: $0, toOffset: $1) }

            searchable("customDocks.apps", Button(action: addApps) {
                Label("Add App…", systemImage: "plus")
            })

            Button("Delete Dock", role: .destructive, action: onDelete)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { add(url) }
                }
            }
            return true
        }
    }

    @ViewBuilder
    private func searchable(_ id: String, _ view: some View) -> some View {
        if isFirst { view.settingsSearchTarget(id) } else { view }
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(add)
    }

    private func add(_ url: URL) {
        guard url.pathExtension == "app",
              let bundleID = Bundle(url: url)?.bundleIdentifier,
              !dock.bundleIDs.contains(bundleID) else { return }
        dock.bundleIDs.append(bundleID)
    }

    private static func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }
}
