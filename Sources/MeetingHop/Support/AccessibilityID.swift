import Foundation
import MeetingHopKit

/// The app-facing half of KTD9's identifier contract.
///
/// `MeetingHopKit.AccessibilityID` holds the real string builders — it has
/// to, since `Tests/MeetingHopKitTests/AccessibilityIDTests.swift` can only
/// reach code inside `MeetingHopKit` (see the comment on that file for why).
/// This file adds nothing but convenience: overloads that accept the app's
/// own view-model types (`HUDModel.Item`, defined in `HUDView.swift`, and
/// `MeetingHopKit.UpcomingMeeting` itself, used directly by
/// `MenuBar.swift`'s row view) and forward to the Kit builders, hashing a
/// meeting's `id` the one place it does so. Every raw value a control
/// actually carries is defined exactly once, in the Kit file; nothing here
/// recomputes or duplicates one.
extension AccessibilityID.HUD {
    static func join(_ item: HUDModel.Item) -> String {
        join(idHash: AccessibilityID.hash(item.meeting.id))
    }
}

extension AccessibilityID.MenuBar {
    static func row(_ meeting: UpcomingMeeting) -> String {
        row(idHash: AccessibilityID.hash(meeting.id))
    }
}
