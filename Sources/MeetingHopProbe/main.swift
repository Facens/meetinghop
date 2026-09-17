import AppKit
import ApplicationServices
import EventKit
import Foundation
import MeetingHopKit

// Read-only diagnostic. Never joins, never leaves, never clicks.
//
// This target cannot depend on the MeetingHop app target (an executableTarget's
// non-entry-point symbols are not exported for another executable to link
// against — see Package.swift), so it carries its own thin EventKit
// adapter, matching the shape of CalendarSource in
// the app target. Every classification decision still comes from the Kit
// (`MeetingState.classify`, `CalendarRules`, `MeetingLinkParser`,
// `deduplicatedMeetings()`), so the two binaries cannot drift on anything the
// Diagnostics gate actually compares.
/// Zoom state for the probe, read from window owner names. No Accessibility:
/// the app does not use it either, and owners carry no permission requirement.
enum ProbeZoom {
    private static let shareOwners = ["cpthost", "zoom share"]

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "us.zoom.xos").isEmpty
    }

    static var isSharingScreen: Bool {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return list.contains { window in
            guard let owner = (window[kCGWindowOwnerName as String] as? String)?.lowercased() else {
                return false
            }
            return shareOwners.contains { owner.contains($0) }
        }
    }
}

enum ProbeCalendar {
    static func fetch(store: EKEventStore, now: Date = Date()) -> [UpcomingMeeting] {
        let horizon: TimeInterval = 60 * 60 * 12
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

    private static func currentUserDeclined(_ event: EKEvent) -> Bool? {
        guard let attendees = event.attendees else { return nil }
        guard let me = attendees.first(where: { $0.isCurrentUser }) else { return nil }
        return me.participantStatus == .declined
    }
}

@MainActor
func runProbe() async {
    print("== accessibility ==")
    
    print("\n== zoom ==")
    print("running: \(ProbeZoom.isRunning)  sharing: \(ProbeZoom.isSharingScreen)")
    print("meeting window numbers: \(ZoomWindows.meetingWindowNumbers().sorted())")
    // The "dialogs:" line that used to print here called
    // `ZoomControl.snapshotDialogs()`, which no longer exists: KTD4 deleted
    // the whole leave-button matcher (candidate titles, the end-for-all
    // blocklist, learn mode) rather than gating it, and this probe was never
    // updated to match. Dropped rather than ported, since there is nothing
    // left to snapshot.

    print("\n== calendar ==")
    let store = EKEventStore()
    let ok: Bool
    do {
        ok = try await store.requestFullAccessToEvents()
    } catch {
        ok = false
    }
    print("authorized: \(ok)")
    guard ok else { return }
    let meetings = ProbeCalendar.fetch(store: store)
    print("joinable meetings in next 12h: \(meetings.count)")
    let fmt = DateFormatter()
    fmt.dateFormat = "EEE HH:mm"
    for m in meetings.prefix(8) {
        print("  \(fmt.string(from: m.start))  [\(m.link.provider.rawValue)]  \(m.title)")
        print("       join: \(m.link.appURL?.absoluteString ?? m.link.url.absoluteString)")
    }
}

let sem = DispatchSemaphore(value: 0)
Task { @MainActor in
    await runProbe()
    sem.signal()
}
while sem.wait(timeout: .now()) == .timedOut {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
}
