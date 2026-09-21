import Foundation

/// Whether a bundle path sits inside macOS's App Translocation mountpoint —
/// the randomized, read-only `/private/var/.../AppTranslocation/<uuid>/d/
/// <App>.app` copy Gatekeeper substitutes for a quarantined app that has
/// never been moved out of the folder it was quarantined in.
///
/// Discovered the hard way, 2026-09-21: the harness used to assume a Finder
/// move out of that folder was enough to stop it (`clear_quarantine`'s own
/// comment in `harness/lib/scenario.sh` still records the belief), and a
/// reproducible VM test disproved it — a scripted Finder move, fully
/// consented, still translocated. Only removing the quarantine attribute and
/// relaunching does, which needs a second launch the harness cannot make
/// instant, and a MeetingHop that requests calendar access within ~25ms of
/// launch (today's app fix) can have that request orphaned by it. Detecting
/// translocation and not asking at all removes the request the race was
/// ever a race about, from the side that actually knows it is translocated —
/// the running process — rather than from a harness pretending to be a user.
///
/// It is also not only a harness problem: a translocated MeetingHop is not
/// the app a real user keeps. The mount is read-only, so nothing can write
/// an update into it, and its path is different on every single launch, so
/// Sparkle has no stable location to replace and a calendar grant handed to
/// today's random path is worthless once tomorrow's launch translocates to a
/// different one. The fix a translocated launch needs is not a permission —
/// it is being moved to `/Applications`, which is also the one thing that
/// makes it updatable at all.
///
/// Pure over a path string, not over `Bundle.main`, so it is provable from
/// `Tests/MeetingHopKitTests` (which cannot link the app target — see this
/// Kit's other doc comments for why) without ever needing a real translocated
/// bundle. `Coordinator.start()` is the one real call site, and hands in
/// `Bundle.main.bundlePath`.
///
/// Named and shaped to match AgentMenuKit's `BundleTranslocation` — the two
/// apps hit the identical Gatekeeper behaviour and share this fix.
public enum BundleTranslocation {

    /// The path component App Translocation always inserts (macOS 10.12
    /// onward). Substring matching, rather than resolving symlinks or reading
    /// further `Bundle` state, because the translocated path itself is the
    /// one fact this has to be right about, whatever produced the path a
    /// caller hands in.
    public static let marker = "/AppTranslocation/"

    /// Whether `bundlePath` names a translocated copy.
    public static func isTranslocated(bundlePath: String) -> Bool {
        bundlePath.contains(marker)
    }
}
