import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
ApplicationMenu.install()
let controller = AppController()
app.delegate = controller
app.run()
