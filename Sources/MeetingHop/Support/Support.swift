import AppKit
import Combine
import ServiceManagement
import os
import MeetingHopKit

let log = Logger(subsystem: AppIdentity.bundleIdentifier, category: "app")

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("launch at login \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - View-local state

/// Stands in for SwiftUI's `@State`.
///
/// In the macOS 26 SDK `State` is a macro rather than a plain property
/// wrapper, and macro plugins ship inside Xcode — not with the Command Line
/// Tools this project builds against (see the Makefile header). There is no
/// `libSwiftUIMacros.dylib` anywhere on a CLT-only machine, so `@State`
/// cannot expand and every use of it is a hard compile error.
///
/// Every other SwiftUI wrapper the app uses is still an ordinary property
/// wrapper and still compiles, `@StateObject` included — which is what makes
/// this workable rather than a rewrite. A one-value `ObservableObject` held by
/// `@StateObject` provides exactly the two things `@State` was providing:
/// storage tied to the view's *identity*, so it survives the view struct being
/// re-created on each parent render, and an invalidation when it changes.
///
/// Declare one of these and expose it as a computed property with a
/// `nonmutating set`, so the call sites in `body` read and write the value
/// exactly as they did under `@State`:
///
/// ```swift
/// @StateObject private var hoveredLocal = ViewLocal(false)
/// private var hovered: Bool {
///     get { hoveredLocal.value }
///     nonmutating set { hoveredLocal.value = newValue }
/// }
/// ```
///
/// For view-local, throwaway UI state only — hover flags, an entrance
/// animation's latch. Anything the app actually reasons about belongs on a
/// real model object such as `HUDState` or `SettingsStore`.
final class ViewLocal<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}
