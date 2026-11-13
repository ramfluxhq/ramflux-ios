// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData

public enum AppShellPreviews {
    public static let cases: [AppShellPreview] = [
        AppShellPreview(id: "locked", state: AppShellState()),
        AppShellPreview(id: "opening", state: AppShellState(session: SessionSnapshot(phase: .opening), privacyShield: false, busy: true)),
        AppShellPreview(id: "unavailable", state: AppShellState(session: SessionSnapshot(phase: .unavailable(.nativeCoreMissing)), privacyShield: false)),
        AppShellPreview(id: "offline", state: AppShellState(session: SessionSnapshot(phase: .failed(.offline)), privacyShield: false)),
        AppShellPreview(id: "empty", state: AppShellState(session: SessionSnapshot(phase: .ready), privacyShield: false)),
        AppShellPreview(id: "accounts", state: AppShellState(session: SessionSnapshot(phase: .ready, accounts: [
            AccountRecord(id: "preview-account", displayName: "Preview account", isLocked: false),
        ], activeAccountID: "preview-account"), privacyShield: false)),
    ]
    @MainActor public static func screen(_ item: AppShellPreview) -> some View { AppShellScreen(state: item.state, onAction: { _ in }) }
}
#Preview("Shell states") {
    ScrollView { LazyVStack { ForEach(AppShellPreviews.cases) { item in
        VStack { Text(item.id); AppShellPreviews.screen(item).frame(width: 390, height: 844) }
    } } }
}
