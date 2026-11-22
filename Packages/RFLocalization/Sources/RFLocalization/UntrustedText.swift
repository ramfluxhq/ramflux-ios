// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// The base direction of a run of text.
public enum RFTextDirection: Equatable, Sendable {
    case leftToRight, rightToLeft
}

/// Bidirectional text helpers for text the app does not control.
///
/// Untrusted text (display names, group names, file names, message text, previews, node
/// origins) must not reorder the app's own text around it. Two rules apply everywhere:
/// directional embedding, override and isolate controls are removed from it, and when it is
/// placed inside app text it is wrapped in a first-strong isolate (FSI ... PDI).
public enum RFBidi {
    public static let leftToRightIsolate: Unicode.Scalar = "\u{2066}"
    public static let firstStrongIsolate: Unicode.Scalar = "\u{2068}"
    public static let popDirectionalIsolate: Unicode.Scalar = "\u{2069}"

    /// U+202A-202E (embeddings, overrides, PDF) and U+2066-2069 (isolates). They can reorder text
    /// outside the run that carries them.
    public static func isEmbeddingOrIsolate(_ scalar: Unicode.Scalar) -> Bool {
        (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
    }

    /// LRM, RLM and ALM. They only influence neighbouring neutral characters.
    public static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x200E || scalar.value == 0x200F || scalar.value == 0x061C
    }

    /// Untrusted text prepared for insertion into app text: identity-sanitised and wrapped in FSI ... PDI.
    public static func isolate(_ untrusted: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(firstStrongIsolate)
        scalars.append(contentsOf: RFUntrustedText(untrusted, kind: .identity).text.unicodeScalars)
        scalars.append(popDirectionalIsolate)
        return String(scalars)
    }

    /// Text that must read left to right in every locale, wrapped in LRI ... PDI after its own
    /// controls are removed.
    public static func isolateLeftToRight(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(leftToRightIsolate)
        scalars.append(contentsOf: text.unicodeScalars.filter { !isEmbeddingOrIsolate($0) && !isMark($0) })
        scalars.append(popDirectionalIsolate)
        return String(scalars)
    }

    /// The base direction of a message from its content: the first strong character after
    /// skipping @mentions, links and inline code. Nil when the text has no strong character
    /// (digits, emoji, punctuation only); the caller keeps the surrounding direction then.
    public static func firstStrongDirection(of text: String) -> RFTextDirection? {
        var skipping: Skip = .none
        var previous: Unicode.Scalar = " "
        var index = text.unicodeScalars.startIndex
        let scalars = text.unicodeScalars
        while index < scalars.endIndex {
            let scalar = scalars[index]
            switch skipping {
            case .code:
                if scalar == "`" { skipping = .none }
            case .word:
                if scalar.properties.isWhitespace { skipping = .none }
            case .none:
                if scalar == "`" {
                    skipping = .code
                } else if scalar == "@" && previous.properties.isWhitespace {
                    skipping = .word
                } else if previous.properties.isWhitespace && startsLink(scalars[index...]) {
                    skipping = .word
                } else if let direction = strongDirection(scalar) {
                    return direction
                }
            }
            previous = scalar
            index = scalars.index(after: index)
        }
        return nil
    }

    private enum Skip { case none, code, word }

    private static func startsLink(_ rest: String.UnicodeScalarView.SubSequence) -> Bool {
        let head = String(String.UnicodeScalarView(rest.prefix(8))).lowercased()
        return head.hasPrefix("http://") || head.hasPrefix("https://") || head.hasPrefix("www.")
    }

    /// Strong right-to-left: Hebrew, Arabic, Syriac, Thaana, NKo, Samaritan, Mandaic and their
    /// presentation forms. Strong left-to-right: any other letter.
    public static func strongDirection(_ scalar: Unicode.Scalar) -> RFTextDirection? {
        let value = scalar.value
        let rtlRanges: [ClosedRange<UInt32>] = [
            0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF,
        ]
        if scalar.properties.isAlphabetic && !scalar.properties.generalCategory.isMark {
            return rtlRanges.contains { $0.contains(value) } ? .rightToLeft : .leftToRight
        }
        return nil
    }
}

private extension Unicode.GeneralCategory {
    var isMark: Bool { self == .nonspacingMark || self == .spacingMark || self == .enclosingMark }
}

/// Untrusted text with directional controls neutralised.
///
/// Visible behaviour: removed controls leave no glyph and no gap; the surrounding characters
/// keep their logical order. `containedDirectionalControls` reports that something was removed,
/// so a screen can show `KitSecurityWarning` for an identity that tried to reorder text.
public struct RFUntrustedText: Equatable, Sendable {
    public enum Kind: Sendable {
        /// Display names, group names, node origins: every directional control and mark is removed.
        case identity
        /// File names: as identity; the extension is shown separately by `KitFileName`.
        case fileName
        /// Message text and previews: embeddings, overrides and isolates are removed; LRM, RLM and
        /// ALM stay because writers use them to place punctuation.
        case messageBody
    }

