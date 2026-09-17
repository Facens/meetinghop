import Foundation

/// An upcoming calendar event that has something joinable attached to it.
public struct UpcomingMeeting: Equatable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let link: MeetingLink

    public init(id: String, title: String, start: Date, end: Date, link: MeetingLink) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.link = link
    }

    public var isInProgress: Bool {
        let now = Date()
        return now >= start && now < end
    }

    public func minutesUntilStart(from now: Date = Date()) -> Int {
        Int((start.timeIntervalSince(now) / 60).rounded(.down))
    }
}

/// The pure calendar rules that used to live inline in `CalendarWatcher`,
/// extracted so they can be exercised with plain values instead of live
/// `EKEvent`/`EKParticipant` objects. `CalendarSource` (app target) is the
/// only caller: it reads EventKit and translates each event into the plain
/// values these take.
public enum CalendarRules {

    /// Exchange/Outlook often does not mark the current user as an attendee
    /// at all; it rewrites the event title to "Declined: ..." instead.
    /// Checking only `participantStatus` therefore lets declined meetings
    /// through.
    public static let declinedTitlePrefixes = [
        "declined:", "rifiutato:", "rifiutata:", "abgelehnt:", "refusé:", "rechazado:", "geweigerd:",
    ]

    /// Whether the event should be treated as accepted by the current user.
    ///
    /// `currentUserDeclined` mirrors the three-way outcome of the original
    /// `EKEvent.attendees` lookup: `nil` when there is no attendee list, or
    /// no attendee marked `isCurrentUser` (both cases read as "not
    /// declined", matching the original's `return true`); otherwise whether
    /// that attendee's `participantStatus == .declined`.
    /// An all-day entry is a marker, not something to join, even when the
    /// invitation body it carries has a link in it. Lifted out of the EventKit
    /// reader so the exclusion can be tested with the rest of them.
    public static func isJoinable(isAllDay: Bool, end: Date, now: Date) -> Bool {
        !isAllDay && end > now
    }

    public static func selfParticipationIsNotDeclined(
        title: String?,
        isCancelled: Bool,
        currentUserDeclined: Bool?
    ) -> Bool {
        if let title = title?.trimmingCharacters(in: .whitespaces).lowercased(),
           declinedTitlePrefixes.contains(where: { title.hasPrefix($0) }) {
            return false
        }
        if isCancelled { return false }
        return currentUserDeclined != true
    }
}

public extension Array where Element == UpcomingMeeting {
    /// The same meeting often appears several times: synced into more than one
    /// local calendar, or invited both directly and via a group alias. Collapse
    /// on the join target plus the start time, which is what actually makes two
    /// rows the same meeting.
    func deduplicatedMeetings() -> [UpcomingMeeting] {
        var seen = Set<String>()
        return filter { meeting in
            let key = [
                meeting.link.meetingID ?? meeting.link.url.absoluteString,
                String(Int(meeting.start.timeIntervalSince1970)),
            ].joined(separator: "|")
            return seen.insert(key).inserted
        }
    }
}
