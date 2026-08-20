import AppKit
import SwiftUI

final class PetPanel: NSPanel {
    private static let petSize = NSSize(width: 140, height: 170)
    var onPetDragged: ((CGFloat, CGFloat) -> Void)?
    var onPetDragEnded: (() -> Void)?
    private var trackingPetDrag = false
    private var lastMouseLocation: NSPoint?

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        hasShadow = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        var shouldConstrainPet = false
        switch event.type {
        case .leftMouseDown:
            let point = event.locationInWindow
            trackingPetDrag = point.x >= frame.width - Self.petSize.width
                && point.y <= Self.petSize.height
            lastMouseLocation = trackingPetDrag ? NSEvent.mouseLocation : nil
        case .leftMouseDragged where trackingPetDrag:
            let location = NSEvent.mouseLocation
            if let previous = lastMouseLocation {
                onPetDragged?(location.x - previous.x, location.y - previous.y)
            }
            lastMouseLocation = location
            shouldConstrainPet = true
        case .leftMouseUp:
            if trackingPetDrag {
                onPetDragEnded?()
                shouldConstrainPet = true
            }
            trackingPetDrag = false
            lastMouseLocation = nil
        default:
            break
        }
        super.sendEvent(event)
        if shouldConstrainPet { constrainPetToVisibleScreen() }
    }

    func frameConstrainedToVisibleScreen(_ proposedFrame: NSRect) -> NSRect {
        guard let visibleFrame = targetScreen(for: proposedFrame)?.visibleFrame else {
            return proposedFrame
        }

        var result = proposedFrame
        let petWidth = min(Self.petSize.width, result.width, visibleFrame.width)
        let petHeight = min(Self.petSize.height, result.height, visibleFrame.height)
        let minimumX = visibleFrame.minX - result.width + petWidth
        let maximumX = visibleFrame.maxX - result.width
        result.origin.x = min(max(result.origin.x, minimumX), maximumX)
        result.origin.y = min(max(result.origin.y, visibleFrame.minY), visibleFrame.maxY - petHeight)
        return result
    }

    private func constrainPetToVisibleScreen() {
        let constrainedFrame = frameConstrainedToVisibleScreen(frame)
        if constrainedFrame.origin != frame.origin {
            setFrameOrigin(constrainedFrame.origin)
        }
    }

    private func targetScreen(for proposedFrame: NSRect) -> NSScreen? {
        let intersectingScreen = NSScreen.screens
            .map { ($0, $0.visibleFrame.intersection(proposedFrame)) }
            .filter { !$0.1.isNull }
            .max { $0.1.width * $0.1.height < $1.1.width * $1.1.height }?
            .0
        if let intersectingScreen { return intersectingScreen }

        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.visibleFrame.contains(mouseLocation) }
            ?? screen
            ?? NSScreen.main
    }
}

final class AppController: NSObject, NSApplicationDelegate {
    private static let collapsedSize = NSSize(width: 140, height: 170)
    private static let expandedSize = NSSize(width: 430, height: 260)
    private let monitor = SessionMonitor()
    private let motion = PetMotion()
    private var panel: PetPanel!
    private var collapseWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = Self.collapsedSize
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: visible.maxX - size.width - 18, y: visible.minY + 18)
        panel = PetPanel(frame: NSRect(origin: origin, size: size))
        panel.onPetDragged = { [weak self] deltaX, deltaY in
            self?.motion.updateDrag(deltaX: deltaX, deltaY: deltaY)
        }
        panel.onPetDragEnded = { [weak self] in self?.motion.endDrag() }
        let host = NSHostingView(rootView: PetView(
            monitor: monitor,
            motion: motion,
            quit: { NSApplication.shared.terminate(nil) },
            setExpanded: { [weak self] expanded in self?.setExpanded(expanded) }
        ))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.orderFrontRegardless()
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) { monitor.stop() }

    private func setExpanded(_ expanded: Bool) {
        collapseWorkItem?.cancel()
        if expanded {
            apply(size: Self.expandedSize)
            return
        }
        let item = DispatchWorkItem { [weak self] in self?.apply(size: Self.collapsedSize) }
        collapseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
    }

    private func apply(size: NSSize) {
        var frame = panel.frame
        let right = frame.maxX
        let bottom = frame.minY
        frame.size = size
        frame.origin = NSPoint(x: right - size.width, y: bottom)
        frame = panel.frameConstrainedToVisibleScreen(frame)
        panel.setFrame(frame, display: true, animate: true)
    }
}
