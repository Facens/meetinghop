import Foundation

/// How an offer was answered.
///
/// One set of ids used to carry all of this, under the name `dismissed`, and
/// the two surfaces that read it wanted different things from it. The card
/// wants "answered, do not offer this again", which is true of every case
/// below. The menu-bar pill wants "the user dealt with this, stop reminding
/// them", which is only true of some of them — and reading the card's set for
/// the pill's question is what made a stray click on the close button take
/// the meeting off every surface at once.
public enum MeetingAnswer: String, Sendable, Equatable, CaseIterable {
    /// The Join button, on the card or in the popover. The only answer that
    /// is evidence the user actually went.
    case joined

    /// The close button, pressed before the meeting started. "Stop covering
    /// my screen", not "forget it" — the pill keeps counting down, and keeps
    /// reading "now" once the meeting starts, until the grace window ends.
    case closed

    /// The close button, pressed after the meeting had already started. The
    /// user was looking at a card for a meeting that was running and said no,
    /// which is a decision rather than a deferral, so the pill goes quiet too.
    case declined
}

/// Every answer this copy of MeetingHop has recorded, by meeting id.
///
/// A value type with no `UserDefaults` in it: `Coordinator` owns the
/// persistence and this owns the rules, so the three derived sets below can
/// be proven from the test suite without a defaults domain.
public struct MeetingAnswers: Equatable, Sendable {
    private var byID: [String: MeetingAnswer]

    public init(_ byID: [String: MeetingAnswer] = [:]) {
        self.byID = byID
    }

    /// Decodes what `storage` wrote. An unrecognised raw value is dropped
    /// rather than defaulted: a future version that adds a fourth answer and
    /// is then downgraded would otherwise have its unknown answers silently
    /// read as whichever case this version picked, and the wrong one of those
    /// guesses re-offers a meeting the user already answered.
    public init(storage: [String: String]) {
        self.byID = storage.compactMapValues(MeetingAnswer.init(rawValue:))
    }

    /// The `[String: String]` form, which is a property-list type and so can
    /// go straight into `UserDefaults`.
    public var storage: [String: String] {
        byID.mapValues(\.rawValue)
    }

    public subscript(id: String) -> MeetingAnswer? { byID[id] }

    public var isEmpty: Bool { byID.isEmpty }

    /// The card's set: an answered meeting is never offered again, whichever
    /// way it was answered.
    public var answered: Set<String> {
        Set(byID.keys)
    }

    /// The pill's set: the answers that stop the menu bar reminding the user
    /// about a meeting that is under way. `closed` is deliberately absent —
    /// see `MeetingAnswer.closed`.
    public var silenced: Set<String> {
        Set(byID.filter { $0.value != .closed }.keys)
    }

    /// The popover header's set. "In <meeting>" claims the user is sitting in
    /// it, and only a join is evidence of that: closing a card for a meeting
    /// that has started says the opposite.
    public var joined: Set<String> {
        Set(byID.filter { $0.value == .joined }.keys)
    }

    public mutating func record(_ answer: MeetingAnswer, for id: String) {
        byID[id] = answer
    }

    /// The close button, which is `closed` or `declined` depending on whether
    /// the meeting had already started when it was pressed. The caller passes
    /// the meeting's own start rather than a flag, so the distinction is made
    /// in one place instead of at each call site.
    public mutating func close(_ id: String, start: Date, now: Date) {
        record(start <= now ? .declined : .closed, for: id)
    }

    /// Drops answers for meetings that are no longer live, so the record stays
    /// the size of a day rather than growing for as long as the app is
    /// installed. Returns whether anything changed, so the caller can skip a
    /// pointless write on every five-second tick.
    @discardableResult
    public mutating func prune(keeping live: Set<String>) -> Bool {
        let kept = byID.filter { live.contains($0.key) }
        guard kept.count != byID.count else { return false }
        byID = kept
        return true
    }

    /// Folds the old `dismissedMeetingIDs` array into this record.
    ///
    /// Every id in it is taken as `joined`, which is what the old single set
    /// meant at every one of its read sites: the card did not re-offer it, the
    /// pill did not watch it once it had started, and the popover header was
    /// willing to say "In <meeting>". Reading them as `closed` instead would
    /// be more literally true of some of them and would put a "now" pill back
    /// on a meeting the user is sitting in, the first time they update.
    public static func migrating(legacy ids: [String]) -> MeetingAnswers {
        MeetingAnswers(Dictionary(uniqueKeysWithValues: Set(ids).map { ($0, .joined) }))
    }

    /// Merges `other` into this record, keeping this record's answer where
    /// both hold one. Used once, to fold a legacy array in underneath answers
    /// this version has already written.
    public func merging(under other: MeetingAnswers) -> MeetingAnswers {
        MeetingAnswers(other.byID.merging(byID) { _, mine in mine })
    }
}

/// The `UserDefaults` side of `MeetingAnswers`.
///
/// In the Kit rather than in `Coordinator` for the reason
/// `AppIdentity.SettingsStorage` already gives: the app target is unreachable
/// from `Tests/MeetingHopKitTests`, and `migrateLegacy(in:)` is the only path
/// in this app that *deletes* a key out of a domain the user owns. A rule
/// that destructive should be provable from the test suite rather than
/// inspected.
public enum MeetingAnswerStorage {

    public static func load(from defaults: UserDefaults) -> MeetingAnswers {
        let stored = defaults.dictionary(forKey: AppIdentity.DefaultsKeys.meetingAnswers) as? [String: String]
        return MeetingAnswers(storage: stored ?? [:])
    }

    public static func save(_ answers: MeetingAnswers, to defaults: UserDefaults) {
        defaults.set(answers.storage, forKey: AppIdentity.DefaultsKeys.meetingAnswers)
    }

    /// Folds a pre-`meetingAnswers` copy's `dismissedMeetingIDs` array into
    /// the answers record and removes it. Returns whether there was one.
    ///
    /// Everything happens in the single `defaults` it is handed, which is
    /// `AppIdentity.activeDefaults()` at the call site — the harness suite on
    /// a `-MeetingHopDefaultsSuite` launch, `.standard` otherwise. A harness
    /// run must not reach past its suite and delete the real user's key, and
    /// that is what `MeetingAnswersTests` pins.
    ///
    /// Answers already recorded in the new key win over the legacy array, so
    /// a stale array left behind by a downgrade cannot overwrite them.
    @discardableResult
    public static func migrateLegacy(in defaults: UserDefaults) -> Bool {
        let key = AppIdentity.DefaultsKeys.dismissedMeetingIDs
        guard let legacy = defaults.stringArray(forKey: key) else { return false }
        if !legacy.isEmpty {
            save(load(from: defaults).merging(under: .migrating(legacy: legacy)), to: defaults)
        }
        defaults.removeObject(forKey: key)
        return true
    }
}
