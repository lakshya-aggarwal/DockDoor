import Cocoa
import SwiftUI

final class CustomDockModel: ObservableObject {
    @Published var config: CustomDockConfig
    @Published var running: Set<String>
    @Published var isShown = true
    @Published var hiddenOffset = CGSize.zero
    @Published var fadesWhenHidden = false
    weak var panel: CustomDockPanel?

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
                    isVertical: model.config.isVertical,
                    isShown: model.isShown
                )
            }
        }
        .padding(10)
        .dockStyle(backgroundAppearance: .resolve(), cornerRadius: 18, outerPadding: 0)
        .fixedSize()
        .offset(model.isShown ? .zero : model.hiddenOffset)
        // Like the system Dock, an edge dock slides out solid; a floating one also fades so it isn't cut off mid-screen.
        .opacity(model.isShown || !model.fadesWhenHidden ? 1 : 0)
        // Paced to finish alongside the system's Space slide, as the Dock does.
        .animation(.easeInOut(duration: 0.4), value: model.isShown)
        .contentShape(Rectangle())
        .hoverCursor(.openHand, active: model.isShown)
        .highPriorityGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in model.panel?.dragChanged() }
                .onEnded { _ in model.panel?.dragEnded() }
        )
    }
}

private struct CustomDockIcon: View {
    let bundleID: String
    let size: CGFloat
    let isRunning: Bool
    let isVertical: Bool
    let isShown: Bool

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
        .hoverCursor(.arrow, active: isShown)
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

private struct HoverCursorModifier: ViewModifier {
    let cursor: NSCursor
    let active: Bool
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside, active, !pushed {
                    cursor.push()
                    pushed = true
                } else if !inside { release() }
            }
            .onChange(of: active) { if !$0 { release() } }
            .onDisappear { release() }
    }

    // A hidden dock stops receiving mouse events, so the exit callback may never fire and the cursor is released here.
    private func release() {
        guard pushed else { return }
        NSCursor.pop()
        pushed = false
    }
}

private extension View {
    func hoverCursor(_ cursor: NSCursor, active: Bool) -> some View {
        modifier(HoverCursorModifier(cursor: cursor, active: active))
    }
}
