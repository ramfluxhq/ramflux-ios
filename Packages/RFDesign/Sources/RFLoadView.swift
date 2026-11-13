// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

public struct RFFailureView: View {
    @Environment(\.colorScheme) private var scheme
    public let title: String
    public let message: String
    public let retry: (() -> Void)?
    public init(title: String, message: String, retry: (() -> Void)? = nil) {
        self.title = title; self.message = message; self.retry = retry
    }
    public var body: some View {
        let theme = RFTheme.adaptive(scheme)
        RFStateBlock(title: title, description: message, kind: .error, theme: theme) {
            if let retry { Button("Try again", action: retry).buttonStyle(.bordered) }
        }.accessibilityElement(children: .contain)
    }
}
public struct RFLoadingView: View {
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public var body: some View {
        RFStateBlock(title: "Loading", description: "Reading your local records", kind: .loading,
                     theme: RFTheme.adaptive(scheme)) { EmptyView() }
    }
}
