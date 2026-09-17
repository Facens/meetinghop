import Foundation

/// Which video conferencing platform a meeting link belongs to.
/// Named `MeetingProvider` (not `MeetingService`): HUDView.swift already
/// defines `enum MeetingService: String, Sendable { case zoom, meet, teams,
/// other }` for driving the HUD's icon/color/display name, and it has no
/// `webex` case, so reusing it here would either collide or under-model
/// webex meetings. Kept as a separate type per the task's explicit fallback.
public enum MeetingProvider: String, Sendable {
    case zoom, meet, teams, webex, other
}

public struct MeetingLink: Equatable, Sendable {
    public let provider: MeetingProvider
    /// Canonical https URL to join. For an already-native zoommtg:// input,
    /// this is reconstructed as the https://zoom.us/j/... form.
    public let url: URL
    /// Native-client deep link, when one exists (currently only Zoom).
    public let appURL: URL?
    public let meetingID: String?
    public let password: String?

    public init(provider: MeetingProvider, url: URL, appURL: URL?, meetingID: String?, password: String?) {
        self.provider = provider
        self.url = url
        self.appURL = appURL
        self.meetingID = meetingID
        self.password = password
    }
}

public enum MeetingLinkParser {

    /// Order of preference: url field, then location, then notes.
    /// Returns the first successful parse.
    public static func parse(url: String?, location: String?, notes: String?) -> MeetingLink? {
        if let url, let link = firstLink(in: url) { return link }
        if let location, let link = firstLink(in: location) { return link }
        if let notes, let link = firstLink(in: notes) { return link }
        return nil
    }

