import Foundation
import MeetingHopKit

/// Ported from `tools/tests.swift` (U2/R3), which sat unrun until this suite
/// wired it in — moved case for case, preserving every assertion, so the
/// count below (69) is the baseline the runner's per-suite count protects.
func runMeetingLinkTests(_ t: TestRunner) {
    t.suite("MeetingLink")

    // MARK: Zoom - basic /j/
    do {
        let link = MeetingLinkParser.parse(url: "https://zoom.us/j/1234567890", location: nil, notes: nil)
        t.expect(link != nil, "zoom basic /j/ parses")
        t.expectEqual(link?.provider, .zoom, "zoom basic provider")
        t.expectEqual(link?.meetingID, "1234567890", "zoom basic meetingID")
        t.expectEqual(link?.appURL?.absoluteString, "zoommtg://zoom.us/join?action=join&confno=1234567890", "zoom basic appURL exact (no pwd)")
        t.expectEqual(link?.password, nil, "zoom basic password nil")
    }

    // MARK: Zoom - subdomain + pwd
    do {
        let link = MeetingLinkParser.parse(url: "https://us02web.zoom.us/j/1234567890?pwd=abcDEF123", location: nil, notes: nil)
        t.expect(link != nil, "zoom subdomain+pwd parses")
        t.expectEqual(link?.meetingID, "1234567890", "zoom subdomain+pwd meetingID")
        t.expectEqual(link?.password, "abcDEF123", "zoom subdomain+pwd password")
        t.expectEqual(link?.appURL?.absoluteString, "zoommtg://zoom.us/join?action=join&confno=1234567890&pwd=abcDEF123", "zoom subdomain+pwd appURL exact (with pwd)")
    }

    // MARK: Zoom - arbitrary company subdomain
    do {
        let link = MeetingLinkParser.parse(url: "https://acmecorp.zoom.us/j/123456789", location: nil, notes: nil)
        t.expect(link != nil, "zoom company subdomain parses")
        t.expectEqual(link?.meetingID, "123456789", "zoom company subdomain meetingID")
    }

    // MARK: Zoom - webinar /w/
    do {
        let link = MeetingLinkParser.parse(url: "https://zoom.us/w/1234567890?tk=sometoken", location: nil, notes: nil)
        t.expect(link != nil, "zoom webinar /w/ parses")
        t.expectEqual(link?.meetingID, "1234567890", "zoom webinar meetingID")
        t.expectEqual(link?.password, nil, "zoom webinar password nil (tk isn't pwd)")
    }

    // MARK: Zoom - personal room /my/
    do {
        let link = MeetingLinkParser.parse(url: "https://zoom.us/my/somename", location: nil, notes: nil)
        t.expect(link != nil, "zoom personal room parses")
        t.expectEqual(link?.meetingID, "somename", "zoom personal room meetingID is vanity name")
        t.expectEqual(link?.appURL, nil, "zoom personal room appURL nil")
    }

    // MARK: Zoom - already-native zoommtg:// with pwd
    do {
        let link = MeetingLinkParser.parse(url: "zoommtg://zoom.us/join?action=join&confno=1234567890&pwd=abcDEF123", location: nil, notes: nil)
        t.expect(link != nil, "zoom native parses")
        t.expectEqual(link?.meetingID, "1234567890", "zoom native meetingID")
        t.expectEqual(link?.password, "abcDEF123", "zoom native password")
        t.expectEqual(link?.url.absoluteString, "https://zoom.us/j/1234567890?pwd=abcDEF123", "zoom native url is canonical https")
        t.expectEqual(link?.appURL?.absoluteString, "zoommtg://zoom.us/join?action=join&confno=1234567890&pwd=abcDEF123", "zoom native appURL is original zoommtg")
    }

    // MARK: Zoom - already-native zoommtg:// without pwd
    do {
        let link = MeetingLinkParser.parse(url: "zoommtg://zoom.us/join?action=join&confno=1234567890", location: nil, notes: nil)
        t.expect(link != nil, "zoom native no-pwd parses")
        t.expectEqual(link?.url.absoluteString, "https://zoom.us/j/1234567890", "zoom native no-pwd url has no ?pwd")
        t.expectEqual(link?.password, nil, "zoom native no-pwd password nil")
    }

    // MARK: Zoom - non-alphanumeric password percent-encoding round-trip
    do {
        let link = MeetingLinkParser.parse(url: "https://us02web.zoom.us/j/1234567890?pwd=aB3%2Bd%2Ff%3D", location: nil, notes: nil)
        t.expect(link != nil, "zoom non-alnum pwd parses")
        t.expectEqual(link?.password, "aB3+d/f=", "zoom non-alnum pwd decodes exactly")
        t.expectEqual(link?.appURL?.absoluteString, "zoommtg://zoom.us/join?action=join&confno=1234567890&pwd=aB3%2Bd%2Ff%3D", "zoom non-alnum pwd re-encoded exactly in appURL")
    }
    do {
        let link = MeetingLinkParser.parse(url: "zoommtg://zoom.us/join?action=join&confno=1234567890&pwd=aB3%2Bd%2Ff%3D", location: nil, notes: nil)
        t.expect(link != nil, "zoom native non-alnum pwd parses")
        t.expectEqual(link?.password, "aB3+d/f=", "zoom native non-alnum pwd decoded")
        t.expectEqual(link?.url.absoluteString, "https://zoom.us/j/1234567890?pwd=aB3+d/f=", "zoom native non-alnum pwd reconstructed https url")
    }

    // MARK: location-over-notes precedence (independent of url field)
    do {
        let link = MeetingLinkParser.parse(
            url: nil,
            location: "https://zoom.us/j/2222222222",
            notes: "https://meet.google.com/abc-defg-hij"
        )
        t.expectEqual(link?.provider, .zoom, "location takes precedence over notes when url is nil")
        t.expectEqual(link?.meetingID, "2222222222", "location precedence meetingID")
    }

    // MARK: Equatable
    do {
        let a = MeetingLinkParser.parse(url: "https://zoom.us/j/1234567890", location: nil, notes: nil)
        let b = MeetingLinkParser.parse(url: "https://zoom.us/j/1234567890", location: nil, notes: nil)
        t.expectEqual(a, b, "two identical parses are Equatable-equal")
    }

    // MARK: Google Meet
    do {
        let link = MeetingLinkParser.parse(url: "https://meet.google.com/abc-defg-hij", location: nil, notes: nil)
        t.expect(link != nil, "meet parses")
        t.expectEqual(link?.provider, .meet, "meet provider")
        t.expectEqual(link?.meetingID, "abc-defg-hij", "meet meetingID")
    }

    // MARK: Teams - meetup-join
    do {
        let link = MeetingLinkParser.parse(url: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_xxx%40thread.v2/0?context=%7B%22Tid%22%3A%221%22%7D", location: nil, notes: nil)
        t.expect(link != nil, "teams meetup-join parses")
        t.expectEqual(link?.provider, .teams, "teams meetup-join provider")
    }

    // MARK: Teams - teams.live.com/meet/
    do {
        let link = MeetingLinkParser.parse(url: "https://teams.live.com/meet/1234567890", location: nil, notes: nil)
        t.expect(link != nil, "teams.live.com meet parses")
        t.expectEqual(link?.provider, .teams, "teams.live.com provider")
    }

    // MARK: Webex - /meet/
    do {
        let link = MeetingLinkParser.parse(url: "https://acmecorp.webex.com/meet/jsmith", location: nil, notes: nil)
        t.expect(link != nil, "webex /meet/ parses")
        t.expectEqual(link?.provider, .webex, "webex /meet/ provider")
        t.expectEqual(link?.meetingID, "jsmith", "webex /meet/ meetingID")
    }

    // MARK: Webex - j.php?MTID=
    do {
        let link = MeetingLinkParser.parse(url: "https://acmecorp.webex.com/j.php?MTID=m1234567890abcdef", location: nil, notes: nil)
        t.expect(link != nil, "webex j.php parses")
        t.expectEqual(link?.meetingID, "m1234567890abcdef", "webex j.php meetingID from MTID")
    }

    // MARK: Negative cases
    do {
        let link = MeetingLinkParser.parse(url: "https://zoom.us/download", location: nil, notes: nil)
        t.expectEqual(link, nil, "zoom /download is NOT a match")
    }
    do {
        let link = MeetingLinkParser.parse(url: "https://support.zoom.us/hc/en-us/articles/123456", location: nil, notes: nil)
        t.expectEqual(link, nil, "support.zoom.us article is NOT a match")
    }
    do {
        let link = MeetingLinkParser.parse(url: "https://example.com", location: nil, notes: nil)
        t.expectEqual(link, nil, "plain example.com is NOT a match")
    }
    do {
        let link = MeetingLinkParser.parse(url: nil, location: nil, notes: "Just some prose with no links at all.")
        t.expectEqual(link, nil, "prose with no links returns nil")
    }

    // MARK: Punctuation-wrapped links
    do {
        let link = MeetingLinkParser.firstLink(in: "Join via <https://zoom.us/j/1234567890> in your browser.")
        t.expect(link != nil, "angle-bracket wrapped link parses")
        t.expectEqual(link?.meetingID, "1234567890", "angle-bracket wrapped meetingID clean")
    }
    do {
        let link = MeetingLinkParser.firstLink(in: "Join here: https://zoom.us/j/1234567890.")
        t.expectEqual(link?.meetingID, "1234567890", "trailing period stripped")
    }
    do {
        let link = MeetingLinkParser.firstLink(in: "(see https://zoom.us/j/1234567890)")
        t.expectEqual(link?.meetingID, "1234567890", "trailing unbalanced paren stripped")
    }
    do {
        let link = MeetingLinkParser.firstLink(in: "Link: https://zoom.us/j/1234567890, thanks")
        t.expectEqual(link?.meetingID, "1234567890", "trailing comma stripped")
    }

    // MARK: href-embedded links
    do {
        let link = MeetingLinkParser.firstLink(in: "<a href=\"https://zoom.us/j/1234567890?pwd=abcDEF123\">Click to join</a>")
        t.expect(link != nil, "href-embedded link parses")
        t.expectEqual(link?.meetingID, "1234567890", "href-embedded meetingID")
        t.expectEqual(link?.password, "abcDEF123", "href-embedded password")
    }
    do {
        let link = MeetingLinkParser.firstLink(in: "<a href=\"https://us02web.zoom.us/j/1234567890?uname=x&amp;pwd=abcDEF123\">Click</a>")
        t.expect(link != nil, "href with &amp; before pwd parses")
        t.expectEqual(link?.password, "abcDEF123", "href with &amp; password correct despite entity")
    }

    // MARK: url / location / notes precedence
    do {
        // url field is present but not a meeting link -> must fall through to location
        let link = MeetingLinkParser.parse(
            url: "https://example.com",
            location: "https://zoom.us/j/1234567890",
            notes: "https://meet.google.com/abc-defg-hij"
        )
        t.expect(link != nil, "falls through non-meeting url to location")
        t.expectEqual(link?.provider, .zoom, "falls through picks location's zoom link")
    }
    do {
        // url field wins over location/notes when it IS a meeting link
        let link = MeetingLinkParser.parse(
            url: "https://zoom.us/j/1111111111",
            location: "https://meet.google.com/abc-defg-hij",
            notes: "https://acmecorp.webex.com/meet/jsmith"
        )
        t.expectEqual(link?.provider, .zoom, "url field takes precedence over location/notes")
        t.expectEqual(link?.meetingID, "1111111111", "url field precedence meetingID")
    }
    do {
        // only notes carries a link
        let link = MeetingLinkParser.parse(
            url: nil,
            location: nil,
            notes: "Lots of prose here.\n\nJoin Zoom Meeting\nhttps://zoom.us/j/9998887770?pwd=xyzPWD1\n\nMeeting ID: 999 888 7770"
        )
        t.expect(link != nil, "notes-only parses")
        t.expectEqual(link?.meetingID, "9998887770", "notes-only meetingID")
        t.expectEqual(link?.password, "xyzPWD1", "notes-only password")
    }

    // MARK: scanning skips unrelated urls to find the real one
    do {
        let link = MeetingLinkParser.firstLink(in: "Download the app at https://zoom.us/download or check https://support.zoom.us/hc/en-us first, then join https://zoom.us/j/1234567890")
        t.expect(link != nil, "scan skips non-meeting urls before real one")
        t.expectEqual(link?.meetingID, "1234567890", "scan finds the zoom /j/ link after skipping")
    }
}
