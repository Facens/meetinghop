import EventKit
import Foundation
import MeetingHopKit

/// Reads the user's calendars and reports the next joinable meeting.
///
/// The EventKit calls live here; the filtering and dedup rules they feed are
/// pure functions in `MeetingHopKit.CalendarRules` and
/// `Array<UpcomingMeeting>.deduplicatedMeetings()` (KTD3).
///
/// EventKit on macOS 14+ requires the full-access request; the older
/// `requestAccess(to:)` is deprecated and returns write-only access.
@MainActor
final class CalendarSource {

    private let store = EKEventStore()
    private var timer: Timer?

    /// How far ahead we look for the next meeting.
    private let horizon: TimeInterval = 60 * 60 * 12

    private(set) var authorized = false

    var onChange: (([UpcomingMeeting]) -> Void)?

    func requestAccess() async -> Bool {
        do {
            authorized = try await store.requestFullAccessToEvents()
        } catch {
            authorized = false
        }
        return authorized
    }

    static var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    func start(pollInterval: TimeInterval = 30) {
        stop()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeChanged),
            name: .EKEventStoreChanged,
            object: store
        )
        let t = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        NotificationCenter.default.removeObserver(self, name: .EKEventStoreChanged, object: store)
    }

    @objc private func storeChanged() {
        Task { @MainActor in refresh() }
    }

    func refresh() {
        guard authorized else { return }
        onChange?(fetch())
    }

    /// Joinable meetings from now to the horizon, earliest first.
    /// Declined events and all-day events are skipped.
    func fetch(now: Date = Date()) -> [UpcomingMeeting] {
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-60 * 60),
            end: now.addingTimeInterval(horizon),
            calendars: nil
        )
        let events = store.events(matching: predicate)

        return events.compactMap { event -> UpcomingMeeting? in
            guard CalendarRules.isJoinable(isAllDay: event.isAllDay, end: event.endDate ?? .distantPast, now: now) else { return nil }
            guard let start = event.startDate, let end = event.endDate else { return nil }
            guard end > now else { return nil }
            guard CalendarRules.selfParticipationIsNotDeclined(
                title: event.title,
                isCancelled: event.status == .canceled,
                currentUserDeclined: currentUserDeclined(event)
            ) else { return nil }
            guard let link = MeetingLinkParser.parse(
                url: event.url?.absoluteString,
                location: event.location,
                notes: event.notes
            ) else { return nil }

            return UpcomingMeeting(
                id: event.eventIdentifier ?? "\(event.title ?? "")-\(start.timeIntervalSince1970)",
                title: event.title ?? "Untitled meeting",
                start: start,
                end: end,
                link: link
            )
        }
        .sorted { $0.start < $1.start }
        .deduplicatedMeetings()
    }

    /// `nil` when there is no attendee list, or no attendee marked
    /// `isCurrentUser` — both read as "not declined" in
    /// `CalendarRules.selfParticipationIsNotDeclined`, matching the
    /// original inline check's two early `return true`s.
    private func currentUserDeclined(_ event: EKEvent) -> Bool? {
        guard let attendees = event.attendees else { return nil }
        guard let me = attendees.first(where: { $0.isCurrentUser }) else { return nil }
        return me.participantStatus == .declined
    }
}
