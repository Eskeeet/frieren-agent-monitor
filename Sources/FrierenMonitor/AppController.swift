import AppKit
import SwiftUI

final class PetPanel: NSPanel {
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
}

final class AppController: NSObject, NSApplicationDelegate {
    private static let collapsedSize = NSSize(width: 140, height: 170)
    private static let expandedSize = NSSize(width: 430, height: 260)
    private let monitor = SessionMonitor()
    private var panel: PetPanel!
    private var collapseWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = Self.collapsedSize
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: visible.maxX - size.width - 18, y: visible.minY + 18)
        panel = PetPanel(frame: NSRect(origin: origin, size: size))
        let host = NSHostingView(rootView: PetView(
            monitor: monitor,
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
