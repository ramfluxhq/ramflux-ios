// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import SwiftUI
import RFLocalization

/// Message text drawn by the system text stack: selectable, with detected links, read by
/// VoiceOver like any text, and measured by the system.
///
/// The base direction comes from the content (`RFBidi.contentDirection`), not the UI language:
/// an Arabic message reads and aligns right to left in an English UI and an English message
/// left to right in an Arabic UI. Text with no strong character keeps the surrounding direction.
/// Directional overrides, embeddings and isolates in the message are removed first. This view,
/// `KitIdentifierText` and `KitFileName` are the only Kit views that set a layout direction.
public struct KitMessageText: View {
    var text: String
    var size: CGFloat?
    var color: Color?
    var lines: Int?
    var fillsWidth: Bool
    @Environment(\.rfTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection

    /// - Parameter fillsWidth: true fills the offered width (bubble body); false hugs the text
    ///   (reply excerpts). Either way the text aligns by its own direction.
    public init(_ text: String, size: CGFloat? = nil, color: Color? = nil, lines: Int? = nil, fillsWidth: Bool = true) {
        self.text = text
        self.size = size
        self.color = color
        self.lines = lines
        self.fillsWidth = fillsWidth
    }

    public var body: some View {
        let clean = RFUntrustedText(text, kind: .messageBody).text
        let points = kitScaledSize(size ?? theme.size_mobile_body, typeSize)
        let face = KitTypeface.face(for: .ui, text: clean, locale: locale)
        let ink = color ?? theme.text
        Text(Self.linked(clean))
            .font(kitFont(size: points, weight: kitWeight(.regular), face: face))
            .foregroundStyle(ink)
            .tint(ink)
            .modifier(KitLineHeight(size: points, weight: .regular, line: KitMetrics.lineBubble, face: face))
            .lineLimit(lines)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
            .environment(\.layoutDirection, Self.direction(of: clean, surrounding: layoutDirection))
    }

    /// The direction the message is laid out in.
    nonisolated public static func direction(of text: String, surrounding: LayoutDirection) -> LayoutDirection {
        RFBidi.contentDirection(of: RFUntrustedText(text, kind: .messageBody).text) ?? surrounding
    }

    /// Detected web links become underlined link runs.
    nonisolated static func linked(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return attributed }
        let whole = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in detector.matches(in: text, options: [], range: whole) {
            guard let url = match.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let range = Range(match.range, in: text), let span = Range(range, in: attributed) else { continue }
            attributed[span].link = url
            attributed[span].underlineStyle = .single
        }
        return attributed
    }
}

/// Bubble width: hugs content that fits on one line, and fills the cap when it wraps.
///
/// The cap is the explicit width when one is given, otherwise the smaller of the bubble token
/// maximum and a fraction of the width the container offers, so a 320 pt screen, a 360 pt column
/// and a wide detail column all get a proportionate bubble.
struct KitBubbleWidth: Layout {
    var fixed: CGFloat?
    var token: CGFloat
    var fraction: CGFloat

    func cap(_ proposal: ProposedViewSize) -> CGFloat {
        let offered = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        if let fixed { return min(fixed, offered ?? fixed) }
        guard let offered else { return token }
        return min(token, offered * fraction)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let limit = cap(proposal)
        let ideal = content.sizeThatFits(.unspecified)
        if ideal.width <= limit { return ideal }
        let wrapped = content.sizeThatFits(ProposedViewSize(width: limit, height: nil))
        return CGSize(width: limit, height: wrapped.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
