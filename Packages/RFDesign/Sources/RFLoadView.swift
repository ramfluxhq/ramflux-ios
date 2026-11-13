// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

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
        RFStateBlock(title: title, description: message, kind: .error, theme: theme) {
            if let retry { Button(RFDesignStrings.text("copy.d8b8392e2c54", locale: locale), action: retry).buttonStyle(.bordered) }
        }.accessibilityElement(children: .contain)
    }
}
public struct RFLoadingView: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public init() {}
    public var body: some View {
        RFStateBlock(title: RFDesignStrings.text("copy.dc380888c4e2", locale: locale), description: RFDesignStrings.text("copy.c771af79a1fe", locale: locale), kind: .loading,
                     theme: theme) { EmptyView() }
    }
}
