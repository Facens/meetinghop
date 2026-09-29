import AppKit
import MeetingHopKit

/// Draws the one-shot "launch at login?" ask as a native `NSAlert`, in place
/// of the custom HUD panel this used to be (`LaunchAtLoginPromptView.swift`,
/// removed). The owner's call: this question is asked exactly once per
/// install, and the standard system alert is what macOS users already know
/// how to answer, rather than a third bespoke card competing with the
/// calendar guidance card for the same onboarding real estate. Mirrors
/// `../agentmenu/Sources/AgentMenu/Support/LaunchAtLoginPrompt.swift` — same
/// button order, same activation dance, same icon source — down to the
/// comments explaining each one, since every line there fixes a bug an
/// AgentMenu VM gate actually found.
///
/// Named `LaunchAtLoginAlert`, not `LaunchAtLoginPrompt` the way AgentMenu's
/// own presenter is: `MeetingHopKit` already exports a type of that name —
/// the pure `decide` rule this one calls through `Coordinator` — and a
/// second type of the same name in the app target would make every
/// `LaunchAtLoginPrompt.…` reference in `Coordinator.swift` ambiguous.
///
/// Everything that decides WHETHER to ask, and everything that remembers
/// the answer, stays exactly where it was: `MeetingHopKit.LaunchAtLoginPrompt
/// .decide`, `LaunchAtLoginPromptStorage`, and `Coordinator
/// .launchAtLoginPromptAnswered`. This type only draws the question and
/// hands the raw yes/no back — the same split `Coordinator`'s own
/// `presentLaunchAtLoginPrompt` closure already drew between "decide" and
/// "draw" for the HUD-panel version.
enum LaunchAtLoginAlert {

    /// Shows the alert and reports whether "Launch at Login" was pressed.
    ///
    /// Call this from one run-loop turn after the decision to show it, via
    /// `RunLoop.main.perform` at the call site (`AppDelegate
    /// .showLaunchAtLoginPrompt`'s own comment explains why that and not
    /// `DispatchQueue.main.async`, AgentMenu's own recipe) — never
    /// synchronously from `applicationDidFinishLaunching`. `NSApp.activate`
    /// asked for by an app that has not finished launching yet is silently
    /// ignored, and an alert shown to an app that is not active draws its
    /// default button grey instead of tinted — the exact failure AgentMenu's
    /// own `LaunchAtLoginPrompt.presentIfNeeded` doc comment names for the
    /// identical alert on the v0.2.2-beta.2 gate.
    @MainActor
    static func present(completion: @escaping (_ accepted: Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = LaunchAtLoginPromptCopy.title
        alert.informativeText = LaunchAtLoginPromptCopy.body
        // Added first, so it is the default (Return-triggering) button —
        // "Launch at Login" is `alertFirstButtonReturn`. "Not Now" second.
        alert.addButton(withTitle: LaunchAtLoginPromptCopy.accept)
            .setAccessibilityIdentifier(AccessibilityID.LaunchAtLoginPrompt.accept)
        alert.addButton(withTitle: LaunchAtLoginPromptCopy.decline)
            .setAccessibilityIdentifier(AccessibilityID.LaunchAtLoginPrompt.decline)

        // The bundle's own .icns (packaging/bundle.sh copies it in as
        // Contents/Resources/MeetingHop.icns), never
        // NSApp.applicationIconImage or NSWorkspace.icon(forFile:) — both go
        // through Launch Services, which on a machine that has only just
        // seen this bundle for the first time has not rendered its icon yet
        // and hands back the generic placeholder. Same finding as
        // AgentMenu's own two v0.2.2 gate runs, for the same reason: this
        // file does not depend on Launch Services' cache, that call does.
        if let icon = Bundle.main.image(forResource: "MeetingHop") {
            alert.icon = icon
        }

        // A menu-bar accessory app is never the active app at launch, and an
        // inactive app's alert draws its default button grey — activating
        // first is what makes "Launch at Login" read as the tinted default.
        NSApp.activate(ignoringOtherApps: true)
        let accepted = alert.runModal() == .alertFirstButtonReturn
        completion(accepted)
    }
}
