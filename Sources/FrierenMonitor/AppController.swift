import AppKit
import SwiftUI

final class PetPanel: NSPanel {
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
        switch event.type {
        case .leftMouseDown:
            let point = event.locationInWindow
            trackingPetDrag = point.x >= frame.width - 140 && point.y <= 170
            lastMouseLocation = trackingPetDrag ? NSEvent.mouseLocation : nil
        case .leftMouseDragged where trackingPetDrag:
            let location = NSEvent.mouseLocation
            if let previous = lastMouseLocation {
                onPetDragged?(location.x - previous.x, location.y - previous.y)
            }
            lastMouseLocation = location
        case .leftMouseUp:
            if trackingPetDrag { onPetDragEnded?() }
            trackingPetDrag = false
            lastMouseLocation = nil
        default:
            break
        }
        super.sendEvent(event)
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
        panel.setFrame(frame, display: true, animate: true)
    }
}
