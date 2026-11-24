import Cocoa
import Defaults
import SwiftUI

final class CustomDockPanel: NSPanel {
    let model: CustomDockModel
    private let hostingView: NSHostingView<CustomDockView>
    var isRevealed = true
    var isOnFullScreen = false
    var onDragEnd: (() -> Void)?
    private var dragStart: (mouse: CGPoint, origin: CGPoint)?

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
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        contentView = hostingView
        model.panel = self
    }

    // Background dragging is unusable when icons fill the panel, so the view's drag gesture moves the window instead.
    func dragChanged() {
        let mouse = NSEvent.mouseLocation
        let start = dragStart ?? (mouse, frame.origin)
        dragStart = start
        NSCursor.closedHand.set()
        setFrameOrigin(CGPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
    }

    func dragEnded() {
        dragStart = nil
        onDragEnd?()
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
        setFrame(CustomDockCoordinator.snapped(NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height), in: screen.visibleFrame, force: false), display: true)
    }

    // The content slides inside the panel rather than moving the window, so it never spills onto a neighbouring display.
    func setShown(_ shown: Bool, towards edge: Edge, flush: Bool) {
        if model.fadesWhenHidden == flush { model.fadesWhenHidden = !flush }
        let offset = switch edge {
        case .leading: CGSize(width: -frame.width, height: 0)
        case .trailing: CGSize(width: frame.width, height: 0)
        case .top: CGSize(width: 0, height: -frame.height)
        case .bottom: CGSize(width: 0, height: frame.height)
        }
        if model.hiddenOffset != offset { model.hiddenOffset = offset }
        guard shown != model.isShown else { return }
        model.isShown = shown
        ignoresMouseEvents = !shown
    }
}

final class CustomDockCoordinator {
    private static let snapThreshold: CGFloat = 24
    private static let edgeInset: CGFloat = 6
    private static let revealThickness: CGFloat = 4

