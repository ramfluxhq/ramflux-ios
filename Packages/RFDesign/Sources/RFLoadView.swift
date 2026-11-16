// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

struct RFStatusNote: View {
    @Environment(\.rfTheme) private var theme
    let title: String
    let message: String
    let icon: String
    var tint: Color?
    var body: some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            KitStatusHero(icon: icon, tint: tint)
            Text(title).font(theme.bodyFont.weight(.semibold))
            if !message.isEmpty { Text(message).font(theme.captionFont).foregroundStyle(theme.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

public struct RFFailureView: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let title: String
    public let message: String
    public let retry: (() -> Void)?
    public init(title: String, message: String, retry: (() -> Void)? = nil) {
        self.title = title; self.message = message; self.retry = retry
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            RFStatusNote(title: title, message: message, icon: "circle-alert", tint: theme.danger)
            if let retry {
                KitButton(RFDesignStrings.text("copy.d8b8392e2c54", locale: locale), action: retry, kind: .secondary, tag: "failure-retry")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

public struct RFLoadingView: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public init() {}
    public var body: some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            ProgressView().accessibilityLabel(RFDesignStrings.text("copy.dc380888c4e2", locale: locale))
            Text(RFDesignStrings.text("copy.dc380888c4e2", locale: locale)).font(theme.bodyFont.weight(.semibold))
            Text(RFDesignStrings.text("copy.c771af79a1fe", locale: locale)).font(theme.captionFont).foregroundStyle(theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