    public let text: String
    public let containedDirectionalControls: Bool

    public init(_ raw: String, kind: Kind) {
        var kept = String.UnicodeScalarView()
        var removed = false
        for scalar in raw.unicodeScalars {
            let drop = RFBidi.isEmbeddingOrIsolate(scalar) || (kind != .messageBody && RFBidi.isMark(scalar))
            if drop { removed = true } else { kept.append(scalar) }
        }
        text = String(kept)
        containedDirectionalControls = removed
    }
}

/// A file name split so the extension cannot be hidden or disguised.
public struct RFFileName: Equatable, Sendable {
    /// The name before the extension, controls removed.
    public let stem: String
    /// ASCII letters and digits after the last dot (1 to 10 of them), or nil.
    public let fileExtension: String?
    public let containedDirectionalControls: Bool

    public init(_ raw: String) {
        let clean = RFUntrustedText(raw, kind: .fileName)
        containedDirectionalControls = clean.containedDirectionalControls
        let name = clean.text
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            let candidate = name[name.index(after: dot)...]
            if (1...10).contains(candidate.count), candidate.unicodeScalars.allSatisfy({ $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0)) }) {
                stem = String(name[..<dot])
                fileExtension = String(candidate)
                return
            }
        }
        stem = name
        fileExtension = nil
    }
}

/// Identifiers that are compared by people: safety numbers, fingerprints, pairing codes, the
/// six-digit code, device ids, recovery words.
public enum RFIdentifier {
    /// Western digits and ASCII letters in left-to-right order in every locale. Arabic-Indic,
    /// Extended Arabic-Indic, Devanagari and fullwidth digits become ASCII digits; directional
    /// controls are removed; the result is wrapped in LRI ... PDI.
    public static func display(_ raw: String) -> String {
        RFBidi.isolateLeftToRight(normalizedDigits(raw))
    }

    public static func normalizedDigits(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            if let ascii = asciiDigit(scalar) { scalars.append(ascii) } else { scalars.append(scalar) }
        }
        return String(scalars)
    }

    private static func asciiDigit(_ scalar: Unicode.Scalar) -> Unicode.Scalar? {
        let zeros: [UInt32] = [0x0660, 0x06F0, 0x0966, 0xFF10]
        for zero in zeros where (zero...(zero + 9)).contains(scalar.value) {
            return Unicode.Scalar(0x30 + scalar.value - zero)
        }
        return nil
    }
}

/// An argument inserted into a localized sentence.
public enum RFTextArgument: Equatable, Sendable {
    /// Peer-controlled text (a name, a group name, a file name): sanitised and FSI-isolated.
    case untrusted(String)
    /// An identifier: Western digits, left to right, LRI-isolated.
    case identifier(String)
    /// App text already localized for the same locale; inserted as is.
    case localized(String)
    /// A count, formatted with the locale's digits and grouping.
    case count(Int)
}

/// Builds a sentence from a localized format and typed arguments, so word order and
/// separators stay in the catalog and untrusted text cannot reorder the sentence.
///
/// The format accepts `%@`, `%d`, `%i`, `%u`, `%ld`, `%lld`, their positional forms (`%1$@`,
/// `%2$lld`) and `%%`. A placeholder without an argument becomes empty text; it never crashes.
public enum RFSentence {
    public static func compose(_ format: String, _ arguments: [RFTextArgument], locale: Locale) -> String {
        var output = ""
        var sequential = 0
        var index = format.startIndex
        while index < format.endIndex {
            let character = format[index]
            guard character == "%" else {
                output.append(character)
                index = format.index(after: index)
                continue
            }
            var cursor = format.index(after: index)
            guard cursor < format.endIndex else { output.append(character); break }
            if format[cursor] == "%" {
                output.append("%")
                index = format.index(after: cursor)
                continue
            }
            var position: Int?
            var digits = ""
            var probe = cursor
            while probe < format.endIndex, let digit = format[probe].wholeNumberValue, format[probe].isASCII {
                digits.append(String(digit))
                probe = format.index(after: probe)
            }
            if !digits.isEmpty, probe < format.endIndex, format[probe] == "$" {
                position = Int(digits)
                cursor = format.index(after: probe)
            }
            while cursor < format.endIndex, format[cursor] == "l" { cursor = format.index(after: cursor) }
            guard cursor < format.endIndex, "@diu".contains(format[cursor]) else {
                output.append(character)
                index = format.index(after: index)
                continue
            }
            let slot: Int
            if let position { slot = position - 1 } else { slot = sequential; sequential += 1 }
            if arguments.indices.contains(slot) { output += render(arguments[slot], locale: locale) }
            index = format.index(after: cursor)
        }
        return output
    }

    public static func render(_ argument: RFTextArgument, locale: Locale) -> String {
        switch argument {
        case .untrusted(let text): RFBidi.isolate(text)
        case .identifier(let text): RFIdentifier.display(text)
        case .localized(let text): text
        case .count(let value): value.formatted(.number.locale(locale))
        }
    }
}
