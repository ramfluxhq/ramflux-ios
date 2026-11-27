// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
import Push
public enum AppDataFactory {
    /// Source-only builds explicitly refuse account operations. No fixture is linked into the app.
    public static func sessionRepository() -> any SessionRepository { repositories().session }
    public static func repositories() -> AppRepositories {
        #if RF_NATIVE_SDK
        do {
            // The SDK data root is shared with the notification extension: `ramflux/` in the App Group container.
            guard let shared = SharedContainer.containerURL() else { return unavailable() }
            let root = shared.appendingPathComponent("ramflux", isDirectory: true)
            let client = RamfluxClient(transport: try NativeCore(dataRoot: root, custody: HostCustodyProvider(), usernameDirectory: AppOpenConfiguration.usernameDirectory(info: Bundle.main.infoDictionary), diagnostics: AppOpenConfiguration.diagnostics))
            let updates = NativeUpdateSource(client: client)
            let cardSessions = CardSessionRegistry(client: client)
            let nodes = NativeNodeRepository(client: client), lifecycle = AccountLifecycleHooks()
            // Sign-out and removal dispose the account's card sessions before the SDK closes the account.
            lifecycle.register { event in if case .willLeave(let account) = event { await cardSessions.disposeAccount(account) } }
            let contacts = NativeContactsRepository(client: client, updates: updates)
            return AppRepositories(session: NativeSessionRepository(client: client, dataRoot: root, updates: updates, cards: cardSessions), nodes: nodes, onboarding: NativeOnboardingRepository(client: client), conversations: NativeConversationsRepository(client: client, updates: updates, contacts: contacts), chat: NativeChatRepository(client: client, updates: updates, transients: UpdateSourceChatTransients(updates: updates)), contacts: contacts, settings: NativeSettingsRepository(client: client, nodes: nodes, updates: updates, lifecycle: lifecycle), backup: NativeBackupRepository(client: client, directory: root.appendingPathComponent("backups", isDirectory: true), updates: updates), pairing: NativePairingRepository(client: client), groups: NativeGroupsRepository(client: client, updates: updates, contacts: contacts), calls: NativeCallsRepository(client: client, updates: updates), agents: NativeAgentsRepository(client: client, updates: updates), tasks: NativeTasksRepository(client: client, updates: updates), cards: NativeCardsRepository(client: client, updates: updates, registry: cardSessions), lifecycle: lifecycle, pushRoutes: NativePushRouteRepository(client: client))
        } catch { return unavailable() }
        #else
        return unavailable()
        #endif
    }
    private static func unavailable() -> AppRepositories {
        AppRepositories(session: UnavailableSessionRepository(), nodes: UnavailableNodeRepository(), onboarding: UnavailableOnboardingRepository())
    }
}
