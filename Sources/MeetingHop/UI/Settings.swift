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
        static let betaUpdates = AppIdentity.DefaultsKeys.betaUpdates
    }

    /// The `UserDefaults` every property below reads from and writes
    /// through. `let`, not looked up again per access: KTD4 resolves it
    /// once, at construction, so a run never straddles two domains because
    /// an argument was read at two different moments.
    let defaults: UserDefaults

    /// Whether this copy takes beta updates — nil until the user says
    /// either way, and then `UpdatePolicy.betaEnabled(preference:version:)`
    /// resolves it from the running build (KTD20). `object(forKey:)` rather
    /// than `bool(forKey:)`, which cannot tell "off" from "never asked".
    @Published var betaUpdates: Bool? {
        didSet {
            if let betaUpdates {
                defaults.set(betaUpdates, forKey: Keys.betaUpdates)
            } else {
                defaults.removeObject(forKey: Keys.betaUpdates)
            }
        }
    }

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
        // No default and no clamp: absent is a state, not a missing value.
        self.betaUpdates = defaults.object(forKey: Keys.betaUpdates) as? Bool
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
    /// Sparkle's controller, or nil in a context that has none (a preview,
    /// or a build whose updater never started). Nil renders the section
    /// disabled with its reason, never absent: a settings window that
    /// silently loses a section reads as a bug.
    private let updater: UpdaterController?

    /// Sparkle owns this preference, so it is mirrored the same way
    /// launch-at-login is rather than stored twice (KTD8).
    @StateObject private var automaticChecksLocal: ViewLocal<Bool>

    init(store: SettingsStore, updater: UpdaterController? = nil) {
        self.store = store
        self.updater = updater
        _automaticChecksLocal = StateObject(
            wrappedValue: ViewLocal(updater?.automaticallyChecksForUpdates ?? false)
        )
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

            Section("Updates") {
                if let refusal = updater?.refusal {
                    Text("Updates are off: \(refusal.description).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(AccessibilityID.Settings.Updates.unavailable)
                }

                Toggle("Check for updates automatically", isOn: $automaticChecksLocal.value)
                    .accessibilityIdentifier(AccessibilityID.Settings.Updates.automatic)
                    .onChange(of: automaticChecksLocal.value) { _, newValue in
                        updater?.automaticallyChecksForUpdates = newValue
                        // Read back, like launch-at-login: Sparkle is the
                        // owner of this value and the toggle must show what
                        // it actually holds, not what we asked for.
                        automaticChecksLocal.value = updater?.automaticallyChecksForUpdates ?? false
                    }

                Toggle("Receive beta updates", isOn: Binding(
                    get: {
                        UpdatePolicy.betaEnabled(
                            preference: store.betaUpdates, version: AppVersion.display()
                        )
                    },
                    set: { store.betaUpdates = $0 }
                ))
                .accessibilityIdentifier(AccessibilityID.Settings.Updates.beta)

                HStack {
                    Button("Check Now") { updater?.checkForUpdates() }
                        .accessibilityIdentifier(AccessibilityID.Settings.Updates.checkNow)
                    if let last = updater?.lastUpdateCheckDate {
                        Text("Last checked \(last.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                }
            }
            .disabled(updater == nil || updater?.refusal != nil)

            Section {
                Text("MeetingHop \(AppVersion.display())")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420)
        .fixedSize(horizontal: false, vertical: true)
        // Re-sync on every reshow, in case the user (or macOS) changed
        // launch-at-login somewhere outside this window since it was built.
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            automaticChecksLocal.value = updater?.automaticallyChecksForUpdates ?? false
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

/// Owned by this app rather than by a SwiftUI `Settings` scene, and given
/// the activation policy somewhere honest to live: an accessory app has no
/// menu bar of its own, so it becomes a regular app while the window is up
/// and goes back when it closes. Mirrors AgentMenu's SettingsWindowController.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    /// Creates the window on first call and reuses it after; the window is
    /// never released on close (see below), so a second `show()` just brings
    /// the same window back rather than building a new one.
    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView(store: .shared, updater: AppDelegate.shared?.updaterController)
            )
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "MeetingHop Settings"
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            // SettingsView used to pin its own width with a hard
            // `.frame(width: 420)`; `.resizable` above means nothing does
            // that anymore, so the window is given that width explicitly
            // instead, asking the content how tall it wants to be at that
            // width — SettingsView's `.fixedSize(vertical: true)` still
            // governs the answer, unchanged by this.
            let fitted = hosting.sizeThatFits(in: NSSize(width: 420, height: CGFloat.greatestFiniteMagnitude))
            // A guard, not the expected path: unlike plain `view.fittingSize`
            // — zero until the view is in a window, per `MenuBarModel
            // .preferredSize`'s comment on that exact pitfall — `sizeThatFits`
            // runs its own layout pass and does not need the window on
            // screen first. But there is no way to see this window and
            // confirm that, so a pathological zero falls back to a literal
            // rather than opening a window with no height at all.
            let height = fitted.height > 0 ? fitted.height : 480
            newWindow.setContentSize(NSSize(width: 420, height: height))
            // Keep the window instance around after the user closes it, so
            // `show()` can reshow it instead of rebuilding SwiftUI state.
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            newWindow.center()
            newWindow.setAccessibilityIdentifier(AccessibilityID.Settings.window)
            window = newWindow
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a menu-bar-only app: no Dock icon, no menu of its own.
        NSApp.setActivationPolicy(.accessory)
    }
}
