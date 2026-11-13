// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
public struct NamedTheme: Identifiable, Sendable {
    public let id: String
    public let labelKey: String
    public let isDark: Bool
    public let tokens: RFTheme
    public let increasedContrast: RFTheme
}
