// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import RFDesign

/// Metrics of the onboarding boards (MOB-S01, S02, S18, N01, A01, A02, A07) that the Kit does not name.
enum OnboardingMetrics {
    /// Wordmark of the start boards (S02, S18) and of the splash (S01).
    static let wordmark: CGFloat = 34
    static let splashWordmark: CGFloat = 28
    /// App mark tile of the splash.
    static let mark: CGFloat = 72
    static let markRadius: CGFloat = 18
    static let markLetter: CGFloat = 38
    /// The signature frame: 160 x 40 on S18, 120 x 30 elsewhere; the stroke is 150 x 30 at (6, 4).
    static let signatureWidth: CGFloat = 160
    static let stroke: CGFloat = 1.6
    static let seal: CGFloat = 10
    /// Vertical rhythm of the start boards.
    static let sectionGap: CGFloat = 16
    static let splashGap: CGFloat = 12
    /// Top of the wordmark below the status bar: 80 pt on S02, 104 pt on S18.
    static let startTop: CGFloat = 80
    static let welcomeTop: CGFloat = 104
    /// Space between the page header and the first content line (header ends at 119, the first line box at 139).
    static let contentTop: CGFloat = 19
    /// The splash group sits 48 pt above the centre of the area below the status bar.
    static let splashLift: CGFloat = 96
    /// The pinned action ends 11 pt above the home indicator band (S02, A01, A02, A07), 8 pt on N01.
    static let footerBottom: CGFloat = 11
    static let createFooterBottom: CGFloat = 8
    /// S18's last (text) action ends 16 pt above the home indicator band.
    static let welcomeFooterBottom: CGFloat = 16
    /// A07 information rows.
    static let infoRow: CGFloat = 76
    static let infoRowPad: CGFloat = 9
    static let selectedCard: CGFloat = 74
    static let infoLine: CGFloat = 44
}

/// The hand-drawn brand signature: a seal dot and one ink stroke (design path, viewBox 4 0 142 30).
struct BrandSignature: View {
    var height: CGFloat = 30
    @Environment(\.rfTheme) private var theme
    var body: some View {
        ZStack(alignment: .topLeading) {
            SignatureStroke()
                .stroke(theme.text, style: StrokeStyle(lineWidth: OnboardingMetrics.stroke, lineCap: .round, lineJoin: .round))
                .frame(width: 150, height: 30).offset(x: 6, y: 4)
            Circle().fill(theme.line_strong).frame(width: OnboardingMetrics.seal, height: OnboardingMetrics.seal).offset(x: 2, y: 17)
        }
        .frame(width: OnboardingMetrics.signatureWidth, height: height, alignment: .topLeading)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}

/// The signature stroke in its 150 x 30 frame.
struct SignatureStroke: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 142, sy = rect.height / 30
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + (x - 4) * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(6, 22))
        path.addCurve(to: p(50, 4), control1: p(22, 22), control2: p(30, 4))
        path.addCurve(to: p(96, 26), control1: p(70, 4), control2: p(76, 28))
        path.addCurve(to: p(136, 8), control1: p(116, 24), control2: p(122, 2))
        path.addCurve(to: p(137, 23), control1: p(146, 12), control2: p(145, 24))
        path.addCurve(to: p(141, 13), control1: p(130, 22), control2: p(132, 12))
        return path
    }
}

/// The app mark of the splash: a dark rounded tile with the brand letter.
struct BrandMark: View {
    var letter: String
    @Environment(\.rfTheme) private var theme
    var body: some View {
        Text(letter).font(.custom(DesignFonts.face(for: theme.font_latin), fixedSize: OnboardingMetrics.markLetter).weight(.bold)).foregroundStyle(theme.on_primary)
            .frame(width: OnboardingMetrics.mark, height: OnboardingMetrics.mark)
            .background(theme.primary, in: RoundedRectangle(cornerRadius: OnboardingMetrics.markRadius))
            .accessibilityHidden(true)
    }
}

/// The Ramflux wordmark in the brand's Latin face (Hanken Grotesk, bold), as on the start boards.
struct BrandWordmark: View {
    var text: String
    var size: CGFloat
    @Environment(\.rfTheme) private var theme
    var body: some View {
        Text(text).font(.custom(DesignFonts.face(for: theme.font_latin), size: size, relativeTo: .largeTitle).weight(.bold))
            .accessibilityAddTraits(.isHeader)
    }
}