    /// Scans free-form text left-to-right for URL-like tokens and returns the
    /// first one that classifies as a known meeting link, skipping tokens
    /// that don't (e.g. https://zoom.us/download, https://example.com) rather
    /// than giving up at the first URL found.
    public static func firstLink(in text: String) -> MeetingLink? {
        let ns = text as NSString
        let matches = tokenRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let raw = ns.substring(with: m.range)
            let trimmed = trimTrailingPunctuation(raw)
            if let link = classify(trimmed) {
                return link
            }
        }
        return nil
    }

    // MARK: - Tokenizing

    // Matches http(s):// or zoommtg:// tokens. Excludes whitespace and the
    // common wrapping/delimiting characters (<, >, ", ') so that
    // "<https://...>" and href="https://..." stop at the wrapper rather than
    // swallowing it.
    private static let tokenRegex: NSRegularExpression = {
        let pattern = #"(?:https?|zoommtg)://[^\s<>"']+"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    /// Strips trailing punctuation that is very unlikely to be part of a URL
    /// (sentence-ending ".", ",", ")" closing prose, etc). Handles a trailing
    /// ")" specially: only stripped when parens in the remaining string are
    /// unbalanced (more closes than opens), so a URL that legitimately
    /// contains "(" is left alone.
    private static func trimTrailingPunctuation(_ s: String) -> String {
        var result = Substring(s)
        let simpleTrim: Set<Character> = [".", ",", ";", ":", "!", "?", "]", ">", "\"", "'"]
        var changed = true
        while changed {
            changed = false
            if let last = result.last, simpleTrim.contains(last) {
                result.removeLast()
                changed = true
            }
            if result.last == ")" {
                let opens = result.reduce(0) { $0 + ($1 == "(" ? 1 : 0) }
                let closes = result.reduce(0) { $0 + ($1 == ")" ? 1 : 0) }
                if closes > opens {
                    result.removeLast()
                    changed = true
                }
            }
        }
        return String(result)
    }

    // MARK: - Classification

    private static func classify(_ raw: String) -> MeetingLink? {
        // Real invite HTML frequently carries "&amp;" inside href query
        // strings; normalize before URLComponents parses the query.
        let normalized = raw.replacingOccurrences(of: "&amp;", with: "&")

        guard let comps = URLComponents(string: normalized), let host = comps.host?.lowercased() else {
            return nil
        }
        let scheme = (comps.scheme ?? "").lowercased()
        let path = comps.path
        let queryItems = comps.queryItems ?? []
        func queryValue(_ name: String) -> String? {
            queryItems.first(where: { $0.name.lowercased() == name.lowercased() })?.value
        }

        if scheme == "zoommtg" {
            return classifyZoomNative(normalized, host: host, queryValue: queryValue)
        }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") {
            return classifyZoomHTTP(normalized, path: path, queryValue: queryValue)
        }
        if host == "meet.google.com" {
            return classifyMeet(normalized, path: path)
        }
        if host == "teams.microsoft.com" || host == "teams.live.com" {
            return classifyTeams(normalized, path: path)
        }
        if host == "webex.com" || host.hasSuffix(".webex.com") {
            return classifyWebex(normalized, path: path, queryValue: queryValue)
        }
        return nil
    }

    private static func classifyZoomNative(
        _ raw: String, host: String, queryValue: (String) -> String?
    ) -> MeetingLink? {
        guard let confno = queryValue("confno"), !confno.isEmpty else { return nil }
        let pwd = queryValue("pwd")
        guard let appURL = URL(string: raw) else { return nil }
        // The spec's `url` is the canonical https join URL; reconstruct it
        // from the native scheme rather than surfacing zoommtg:// as `url`.
        var httpsString = "https://zoom.us/j/\(confno)"
        if let pwd, !pwd.isEmpty {
            httpsString += "?pwd=\(pwd)"
        }
        guard let httpsURL = URL(string: httpsString) else { return nil }
        return MeetingLink(provider: .zoom, url: httpsURL, appURL: appURL, meetingID: confno, password: pwd)
    }

    private static func classifyZoomHTTP(
        _ raw: String, path: String, queryValue: (String) -> String?
    ) -> MeetingLink? {
        let segments = path.split(separator: "/").map(String.init)
        guard segments.count >= 2 else { return nil }
        let kind = segments[0]
        let idOrVanity = segments[1]
        guard ["j", "w", "my"].contains(kind) else { return nil }
        guard let url = URL(string: raw) else { return nil }
        let pwd = queryValue("pwd")

        var appURL: URL?
        if kind == "j" || kind == "w" {
            var s = "zoommtg://zoom.us/join?action=join&confno=\(idOrVanity)"
            if let pwd, !pwd.isEmpty {
                let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
                let encoded = pwd.addingPercentEncoding(withAllowedCharacters: allowed) ?? pwd
                s += "&pwd=\(encoded)"
            }
            appURL = URL(string: s)
        } else {
            // "/my/<vanity>" personal room: no numeric confno to build a
            // zoommtg:// deep link from, so appURL is left nil. The vanity
            // name is still surfaced as meetingID.
            appURL = nil
        }
        return MeetingLink(provider: .zoom, url: url, appURL: appURL, meetingID: idOrVanity, password: pwd)
    }

    private static func classifyMeet(_ raw: String, path: String) -> MeetingLink? {
        let code = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Real Meet codes are three lowercase-letter groups like
        // "abc-defg-hij"; requiring this shape avoids matching other
        // meet.google.com paths (e.g. "/lookup/...").
        guard code.range(of: "^[a-z]{2,}-[a-z]{2,}-[a-z]{2,}$", options: .regularExpression) != nil else {
            return nil
        }
        guard let url = URL(string: raw) else { return nil }
        return MeetingLink(provider: .meet, url: url, appURL: nil, meetingID: code, password: nil)
    }

    private static func classifyTeams(_ raw: String, path: String) -> MeetingLink? {
        guard path.contains("/meetup-join/") || path.contains("/meet/") else { return nil }
        guard let url = URL(string: raw) else { return nil }
        // Teams meeting identifiers are opaque encoded thread IDs, not a
        // simple token worth surfacing as meetingID; left nil.
        return MeetingLink(provider: .teams, url: url, appURL: nil, meetingID: nil, password: nil)
    }

    private static func classifyWebex(
        _ raw: String, path: String, queryValue: (String) -> String?
    ) -> MeetingLink? {
        guard path.contains("/meet/") || path.contains("/j.php") else { return nil }
        guard let url = URL(string: raw) else { return nil }
        var meetingID = queryValue("mtid")
        if meetingID == nil, path.contains("/meet/") {
            meetingID = path.split(separator: "/").last.map(String.init)
        }
        return MeetingLink(provider: .webex, url: url, appURL: nil, meetingID: meetingID, password: nil)
    }
}
