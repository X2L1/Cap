import Foundation

/// Minimal iCalendar (.ics) parser, just enough to pull assignment/event titles and due
/// dates out of a Canvas Calendar Feed. Canvas exposes a personal feed URL (Calendar →
/// "Calendar Feed") with an embedded secret — it works even when an institution disables
/// personal access tokens, which is the whole reason this path exists.
///
/// We deliberately don't pull in a full RFC 5545 library: we only need VEVENT SUMMARY and
/// DTSTART/DTEND. Recurrence, alarms, timezones-by-reference, etc. are out of scope.
enum ICSParser {
    static func parse(_ raw: String) -> [CanvasItem] {
        let unfolded = unfold(raw)
        var items: [CanvasItem] = []
        var inEvent = false
        var summary: String?
        var dtRaw: String?
        var uid: String?

        for line in unfolded.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "BEGIN:VEVENT" {
                inEvent = true; summary = nil; dtRaw = nil; uid = nil
            } else if trimmed == "END:VEVENT" {
                if let summary {
                    items.append(
                        CanvasItem(
                            id: uid ?? UUID().uuidString,
                            name: cleanSummary(summary),
                            dueDate: dtRaw.flatMap(parseDate)
                        )
                    )
                }
                inEvent = false
            } else if inEvent {
                guard let (name, params, value) = splitProperty(trimmed) else { continue }
                switch name {
                case "SUMMARY": summary = unescape(value)
                case "UID": uid = value
                case "DTSTART": dtRaw = dateString(value: value, params: params)
                case "DTEND" where dtRaw == nil: dtRaw = dateString(value: value, params: params)
                default: break
                }
            }
        }
        return items
    }

    // MARK: - Line handling

    /// RFC 5545 folds long lines by inserting CRLF followed by a space/tab. Rejoin them.
    private static func unfold(_ raw: String) -> String {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var result = ""
        for line in normalized.components(separatedBy: "\n") {
            if let first = line.first, first == " " || first == "\t" {
                result += String(line.dropFirst())
            } else {
                if !result.isEmpty { result += "\n" }
                result += line
            }
        }
        return result
    }

    /// Splits "DTSTART;TZID=America/Chicago:20260115T235900" into
    /// ("DTSTART", ["TZID": "America/Chicago"], "20260115T235900").
    private static func splitProperty(_ line: String) -> (String, [String: String], String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let lhs = String(line[line.startIndex..<colon])
        let value = String(line[line.index(after: colon)...])
        let parts = lhs.components(separatedBy: ";")
        guard let name = parts.first?.uppercased() else { return nil }
        var params: [String: String] = [:]
        for p in parts.dropFirst() {
            let kv = p.components(separatedBy: "=")
            if kv.count == 2 { params[kv[0].uppercased()] = kv[1] }
        }
        return (name, params, value)
    }

    private static func dateString(value: String, params: [String: String]) -> String {
        // Stash the TZID (if any) alongside the value so parseDate can resolve it.
        if let tz = params["TZID"] { return "TZID=\(tz):\(value)" }
        return value
    }

    // MARK: - Dates

    private static func parseDate(_ raw: String) -> Date? {
        var tzID: String?
        var value = raw
        if raw.hasPrefix("TZID="), let colon = raw.firstIndex(of: ":") {
            tzID = String(raw[raw.index(raw.startIndex, offsetBy: 5)..<colon])
            value = String(raw[raw.index(after: colon)...])
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if value.hasSuffix("Z") {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")
            return formatter.date(from: value)
        }
        if value.contains("T") {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss"
            formatter.timeZone = tzID.flatMap(TimeZone.init(identifier:)) ?? .current
            return formatter.date(from: value)
        }
        // All-day (VALUE=DATE): yyyyMMdd
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = tzID.flatMap(TimeZone.init(identifier:)) ?? .current
        return formatter.date(from: value)
    }

    // MARK: - Text

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Canvas summaries look like "Essay 2 [HIST 105]". Keep it as-is — the bracketed
    /// course code is actually useful context for the model.
    private static func cleanSummary(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
