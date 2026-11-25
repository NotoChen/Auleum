import AppKit
import AuleumKit

#if DEBUG
let previewModeEnabled = ProcessInfo.processInfo.environment["AULEUM_UI_PREVIEW"] != nil
let previewDelegate = previewModeEnabled ? UIPreviewAppDelegate() : nil
if previewModeEnabled, let previewDelegate {
    let app = NSApplication.shared
    app.delegate = previewDelegate
    app.setActivationPolicy(.regular)
    app.run()
    exit(0)
}
#endif

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
