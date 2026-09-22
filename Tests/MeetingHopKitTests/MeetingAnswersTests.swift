import Foundation
import MeetingHopKit

/// `MeetingAnswers` exists because one flat set of dismissed ids answered two
/// different questions, and a stray click on a card's close button therefore
/// took a meeting off the card *and* out of the menu bar at once. These pin
/// the three derived sets that keep those questions apart, the storage shape
/// `Coordinator` persists, and the one-time fold of the old array.
func runMeetingAnswersTests(_ t: TestRunner) {
    t.suite("MeetingAnswers")

    let base = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - The three questions

    do {
        var answers = MeetingAnswers()
        answers.record(.joined, for: "went")
        answers.record(.closed, for: "closed-early")
        answers.record(.declined, for: "closed-late")

        t.expectEqual(answers.answered, ["went", "closed-early", "closed-late"], "the card never re-offers anything that was answered, however it was answered")
        t.expectEqual(answers.silenced, ["went", "closed-late"], "the pill is silenced by a join or a post-start close, never by an ordinary close")
        t.expectEqual(answers.joined, ["went"], "only a join lets the popover say \"In <meeting>\"")
    }

    // MARK: - Which close it was is decided from the meeting's own start

    do {
        var answers = MeetingAnswers()
        let start = base.addingTimeInterval(2 * 60)
        answers.close("ahead", start: start, now: base)
        t.expectEqual(answers["ahead"], .closed, "closing a card two minutes before the meeting is a deferral")

        answers.close("running", start: base.addingTimeInterval(-60), now: base)
        t.expectEqual(answers["running"], .declined, "closing a card for a meeting already under way is a decision")

        // The boundary belongs to the meeting: at exactly the start time it is
        // running, so the close is a decision.
        answers.close("exactly", start: base, now: base)
        t.expectEqual(answers["exactly"], .declined, "a close at exactly the start time counts as declining it")
    }

    // MARK: - An answer replaces the one before it

    do {
        var answers = MeetingAnswers()
        answers.record(.closed, for: "twice")
        answers.record(.joined, for: "twice")
        t.expectEqual(answers["twice"], .joined, "joining after closing is the answer that stands")
        t.expectEqual(answers.silenced, ["twice"], "and it silences the pill, which the close alone did not")
    }

    // MARK: - Storage round-trips, and refuses to guess

    do {
        var answers = MeetingAnswers()
        answers.record(.joined, for: "a")
        answers.record(.closed, for: "b")
        answers.record(.declined, for: "c")

        let storage = answers.storage
        t.expectEqual(storage["a"], "joined", "the stored form is the raw value, so a plist can hold it")
        t.expectEqual(MeetingAnswers(storage: storage), answers, "and it decodes back to the same answers")

        // A copy that has been downgraded finds a raw value this version has
        // never heard of. Dropping it re-offers the meeting, which is the
        // harmless direction; guessing a case could silence a meeting the
        // user never answered.
        let fromFuture = MeetingAnswers(storage: ["a": "joined", "d": "snoozed"])
        t.expectEqual(fromFuture.answered, ["a"], "an unrecognised answer is dropped rather than guessed at")
    }

    // MARK: - Pruning

    do {
        var answers = MeetingAnswers([
            "live": .joined,
            "gone": .closed,
        ])
        t.expect(answers.prune(keeping: ["live"]), "pruning reports that it changed something")
        t.expectEqual(answers.answered, ["live"], "an answer outlives nothing: the meeting it belongs to has ended")
        t.expect(!answers.prune(keeping: ["live"]), "a prune that changes nothing says so, so the caller can skip the write")
    }

    // MARK: - The one-time fold of `dismissedMeetingIDs`

    do {
        let legacy = MeetingAnswers.migrating(legacy: ["old-a", "old-b", "old-a"])
        t.expectEqual(legacy.answered, ["old-a", "old-b"], "every id in the old array is an answer, duplicates collapsed")
        t.expectEqual(legacy.silenced, ["old-a", "old-b"], "read as joins, because that is what the old set meant at every read site")
        t.expectEqual(legacy.joined, ["old-a", "old-b"], "including the popover header, which the old set was allowed to drive")

        // A stale array left behind by a downgrade must not overwrite answers
        // this version has already recorded.
        var mine = MeetingAnswers()
        mine.record(.closed, for: "old-a")
        let merged = mine.merging(under: legacy)
        t.expectEqual(merged["old-a"], .closed, "an answer this version recorded wins over the legacy array")
        t.expectEqual(merged["old-b"], .joined, "and the rest of the legacy array still comes across")
    }

    // MARK: - The migration, against a real defaults domain

    ({
        let suiteName = "MeetingAnswersTests.migrate.\(UUID().uuidString)"
        let bystanderName = "MeetingAnswersTests.bystander.\(UUID().uuidString)"
        guard
            let scratch = UserDefaults(suiteName: suiteName),
            let bystander = UserDefaults(suiteName: bystanderName)
        else {
            t.expect(false, "could create two scratch UserDefaults suites")
            return
        }
        defer {
            scratch.removePersistentDomain(forName: suiteName)
            bystander.removePersistentDomain(forName: bystanderName)
        }

        // A copy updating from a version that only had the flat array. The
        // bystander stands in for `.standard` during a harness run: the
        // migration is handed one domain and must not reach past it.
        scratch.set(["legacy-1", "legacy-2"], forKey: AppIdentity.DefaultsKeys.dismissedMeetingIDs)
        bystander.set(["someone-elses"], forKey: AppIdentity.DefaultsKeys.dismissedMeetingIDs)

        t.expect(MeetingAnswerStorage.migrateLegacy(in: scratch), "the migration reports that it found a legacy array")

        let migrated = MeetingAnswerStorage.load(from: scratch)
        t.expectEqual(migrated.answered, ["legacy-1", "legacy-2"], "both ids survive as answers")
        t.expectEqual(migrated.silenced, ["legacy-1", "legacy-2"], "read as joins, which is what the old set meant")
        t.expectEqual(
            scratch.stringArray(forKey: AppIdentity.DefaultsKeys.dismissedMeetingIDs), nil,
            "and the superseded key is gone, so the fold happens exactly once"
        )
        t.expectEqual(
            bystander.stringArray(forKey: AppIdentity.DefaultsKeys.dismissedMeetingIDs) ?? [],
            ["someone-elses"],
            "a migration handed one domain never deletes another's key — a harness run must not touch the real user's"
        )
        t.expectEqual(
            bystander.dictionary(forKey: AppIdentity.DefaultsKeys.meetingAnswers) as? [String: String], nil,
            "and never writes into another's either"
        )

        // Idempotent: the second launch has nothing to fold, and answers
        // recorded since the first one are left alone.
        var since = MeetingAnswerStorage.load(from: scratch)
        since.record(.closed, for: "legacy-1")
        MeetingAnswerStorage.save(since, to: scratch)
        t.expect(!MeetingAnswerStorage.migrateLegacy(in: scratch), "a second launch finds nothing to migrate")
        t.expectEqual(
            MeetingAnswerStorage.load(from: scratch)["legacy-1"], .closed,
            "and does not resurrect the legacy array over an answer given since"
        )
    })()

    // MARK: - Round-tripping through a domain

    ({
        let suiteName = "MeetingAnswersTests.storage.\(UUID().uuidString)"
        guard let scratch = UserDefaults(suiteName: suiteName) else {
            t.expect(false, "could create a scratch UserDefaults suite")
            return
        }
        defer { scratch.removePersistentDomain(forName: suiteName) }

        t.expect(MeetingAnswerStorage.load(from: scratch).isEmpty, "a domain with no answers in it reads as empty, not nil")

        var answers = MeetingAnswers()
        answers.record(.declined, for: "x")
        MeetingAnswerStorage.save(answers, to: scratch)
        t.expectEqual(MeetingAnswerStorage.load(from: scratch), answers, "what was saved is what comes back")
    })()
}
