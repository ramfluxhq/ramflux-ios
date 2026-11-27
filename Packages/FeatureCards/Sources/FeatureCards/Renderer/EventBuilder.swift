// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
import AppData
import RFLocalization
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Simple Markdown for card text (spec 4.1): inline emphasis and "-" or "*" bullets. Headings, images and links are never
/// produced: links are stripped so a tap cannot open anything, and bidirectional controls are removed from untrusted text.
enum CardMarkdown {
    static func attributed(_ raw: String) -> AttributedString {
        let clean = RFUntrustedText(raw, kind: .messageBody).text
        var result = AttributedString()
        for (index, line) in clean.components(separatedBy: "\n").enumerated() {
            if index > 0 { result += AttributedString("\n") }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let body = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") ? "•  " + String(trimmed.dropFirst(2)) : line
            var piece = (try? AttributedString(markdown: body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(body)
            let linked = piece.runs.compactMap { $0.link == nil ? nil : $0.range }
            for range in linked { piece[range].link = nil }
            result += piece
        }
        return result
    }
}

/// Error messages of a node. The runtime sends strings or objects with a `message`; anything else is dropped.
func cardErrors(_ json: JSONValue?) -> [String] {
    guard case .array(let rows)? = json else { return [] }
    return rows.compactMap { $0.string ?? $0["message"]?.string }
}

/// Date and date-time values of DateTimeInput. Date-only values are `yyyy-MM-dd` at midnight UTC; date-times are RFC 3339.
enum CardDates {
    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    static func parse(_ value: String, withTime: Bool) -> Date? {
        if withTime {
            return ISO8601DateFormatter().date(from: value)
        }
        let formatter = dateOnlyFormatter()
        return formatter.date(from: value)
    }

    static func format(_ date: Date, withTime: Bool) -> String {
        if withTime {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.string(from: date)
        }
        return dateOnlyFormatter().string(from: date)
    }

    private static func dateOnlyFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

/// Opens a confirmed link in the system browser. Callers pass only a validated https URL after the runtime answered `opened`.
@MainActor
public enum CardLinkOpener {
    public static func open(_ url: URL) {
        #if canImport(UIKit)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }
}
