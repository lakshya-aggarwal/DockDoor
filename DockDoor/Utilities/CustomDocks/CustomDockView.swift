import Cocoa
import SwiftUI

final class CustomDockModel: ObservableObject {
    @Published var config: CustomDockConfig
    @Published var running: Set<String>

    init(config: CustomDockConfig, running: Set<String>) {
        self.config = config
        self.running = running
    }
}

struct CustomDockView: View {
    @ObservedObject var model: CustomDockModel

    var body: some View {
        let layout = model.config.isVertical
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        layout {
            ForEach(model.config.bundleIDs, id: \.self) { bundleID in
                CustomDockIcon(
                    bundleID: bundleID,
                    size: model.config.iconSize,
                    isRunning: model.running.contains(bundleID),
                    isVertical: model.config.isVertical
                )
            }
        }
        .padding(10)
        .dockStyle(backgroundAppearance: .resolve(), cornerRadius: 18, outerPadding: 0)
        .fixedSize()
    }
}

private struct CustomDockIcon: View {
    let bundleID: String
    let size: CGFloat
    let isRunning: Bool
    let isVertical: Bool

    private var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    var body: some View {
        Button(action: launch) {
            Group {
                if let appURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                        .resizable()
                } else {
                    Image(systemName: "questionmark.app.dashed")
                        .resizable()
                        .scaledToFit()
                        .opacity(0.4)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .disabled(appURL == nil)
        .help(appURL?.deletingPathExtension().lastPathComponent ?? bundleID)
        .overlay(alignment: isVertical ? .leading : .bottom) {
            if isRunning {
                Circle()
                    .fill(.secondary)
                    .frame(width: 4, height: 4)
                    .offset(x: isVertical ? -7 : 0, y: isVertical ? 0 : 7)
            }
        }
    }

    private func launch() {
        guard let appURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }
}
