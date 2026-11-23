import Cocoa
import Defaults
import SwiftUI

final class CustomDockPanel: NSPanel {
    let model: CustomDockModel
    private let hostingView: NSHostingView<CustomDockView>

    init(model: CustomDockModel) {
        self.model = model
        hostingView = NSHostingView(rootView: CustomDockView(model: model))
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        contentView = hostingView
    }

    func fitContent() {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        setFrame(NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height), display: true)
    }

    func place(on screen: NSScreen) {
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let config = model.config
        let center = CGPoint(
            x: screen.frame.minX + config.relativeX * screen.frame.width,
            y: screen.frame.minY + config.relativeY * screen.frame.height
        )
        let bounds = screen.visibleFrame
        let origin = CGPoint(
            x: min(max(center.x - size.width / 2, bounds.minX), max(bounds.minX, bounds.maxX - size.width)),
            y: min(max(center.y - size.height / 2, bounds.minY), max(bounds.minY, bounds.maxY - size.height))
        )
        setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

final class CustomDockCoordinator {
    private var panels: [UUID: CustomDockPanel] = [:]
    private var running: Set<String>
    private var observers: [NSObjectProtocol] = []
    private var saveWorkItems: [UUID: DispatchWorkItem] = [:]

    init() {
        running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let id = Self.bundleID(from: note) else { return }
            self?.updateRunning { $0.insert(id) }
        })
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let id = Self.bundleID(from: note) else { return }
            self?.updateRunning { $0.remove(id) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.panels.values.forEach { panel in
                if let screen = Self.screen(for: panel.model.config) { panel.place(on: screen) }
            }
        })
    }

    deinit {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        panels.values.forEach { $0.orderOut(nil) }
    }

    func apply(_ docks: [CustomDockConfig]) {
        let ids = Set(docks.map(\.id))
        for (id, panel) in panels where !ids.contains(id) {
            panel.orderOut(nil)
            panels[id] = nil
        }
        for config in docks {
            if let panel = panels[config.id] {
                guard panel.model.config != config else { continue }
                panel.model.config = config
                DispatchQueue.main.async { panel.fitContent() }
            } else {
                let panel = CustomDockPanel(model: CustomDockModel(config: config, running: running))
                panels[config.id] = panel
                if let screen = Self.screen(for: config) { panel.place(on: screen) }
                panel.orderFrontRegardless()
                observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self, weak panel] _ in
                    guard let panel, NSEvent.pressedMouseButtons & 1 != 0 else { return }
                    self?.schedulePositionSave(for: panel)
                })
            }
        }
    }

    private static func screen(for config: CustomDockConfig) -> NSScreen? {
        NSScreen.findScreen(byIdentifier: config.screenID ?? "") ?? NSScreen.systemMain
    }

    private static func bundleID(from note: Notification) -> String? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
    }

    private func updateRunning(_ change: (inout Set<String>) -> Void) {
        change(&running)
        panels.values.forEach { $0.model.running = running }
    }

    private func schedulePositionSave(for panel: CustomDockPanel) {
        let id = panel.model.config.id
        saveWorkItems[id]?.cancel()
        let item = DispatchWorkItem { [weak panel] in
            guard let panel else { return }
            let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) else { return }
            let screenID = screen.uniqueIdentifier()
            let relativeX = (center.x - screen.frame.minX) / screen.frame.width
            let relativeY = (center.y - screen.frame.minY) / screen.frame.height
            guard let index = Defaults[.customDocks].firstIndex(where: { $0.id == id }) else { return }
            Defaults[.customDocks][index].screenID = screenID
            Defaults[.customDocks][index].relativeX = relativeX
            Defaults[.customDocks][index].relativeY = relativeY
        }
        saveWorkItems[id] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }
}
