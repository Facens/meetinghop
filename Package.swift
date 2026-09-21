// swift-tools-version:5.9
import PackageDescription

// KTD1: a MeetingHopKit library plus MeetingHop/MeetingHopProbe executables,
// mirroring AgentMenu's AgentMenuKit / AgentMenu boundary — see that
// project's Package.swift for the shape this follows.
//
// Two executable product names must differ by more than case — the default
// macOS filesystem is case-insensitive, so e.g. "MeetingHop" and
// "meetinghop" would collide in .build before either linked. MeetingHop and
// MeetingHopProbe already differ by more than case; keep that true of
// whatever gets added next.
let package = Package(
    name: "MeetingHop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MeetingHop", targets: ["MeetingHop"]),
        .executable(name: "MeetingHopProbe", targets: ["MeetingHopProbe"]),
        .library(name: "MeetingHopKit", targets: ["MeetingHopKit"]),
        // Declared explicitly (unlike AgentMenuKitTests in the sibling
        // project) so `swift build --product MeetingHopKitTests` resolves —
        // that exact command is this unit's verification gate, and `swift
        // run` resolving against targets is not the same guarantee.
        .executable(name: "MeetingHopKitTests", targets: ["MeetingHopKitTests"]),
    ],
    // U13 / R12: Sparkle is attached to the app executable alone, below.
    // The same floor AgentMenu pins, and the same reason: the package
    // resolves an XCFramework that packaging/bundle.sh copies into the
    // bundle and signs bottom-up.
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .target(
            name: "MeetingHopKit",
            path: "Sources/MeetingHopKit"
        ),
        .executableTarget(
            name: "MeetingHop",
            // Sparkle here and nowhere else: attaching it to MeetingHopKit
            // would pull AppKit into the probe and the test runner, which
            // packaging/check-source.sh exists to prevent.
            dependencies: ["MeetingHopKit", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/MeetingHop",
            linkerSettings: [
                // The framework ships inside the bundle, so the executable
                // resolves @rpath/Sparkle.framework relative to itself.
                // Without this the app links here and dies at launch
                // everywhere, including here.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        // Depends on the Kit only, not on MeetingHop: an executableTarget's
        // non-entry-point symbols are not exported for another executable to
        // link against (confirmed by trying it — the build compiles, then
        // fails at link with "symbol(s) not found"). So the probe carries its
        // own thin AXUIElement/EventKit adapter, matching ZoomAccessibility's
        // and CalendarSource's shape, but every classification decision
        // still comes from the Kit (MeetingState.classify, CalendarRules,
        // MeetingLinkParser, deduplicatedMeetings) — the two binaries cannot
        // drift on anything that matters to the Diagnostics gate.
        .executableTarget(
            name: "MeetingHopProbe",
            dependencies: ["MeetingHopKit"],
            path: "Sources/MeetingHopProbe"
        ),
        // The test runner is a plain executable, not a `.testTarget`.
        // XCTest and swift-testing are Xcode-only tooling: neither module
        // exists in a Command Line Tools install. `make test` runs this;
        // U2 ports AgentMenu's Harness.swift and wires the first suites.
        .executableTarget(
            name: "MeetingHopKitTests",
            dependencies: ["MeetingHopKit"],
            path: "Tests/MeetingHopKitTests"
        ),
    ]
)
