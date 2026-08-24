@preconcurrency import AppKit
import Combine
import CoreGraphics
import SwiftUI

@MainActor
final class DesktopPanelController: NSObject, NSWindowDelegate {
    private let panel: DesktopPanel
    private let viewModel: QuotaViewModel
    private var cancellables: Set<AnyCancellable> = []
    private var screenObserver: NSObjectProtocol?
    private var isRestoringPosition = true

    init(viewModel: QuotaViewModel) {
        self.viewModel = viewModel
        panel = DesktopPanel(
            contentRect: CGRect(origin: .zero, size: Self.collapsedSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()

        configurePanel()
        observeViewModel()
        restorePosition()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restorePosition() }
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isRestoringPosition else { return }
        persistPosition()
    }

    private func configurePanel() {
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        // Use an ordinary interactive Window Server layer immediately below
        // normal app windows. Finder's special desktop layers can be visible
        // while still routing physical pointer input to the desktop itself.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        let hostingView = DraggableHostingView(rootView: QuotaCardView(model: viewModel))
        hostingView.onDragEnded = { [weak self] in
            self?.keepVisible()
            self?.persistPosition()
        }
        panel.contentView = hostingView

    }

    private func observeViewModel() {
        viewModel.$isExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                self?.resize(expanded: expanded)
            }
            .store(in: &cancellables)
    }

    private func resize(expanded: Bool) {
        let target = expanded ? Self.expandedSize : Self.collapsedSize
        var frame = panel.frame
        frame.origin.y += frame.height - target.height
        frame.size = target
        panel.setFrame(frame, display: true, animate: true)
        keepVisible()
    }

    private func restorePosition() {
        guard let screen = preferredScreen() ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let width = panel.frame.width
        let height = panel.frame.height
        let defaults = UserDefaults.standard
        let needsPositionMigration = defaults.integer(forKey: "panelPositionVersion") < Self.positionStorageVersion
        let xRatio = needsPositionMigration
            ? 0.93
            : defaults.object(forKey: "panelXRatio") as? Double ?? 0.93
        let yRatio = needsPositionMigration
            ? 0.86
            : defaults.object(forKey: "panelYRatio") as? Double ?? 0.86
        let x = visible.minX + xRatio * max(0, visible.width - width)
        let y = visible.minY + yRatio * max(0, visible.height - height)

        isRestoringPosition = true
        panel.setFrameOrigin(CGPoint(x: x, y: y))
        isRestoringPosition = false

        if needsPositionMigration {
            defaults.set(Self.positionStorageVersion, forKey: "panelPositionVersion")
            persistPosition()
        }
    }

    private func preferredScreen() -> NSScreen? {
        let storedName = UserDefaults.standard.string(forKey: "panelScreenName")
        return NSScreen.screens.first { $0.localizedName == storedName }
    }

    private func persistPosition() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let xRange = max(1, visible.width - panel.frame.width)
        let yRange = max(1, visible.height - panel.frame.height)
        let xRatio = min(max((panel.frame.minX - visible.minX) / xRange, 0), 1)
        let yRatio = min(max((panel.frame.minY - visible.minY) / yRange, 0), 1)

        UserDefaults.standard.set(screen.localizedName, forKey: "panelScreenName")
        UserDefaults.standard.set(xRatio, forKey: "panelXRatio")
        UserDefaults.standard.set(yRatio, forKey: "panelYRatio")
        UserDefaults.standard.set(Self.positionStorageVersion, forKey: "panelPositionVersion")
    }

    private func keepVisible() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        var frame = panel.frame
        let visible = screen.visibleFrame
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        panel.setFrame(frame, display: true)
    }

    private static let collapsedSize = CGSize(width: 254, height: 342)
    private static let expandedSize = CGSize(width: 254, height: 540)
    private static let positionStorageVersion = 2
}

private final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    var onDragEnded: (() -> Void)?
    private var dragStart: (mouse: CGPoint, window: CGPoint)?

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            return self
        default:
            return super.hitTest(point)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragStart = (
            mouse: window.convertPoint(toScreen: event.locationInWindow),
            window: window.frame.origin
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragStart else { return }
        let mouse = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(
            CGPoint(
                x: dragStart.window.x + mouse.x - dragStart.mouse.x,
                y: dragStart.window.y + mouse.y - dragStart.mouse.y
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragStart = nil
        onDragEnded?()
    }
}
