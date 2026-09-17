import AppKit

// Top-level code is nonisolated under Swift 6 strict concurrency; the app
// object and its delegate are both main-actor bound.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
    let delegate = AppDelegate()
    app.delegate = delegate
    // Held for the process lifetime; NSApplication.delegate is unowned.
    objc_setAssociatedObject(app, "MeetingHopDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.run()
}
