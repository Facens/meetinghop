import Foundation
import MeetingHopKit

/// `BundleTranslocation.isTranslocated` — pure over a path string, so every
/// case here is a string literal rather than a real translocated bundle. See
/// that type's own doc comment for why this predicate exists at all: it is
/// what lets `Coordinator.start()` skip a calendar request the running
/// process already knows would be wasted on a mount that will not exist by
/// the next launch.
func runBundleTranslocationTests(_ t: TestRunner) {
    t.suite("BundleTranslocation")

    // A real translocated path, captured on a stranger-tier clone of
    // first-run-golden on 2026-09-21, after a scripted Finder move and a
    // fully consented Gatekeeper sheet — the exact test that disproved the
    // harness's old "a Finder move stops it" assumption.
    t.expect(
        BundleTranslocation.isTranslocated(
            bundlePath: "/private/var/folders/g9/dkt5zts549s6xhd6lmmz7hvm0000gn/T/AppTranslocation/FA6E6F9A-8F54-4362-A020-2EB735167FC2/d/MeetingHop.app"
        ),
        "a real translocated path is detected"
    )
    t.expect(
        !BundleTranslocation.isTranslocated(bundlePath: "/Applications/MeetingHop.app"),
        "the real install location is never mistaken for a translocated one"
    )
    t.expect(
        !BundleTranslocation.isTranslocated(bundlePath: "/Users/admin/Downloads/MeetingHop.app"),
        "an unmoved download is not itself translocation — this is the state App Translocation exists to replace, not the state it produces"
    )
    t.expect(
        !BundleTranslocation.isTranslocated(bundlePath: ""),
        "an empty path is not translocated"
    )
    t.expect(
        BundleTranslocation.isTranslocated(bundlePath: "/AppTranslocation/x/d/MeetingHop.app"),
        "the marker at the very start of the path still counts — no assumption about what comes before it"
    )
    t.expect(
        !BundleTranslocation.isTranslocated(bundlePath: "/Applications/AppTranslocationHelper.app"),
        "a bundle whose own name merely contains the word is not translocated — the marker must be a path component (wrapped in slashes), not a free substring of the name"
    )
}
