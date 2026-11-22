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
            Text(title).rfFont(.body, weight: .semibold)
            if !message.isEmpty { Text(message).rfFont(.caption).foregroundStyle(theme.secondary) }
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
                KitButton(RFDesignStrings.text("kit.load.retry", locale: locale), action: retry, kind: .secondary, tag: "failure-retry")
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
            ProgressView().accessibilityLabel(RFDesignStrings.text("kit.load.loading", locale: locale))
            Text(RFDesignStrings.text("kit.load.loading", locale: locale)).rfFont(.body, weight: .semibold)
            Text(RFDesignStrings.text("kit.load.readingRecords", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
