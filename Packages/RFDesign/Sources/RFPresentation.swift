// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

public extension RFTheme {
    static var light: Self { RFDesign.light.registeredTheme }
    static var dark: Self { RFDesign.dark.registeredTheme }
    static func adaptive(_ scheme: ColorScheme) -> Self { scheme == .dark ? .dark : .light }
}

/// Text roles for screen text outside Kit components.
public enum RFTextRole: Equatable, Sendable {
    case body, caption, page
    /// Another design token size; Dynamic Type scaling follows the nearest text style.
    case size(CGFloat)
    /// Text inside a fixed shape (an avatar initial): the design size, not scaled.
    case fixed(CGFloat)
}

public extension View {
    /// The UI font for a role in the active locale: the bundled face for Latin and Simplified
    /// Chinese locales, the system font (with its own line metrics and the locale's Han forms)
    /// for every other script. Both follow Dynamic Type from the token size. This is the only
    /// way screen text outside the Kit chooses a font.
    func rfFont(_ role: RFTextRole, weight: Font.Weight = .regular) -> some View { modifier(RFFontModifier(role: role, weight: weight)) }
}

private struct RFFontModifier: ViewModifier {
    var role: RFTextRole
    var weight: Font.Weight
    @Environment(\.rfTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        let (size, style, scales): (CGFloat, Font.TextStyle, Bool) = switch role {
        case .body: (theme.size_mobile_body, .body, true)
        case .caption: (theme.size_mobile_caption, .caption, true)
        case .page: (theme.size_page, .title, true)
        case .size(let value): (value, Self.nearestStyle(value), true)
        case .fixed(let value): (value, .body, false)
        }
        let bundled = KitTypeface.face(for: .ui, locale: locale).isBundled
        let font: Font = switch (bundled, scales) {
        case (true, true): .custom(theme.font, size: size, relativeTo: style)
        case (true, false): .custom(theme.font, fixedSize: size)
        case (false, true): .system(size: kitScaledSize(size, typeSize))
        case (false, false): .system(size: size)
        }
        content.font(weight == .regular ? font : font.weight(weight))
    }

    private static func nearestStyle(_ size: CGFloat) -> Font.TextStyle {
        switch size {
        case 34...: .largeTitle
        case 28..<34: .title
        case 22..<28: .title2
        case 20..<22: .title3
        case 17..<20: .body
        case 16..<17: .callout
        case 15..<16: .subheadline
        case 13..<15: .footnote
        case 12..<13: .caption
        default: .caption2
        }
    }
}
public struct RFPage<Content: View>: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        ZStack { theme.bg.ignoresSafeArea(); content }
            .rfFont(.body).foregroundStyle(theme.text).tint(theme.primary)
    }
}
public struct RFUnavailableView: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let title: String
    public let message: String
    public init(title: String, message: String) { self.title = title; self.message = message }
    public var body: some View {
        RFPage {
            RFStatusNote(title: title, message: message, icon: "messages-square")
                .frame(maxWidth: theme.column_max)
        }
    }
}

public extension View {
    @ViewBuilder func rfHidesNavigationBar() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
    @ViewBuilder func rfAddressInput() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
        #else
        self.autocorrectionDisabled()
        #endif
    }
}

public extension EnvironmentValues {
    @Entry var rfLoadsOnAppear = true
}
