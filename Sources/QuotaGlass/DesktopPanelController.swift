@preconcurrency import AppKit
import Combine
import CoreGraphics
import SwiftUI

@MainActor
final class DesktopPanelController: NSObject, NSWindowDelegate, NSGestureRecognizerDelegate {
    private let panel: DesktopPanel
    private let viewModel: QuotaViewModel
    private var cancellables: Set<AnyCancellable> = []
    private var screenObserver: NSObjectProtocol?
    private var isRestoringPosition = false
    private var dragStart: (mouse: CGPoint, window: CGPoint)?

    init(viewModel: QuotaViewModel) {
        self.viewModel = viewModel
        panel = DesktopPanel(
            contentRect: CGRect(origin: .zero, size: Self.collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
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
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = DraggableHostingView(rootView: QuotaCardView(model: viewModel))

        let dragGesture = NSPanGestureRecognizer(target: self, action: #selector(handleDragGesture(_:)))
        dragGesture.buttonMask = 0x1
        dragGesture.delaysPrimaryMouseButtonEvents = false
        dragGesture.delegate = self
        panel.contentView?.addGestureRecognizer(dragGesture)
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
        let xRatio = UserDefaults.standard.object(forKey: "panelXRatio") as? Double ?? 0.93
        let yRatio = UserDefaults.standard.object(forKey: "panelYRatio") as? Double ?? 0.86
        let x = visible.minX + xRatio * max(0, visible.width - width)
        let y = visible.minY + yRatio * max(0, visible.height - height)

        isRestoringPosition = true
        panel.setFrameOrigin(CGPoint(x: x, y: y))
        isRestoringPosition = false
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
    }

    @objc private func handleDragGesture(_ gesture: NSPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            dragStart = (mouse: NSEvent.mouseLocation, window: panel.frame.origin)

        case .changed:
            guard let dragStart else { return }
            let mouse = NSEvent.mouseLocation
            panel.setFrameOrigin(
                CGPoint(
                    x: dragStart.window.x + mouse.x - dragStart.mouse.x,
                    y: dragStart.window.y + mouse.y - dragStart.mouse.y
                )
            )

        case .ended, .cancelled:
            guard dragStart != nil else { return }
            dragStart = nil
            keepVisible()
            persistPosition()

        default:
            break
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        true
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
}

private final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
