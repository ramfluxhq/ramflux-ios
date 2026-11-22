// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

public enum KitIdentifierStyle: Sendable {
    /// Body-size monospaced text: safety numbers, fingerprints, device ids, recovery words.
    case body
    /// The large pairing or account code.
    case code
}

/// The only way a compared identifier reaches the screen.
///
/// The identifier is shown left to right with Western digits in every locale: digits are
/// normalised to ASCII, directional controls are removed, the text is wrapped in LRI ... PDI
/// and laid out left to right, so space-separated groups never swap places under a
/// right-to-left layout. It wraps and never truncates. VoiceOver spells it character by
/// character. Pass the identifier pre-formatted by the data layer; never format it with a
/// locale.
public struct KitIdentifierText: View {
    var value: String
    var style: KitIdentifierStyle
    var color: Color?
    var tag: String?
    @Environment(\.rfTheme) private var theme

    public init(_ identifier: String, style: KitIdentifierStyle = .body, color: Color? = nil, tag: String? = nil) {
        self.value = identifier
        self.style = style
        self.color = color
        self.tag = tag
    }

    /// Recovery words in their written order.
    public init(words: [String], style: KitIdentifierStyle = .body, color: Color? = nil, tag: String? = nil) {
        self.init(words.joined(separator: " "), style: style, color: color, tag: tag)
    }

    public var body: some View {
        let shown = RFIdentifier.display(value)
        Group {
            switch style {
            case .body:
                KitLabel(shown, size: theme.size_body, weight: .regular, color: color ?? theme.text, line: KitMetrics.lineBody, role: .mono, lines: nil)
            case .code:
                KitLabel(shown, size: KitMetrics.pairingSize, weight: .semibold, color: color ?? theme.text, line: KitMetrics.lineTitle, role: .mono, tracking: KitMetrics.pairingTrack, lines: nil)
            }
        }
        .multilineTextAlignment(.leading)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: RFIdentifier.normalizedDigits(RFUntrustedText(value, kind: .identity).text)).speechSpellsOutCharacters())
        .kitTag(tag)
    }
}

/// An untrusted file name whose extension stays visible and cannot be disguised.
///
/// Directional controls are removed, the stem truncates in the middle, and the extension is a
/// separate left-to-right label that never truncates. The row runs in the stem's own direction,
/// so a Latin name reads "report.pdf" in a right-to-left UI and an Arabic name keeps the dot
/// between stem and extension in either UI direction.
public struct KitFileName: View {
    var name: RFFileName
    var size: CGFloat?
    var weight: Font.Weight
    var color: Color?
    @Environment(\.rfTheme) private var theme
    @Environment(\.layoutDirection) private var layoutDirection

    public init(_ raw: String, size: CGFloat? = nil, weight: Font.Weight = .medium, color: Color? = nil) {
        self.name = RFFileName(raw)
        self.size = size
        self.weight = weight
        self.color = color
    }

    public var body: some View {
        let points = size ?? theme.size_body
        let ink = color ?? theme.text
        HStack(spacing: 0) {
            KitLabel(name.stem, size: points, weight: weight, color: ink, line: KitMetrics.lineBody)
                .truncationMode(.middle)
            if let ext = name.fileExtension {
                KitLabel(".", size: points, weight: weight, color: ink, line: KitMetrics.lineBody)
                    .fixedSize()
                KitLabel(RFBidi.isolateLeftToRight(ext), size: points, weight: weight, color: ink, line: KitMetrics.lineBody)
                    .fixedSize()
                    .layoutPriority(1)
            }
        }
        .environment(\.layoutDirection, RFBidi.contentDirection(of: name.stem) ?? layoutDirection)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name.fileExtension.map { name.stem + "." + $0 } ?? name.stem))
    }
}
