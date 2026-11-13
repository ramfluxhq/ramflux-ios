// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

public extension RFTheme {
    static func adaptive(_ scheme: ColorScheme) -> Self { scheme == .dark ? .dark : .light }
    var bodyFont: Font { .custom(font, size: size_mobile_body, relativeTo: .body) }
    var captionFont: Font { .custom(font, size: size_mobile_caption, relativeTo: .caption) }
    var pageFont: Font { .custom(font, size: size_page, relativeTo: .title) }
}
public struct RFPage<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        let theme = RFTheme.adaptive(colorScheme)
        ZStack { theme.bg.ignoresSafeArea(); content }
            .font(theme.bodyFont).foregroundStyle(theme.text).tint(theme.primary)
    }
}
public struct RFUnavailableView: View {
    @Environment(\.colorScheme) private var colorScheme
    public let title: String
    public let message: String
    public init(title: String, message: String) { self.title = title; self.message = message }
    public var body: some View {
        let theme = RFTheme.adaptive(colorScheme)
        RFPage {
            RFStateBlock(title: title, description: message, kind: .empty, theme: theme) { EmptyView() }
                .frame(maxWidth: theme.column_max)
        }
    }
}
