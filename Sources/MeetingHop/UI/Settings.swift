import SwiftUI
import AppKit
import MeetingHopKit

// MARK: - Store

/// Persisted app preferences, backed by the active `UserDefaults` — KTD4:
/// `.standard` on a normal launch, or the suite `-MeetingHopDefaultsSuite
/// <name>` names on the app-fresh and stranger tiers, resolved once by
/// `AppIdentity.activeDefaults()`. Every property writes through on change,
/// so nothing else in the app has to remember to save — set it and it's
/// durable, in whichever domain this instance was built with.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore(defaults: AppIdentity.activeDefaults())

    // Names and identifier live in MeetingHopKit.AppIdentity, so this
    // target has no literal of its own left to drift from the plist (R19).
    // The clamp and the fallback-on-type-mismatch reads live there too, as
    // `AppIdentity.SettingsStorage` — this target has no logic of its own
    // left to drift from what the Kit's test suite proves (U8).
    private enum Keys {
        static let leadMinutes = AppIdentity.DefaultsKeys.leadMinutes
        static let endingLeadMinutes = AppIdentity.DefaultsKeys.endingLeadMinutes
        static let hideWhileSharing = AppIdentity.DefaultsKeys.hideWhileSharing
    }

    /// The `UserDefaults` every property below reads from and writes
    /// through. `let`, not looked up again per access: KTD4 resolves it
    /// once, at construction, so a run never straddles two domains because
    /// an argument was read at two different moments.
    let defaults: UserDefaults

    /// How many minutes before a meeting starts the card appears.
    @Published var leadMinutes: Int {
        didSet {
            let clamped = AppIdentity.SettingsStorage.clampMinutes(leadMinutes)
            if clamped != leadMinutes {
                leadMinutes = clamped   // re-enters didSet once, then converges
                return
            }
            defaults.set(clamped, forKey: Keys.leadMinutes)
        }
    }

    /// How many minutes before the current meeting ends the handoff card appears.
    @Published var endingLeadMinutes: Int {
        didSet {
            let clamped = AppIdentity.SettingsStorage.clampMinutes(endingLeadMinutes)
            if clamped != endingLeadMinutes {
                endingLeadMinutes = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.endingLeadMinutes)
        }
    }

    @Published var hideWhileSharing: Bool {
        didSet {
            defaults.set(hideWhileSharing, forKey: Keys.hideWhileSharing)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.leadMinutes = AppIdentity.SettingsStorage.storedInt(
            defaults, forKey: Keys.leadMinutes, default: AppIdentity.DefaultsValues.leadMinutes
        )
        self.endingLeadMinutes = AppIdentity.SettingsStorage.storedInt(
            defaults, forKey: Keys.endingLeadMinutes, default: AppIdentity.DefaultsValues.endingLeadMinutes
        )
        self.hideWhileSharing = AppIdentity.SettingsStorage.storedBool(
            defaults, forKey: Keys.hideWhileSharing, default: AppIdentity.DefaultsValues.hideWhileSharing
        )
    }

    /// Registers fallback defaults with `UserDefaults`. Safe to call at
    /// launch, before anything reads a `SettingsStore` property — the
    /// per-property readers above carry their own `default:` too, so this is
    /// belt-and-braces rather than load-bearing. `nonisolated`, so it can run
    /// at launch before any actor hop; `on` defaults to the same
    /// `AppIdentity.activeDefaults()` resolution `.shared` uses, so a caller
    /// that wants the two to agree does not have to pass anything.
    nonisolated static func registerDefaults(on defaults: UserDefaults = AppIdentity.activeDefaults()) {
        AppIdentity.SettingsStorage.registerDefaults(on: defaults)
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
                .accessibilityIdentifier(AccessibilityID.Settings.leadMinutesStepper)
                Stepper(value: $store.endingLeadMinutes, in: 1...15) {
                    minuteLabel(store.endingLeadMinutes, explanation: "Before the current meeting ends")
                }
                .accessibilityIdentifier(AccessibilityID.Settings.endingLeadMinutesStepper)
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
                .accessibilityIdentifier(AccessibilityID.Settings.hideWhileSharingToggle)
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLoginLocal.value)
                    .accessibilityIdentifier(AccessibilityID.Settings.launchAtLoginToggle)
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
        newWindow.setAccessibilityIdentifier(AccessibilityID.Settings.window)
        window = newWindow

        newWindow.makeKeyAndOrderFront(nil)
        // The app runs as .accessory (no Dock icon, no menu bar of its own),
        // so without an explicit activate the window can come up behind
        // whatever app currently has focus.
        NSApp.activate()
    }
}