    private var panels: [UUID: CustomDockPanel] = [:]
    private var running: Set<String>
    private var observers: [NSObjectProtocol] = []
    private var hideWorkItems: [UUID: DispatchWorkItem] = [:]
    private var mouseMonitor: Any?

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
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleFullScreenCheck()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.panels.values.forEach { panel in
                if let screen = Self.screen(for: panel.model.config) { panel.place(on: screen) }
            }
            self?.scheduleFullScreenCheck()
        })
    }

    deinit {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
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
                let autoHideChanged = panel.model.config.autoHide != config.autoHide
                panel.model.config = config
                if autoHideChanged { panel.isRevealed = !autoHides(panel) }
                DispatchQueue.main.async { [weak self, weak panel] in
                    guard let self, let panel else { return }
                    panel.fitContent()
                    if autoHideChanged, config.autoHide { snapAndSave(panel, force: true) }
                    refreshVisibility()
                }
            } else {
                let panel = CustomDockPanel(model: CustomDockModel(config: config, running: running))
                panel.isRevealed = !config.autoHide
                panels[config.id] = panel
                if let screen = Self.screen(for: config) { panel.place(on: screen) }
                panel.orderFrontRegardless()
                panel.onDragEnd = { [weak self, weak panel] in
                    guard let self, let panel else { return }
                    snapAndSave(panel, force: panel.model.config.autoHide)
                }
            }
        }
        updateFullScreenState()
    }

    static func snapped(_ frame: NSRect, in visible: NSRect, force: Bool) -> NSRect {
        let bounds = visible.insetBy(dx: edgeInset, dy: edgeInset)
        var result = frame
        result.origin.x = min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - frame.width))
        result.origin.y = min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - frame.height))

        let left = result.minX - bounds.minX
        let right = bounds.maxX - result.maxX
        let bottom = result.minY - bounds.minY
        let top = bounds.maxY - result.maxY

        if force {
            switch min(left, right, bottom, top) {
            case left: result.origin.x = bounds.minX
            case right: result.origin.x = bounds.maxX - result.width
            case bottom: result.origin.y = bounds.minY
            default: result.origin.y = bounds.maxY - result.height
            }
            return result
        }
        if left <= snapThreshold { result.origin.x = bounds.minX } else if right <= snapThreshold { result.origin.x = bounds.maxX - result.width }
        if bottom <= snapThreshold { result.origin.y = bounds.minY } else if top <= snapThreshold { result.origin.y = bounds.maxY - result.height }
        return result
    }

    private static func nearestEdge(of frame: NSRect, in visible: NSRect) -> (edge: Edge, distance: CGFloat) {
        let distances: [(edge: Edge, distance: CGFloat)] = [
            (.leading, frame.minX - visible.minX), (.trailing, visible.maxX - frame.maxX),
            (.bottom, frame.minY - visible.minY), (.top, visible.maxY - frame.maxY),
        ]
        return distances.min { $0.distance < $1.distance }!
    }

    private static func revealZone(for frame: NSRect, on screen: NSScreen) -> NSRect {
        let full = screen.frame
        let visible = screen.visibleFrame
        switch nearestEdge(of: frame, in: visible).edge {
        case .leading:
            return NSRect(x: full.minX, y: frame.minY, width: visible.minX - full.minX + revealThickness, height: frame.height)
        case .trailing:
            return NSRect(x: visible.maxX - revealThickness, y: frame.minY, width: full.maxX - visible.maxX + revealThickness, height: frame.height)
        case .bottom:
            return NSRect(x: frame.minX, y: full.minY, width: frame.width, height: visible.minY - full.minY + revealThickness)
        case .top:
            return NSRect(x: frame.minX, y: visible.maxY - revealThickness, width: frame.width, height: full.maxY - visible.maxY + revealThickness)
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

    // Space data can trail the notification while the switch animates, so it is read once more after it settles.
    private func scheduleFullScreenCheck() {
        updateFullScreenState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.updateFullScreenState() }
    }

    private func updateFullScreenState() {
        for panel in panels.values {
            let onFullScreen = Self.screen(for: panel.model.config).map(WindowSpaces.isFullScreenSpaceActive) ?? false
            guard onFullScreen != panel.isOnFullScreen else { continue }
            panel.isOnFullScreen = onFullScreen
            panel.isRevealed = !autoHides(panel)
        }
        refreshVisibility()
    }

    // Every dock auto-hides over a full-screen app; the per-dock setting only covers the regular desktop.
    private func autoHides(_ panel: CustomDockPanel) -> Bool {
        panel.model.config.autoHide || panel.isOnFullScreen
    }

    private func refreshVisibility() {
        for panel in panels.values {
            if !panel.isVisible { panel.orderFrontRegardless() }
            let visible = Self.screen(for: panel.model.config)?.visibleFrame ?? panel.frame
            let nearest = Self.nearestEdge(of: panel.frame, in: visible)
            panel.setShown(!autoHides(panel) || panel.isRevealed, towards: nearest.edge, flush: nearest.distance <= Self.edgeInset + 1)
        }
        updateMouseMonitor()
    }

    private func updateMouseMonitor() {
        let needed = panels.values.contains { autoHides($0) }
        if needed, mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                self?.handleMouseMoved()
            }
        } else if !needed, let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    private func handleMouseMoved() {
        let point = NSEvent.mouseLocation
        for panel in panels.values where autoHides(panel) {
            guard let screen = Self.screen(for: panel.model.config) else { continue }
            if panel.isRevealed {
                if !panel.frame.insetBy(dx: -8, dy: -8).contains(point) { scheduleHide(panel) }
            } else if Self.revealZone(for: panel.frame, on: screen).contains(point) {
                panel.isRevealed = true
                refreshVisibility()
            }
        }
    }

    private func scheduleHide(_ panel: CustomDockPanel) {
        let id = panel.model.config.id
        guard hideWorkItems[id] == nil else { return }
        let item = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel else { return }
            hideWorkItems[id] = nil
            guard panel.isRevealed, NSEvent.pressedMouseButtons & 1 == 0,
                  !panel.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) else { return }
            panel.isRevealed = false
            refreshVisibility()
        }
        hideWorkItems[id] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func snapAndSave(_ panel: CustomDockPanel, force: Bool) {
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? Self.screen(for: panel.model.config) else { return }
        let target = Self.snapped(panel.frame, in: screen.visibleFrame, force: force)
        if target != panel.frame { panel.setFrame(target, display: true, animate: true) }

        let id = panel.model.config.id
        var docks = Defaults[.customDocks]
        guard let index = docks.firstIndex(where: { $0.id == id }) else { return }
        docks[index].screenID = screen.uniqueIdentifier()
        docks[index].relativeX = (target.midX - screen.frame.minX) / screen.frame.width
        docks[index].relativeY = (target.midY - screen.frame.minY) / screen.frame.height
        Defaults[.customDocks] = docks
    }
}
