// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public enum AppDataFactory {
    /// Source-only builds explicitly refuse account operations. No fixture is linked into the app.
    public static func sessionRepository() -> any SessionRepository { repositories().session }
    public static func repositories() -> AppRepositories {
        #if RF_NATIVE_SDK
        do {
            guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return unavailable() }
            let root = support.appendingPathComponent("ramflux", isDirectory: true)
            let client = RamfluxClient(transport: try NativeCore(dataRoot: root, custody: HostCustodyProvider()))
            let updates = NativeUpdateSource(client: client)
            let nodes = NativeNodeRepository(client: client)
            return AppRepositories(session: NativeSessionRepository(client: client, dataRoot: root), nodes: nodes, onboarding: NativeOnboardingRepository(client: client), conversations: NativeConversationsRepository(client: client, updates: updates), chat: NativeChatRepository(client: client, updates: updates), contacts: NativeContactsRepository(client: client, updates: updates), settings: NativeSettingsRepository(client: client, nodes: nodes, updates: updates), backup: NativeBackupRepository(client: client, directory: root.appendingPathComponent("backups", isDirectory: true)), groups: NativeGroupsRepository(client: client, updates: updates))
        } catch { return unavailable() }
        #else
        return unavailable()
        #endif
    }
    private static func unavailable() -> AppRepositories {
        AppRepositories(session: UnavailableSessionRepository(), nodes: UnavailableNodeRepository(), onboarding: UnavailableOnboardingRepository())
    }
}
