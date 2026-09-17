import SwiftUI
import AppKit
import MeetingHopKit

// MARK: - Store

/// Persisted app preferences, backed directly by `UserDefaults.standard`.
/// Every property writes through on change, so nothing else in the app has
/// to remember to save — set it and it's durable.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    // Names and identifier live in MeetingHopKit.AppIdentity, so this
    // target has no literal of its own left to drift from the plist (R19).
    private enum Keys {
        static let leadMinutes = AppIdentity.DefaultsKeys.leadMinutes
        static let endingLeadMinutes = AppIdentity.DefaultsKeys.endingLeadMinutes
        static let hideWhileSharing = AppIdentity.DefaultsKeys.hideWhileSharing
    }

    // Immutable Int/Bool constants from the Kit, so `nonisolated` is safe
    // even though they're declared on a @MainActor type — `registerDefaults()`
    // (also `nonisolated`, so it can run at launch before any actor hop) needs
    // to read them without a MainActor context.
    private nonisolated static let defaultLeadMinutes = AppIdentity.DefaultsValues.leadMinutes
    private nonisolated static let defaultEndingLeadMinutes = AppIdentity.DefaultsValues.endingLeadMinutes
    private nonisolated static let defaultHideWhileSharing = AppIdentity.DefaultsValues.hideWhileSharing
    private static let validRange = 1...15

    /// How many minutes before a meeting starts the card appears.
    @Published var leadMinutes: Int = SettingsStore.storedInt(
        forKey: Keys.leadMinutes, default: defaultLeadMinutes
    ) {
        didSet {
            let clamped = SettingsStore.clamp(leadMinutes)
            if clamped != leadMinutes {
                leadMinutes = clamped   // re-enters didSet once, then converges
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.leadMinutes)
        }
    }

    /// How many minutes before the current meeting ends the handoff card appears.
    @Published var endingLeadMinutes: Int = SettingsStore.storedInt(
        forKey: Keys.endingLeadMinutes, default: defaultEndingLeadMinutes
    ) {
        didSet {
            let clamped = SettingsStore.clamp(endingLeadMinutes)
            if clamped != endingLeadMinutes {
                endingLeadMinutes = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.endingLeadMinutes)
        }
    }

    @Published var hideWhileSharing: Bool = SettingsStore.storedBool(
        forKey: Keys.hideWhileSharing, default: defaultHideWhileSharing
    ) {
        didSet {
            UserDefaults.standard.set(hideWhileSharing, forKey: Keys.hideWhileSharing)
        }
    }

    private init() {}

    /// Registers fallback defaults with `UserDefaults`. Safe to call at
    /// launch, before anything reads a `SettingsStore` property — the
    /// per-property readers below carry their own `default:` too, so this is
    /// belt-and-braces rather than load-bearing.
    nonisolated static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.leadMinutes: defaultLeadMinutes,
            Keys.endingLeadMinutes: defaultEndingLeadMinutes,
            Keys.hideWhileSharing: defaultHideWhileSharing,
        ])
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, validRange.lowerBound), validRange.upperBound)
    }

    /// `object(forKey:)` + a conditional cast never traps, unlike
    /// `integer(forKey:)`'s silent-zero-on-type-mismatch: a stray non-Int
    /// value written by a future version falls back to `default` instead of
    /// quietly becoming 0 and failing the 1...15 clamp in a confusing way.
    private static func storedInt(forKey key: String, default value: Int) -> Int {
        guard let stored = UserDefaults.standard.object(forKey: key) as? Int else { return value }
        return clamp(stored)
    }

    private static func storedBool(forKey key: String, default value: Bool) -> Bool {
        guard let stored = UserDefaults.standard.object(forKey: key) as? Bool else { return value }
        return stored
    }
}

// MARK: - View

/// Deliberately unbranded: this is a system-style settings pane, not the
/// HUD's own rose-accented card, so it should look like it belongs to macOS
/// rather than to MeetingHop's own chrome.
@MainActor
struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    /// `LaunchAtLogin` (Support.swift) wraps `SMAppService` and isn't
    /// observable, so its current value is mirrored into local state and
    /// pushed back out on change.
    ///
    /// `@State` is a macro in the macOS 26 SDK and its plugin ships with Xcode,
    /// which this project does not build with — see `ViewLocal` in Support.swift.
    @StateObject private var launchAtLoginLocal = ViewLocal(LaunchAtLogin.isEnabled)

    private var launchAtLogin: Bool {
        get { launchAtLoginLocal.value }
        nonmutating set { launchAtLoginLocal.value = newValue }
    }

    // No default for `store`: a default argument is checked against the
    // *caller's* isolation, not this @MainActor struct's, so `= .shared`
    // here would still trip the same "nonisolated context" diagnostic that
    // callers should never have to work around. Callers pass `.shared`
    // explicitly instead (see `SettingsWindowController.show()`).
    init(store: SettingsStore) {
        self.store = store
    }

    var body: some View {
        Form {
            Section("When the card appears") {
                Stepper(value: $store.leadMinutes, in: 1...15) {
                    minuteLabel(store.leadMinutes, explanation: "Before the next meeting starts")
                }
                Stepper(value: $store.endingLeadMinutes, in: 1...15) {
                    minuteLabel(store.endingLeadMinutes, explanation: "Before the current meeting ends")
                }
            }

            Section {
                Toggle(isOn: $store.hideWhileSharing) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide while screen sharing")
                        Text("Keeps the card off your screen so other participants never see it")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLoginLocal.value)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLogin.set(newValue)
                        // `set` only logs on failure (Support.swift), it
                        // doesn't throw out to here — re-read the real
                        // status so the toggle can't be left showing "on"
                        // when SMAppService actually refused (e.g. an
                        // ad-hoc-signed build). Harmless no-op when it
                        // succeeded: the value read back is what we just wrote.
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        // Re-sync on every reshow, in case the user (or macOS) changed
        // launch-at-login somewhere outside this window since it was built.
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    private func minuteLabel(_ minutes: Int, explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(minutes) minute\(minutes == 1 ? "" : "s")")
            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Window

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    /// Creates the window on first call and reuses it after; the window is
    /// never released on close (see below), so a second `show()` just brings
    /// the same window back rather than building a new one.
    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(store: .shared))
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "MeetingHop Settings"
        newWindow.styleMask = [.titled, .closable]
        // Keep the window instance around after the user closes it, so
        // `show()` can reshow it instead of rebuilding SwiftUI state.
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        window = newWindow

        newWindow.makeKeyAndOrderFront(nil)
        // The app runs as .accessory (no Dock icon, no menu bar of its own),
        // so without an explicit activate the window can come up behind
        // whatever app currently has focus.
        NSApp.activate()
    }
}
