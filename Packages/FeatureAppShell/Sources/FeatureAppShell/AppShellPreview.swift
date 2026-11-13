// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData

public struct AppShellPreview: Identifiable, Sendable {
    public let id: String
    public let state: AppShellState
}
/// Explicit presentation fixtures; never used to construct the application repository.
