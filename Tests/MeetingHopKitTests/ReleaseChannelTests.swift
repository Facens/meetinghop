import Foundation
import MeetingHopKit

/// R20 / KTD10 (as amended): `ReleaseChannel(version:)` implements the same
/// grammar as `packaging/version.sh`'s `version_channel`, in Swift rather
/// than bash, for the app to classify its own version at runtime. This suite
/// runs the same table `BundleVersionTests` runs against the real script, so
/// the two implementations are pinned together — a change to one grammar
/// without the other shows up as a failure here or there.
func runReleaseChannelTests(_ t: TestRunner) {
    t.suite("ReleaseChannel")

    let accepted: [(version: String, channel: ReleaseChannel)] = [
        ("0.2.0", .stable),
        ("0.2.0-beta.1", .beta),
        ("0.2.0-beta.99", .beta),
        ("0.2.0-alpha", .alpha),
    ]
    for entry in accepted {
        t.expectEqual(
            ReleaseChannel(version: entry.version), entry.channel,
            "\(entry.version) parses as .\(entry.channel.rawValue)"
        )
    }

    // Same rejected list BundleVersionTests runs against the script: N out
    // of 1...99 on both ends, an unknown pre-release tag, an alpha with a
    // trailing component, a leading v, too few or too many components, and
    // plain garbage. Every one must come back nil, never a best-effort guess.
    let rejected = [
        "0.2.0-beta.0", "0.2.0-beta.100", "0.2.0-rc1", "0.2.0-alpha.1",
        "v0.2.0", "0.2", "1.2.3.4", "abc", "0.2.0\n", "0.2.0-beta.1\n",
    ]
    for version in rejected {
        t.expect(ReleaseChannel(version: version) == nil, "\(version) is rejected")
    }
}
