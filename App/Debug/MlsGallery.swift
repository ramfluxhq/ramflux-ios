// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if RAMFLUX_MLS_GALLERY
import SwiftUI
import AppData
import FeatureChat
import FeatureContacts
import FeatureConversations
import RFDesign

/// Debug-only MLS gallery (MLS-GUI M1): every direct-chat identity fixture F1-1 to F1-11 opens the real chat, chat
/// details, contact profile and conversation list on fixture repositories (AppData/Gallery). A scoped exception to
/// docs/bridge.md like the card gallery: compiled only with `RAMFLUX_MLS_GALLERY` (Debug), reached by the launch
/// argument `-RamfluxMlsGallery 1` or Settings > About, and removed once the pin batch is verified on the real SDK.
/// The titles are developer text and stay literal, like "Card gallery".
enum MlsGalleryLaunch {
    static var enabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-RamfluxMlsGallery"), arguments.indices.contains(index + 1) else { return false }
        return arguments[index + 1] == "1"
    }
}

struct MlsGalleryRoot: View {
    let appearance: AppearanceMode
    var body: some View { RFThemeScope(selection: appearance.rawValue) { MlsGalleryView() } }
}

struct MlsGalleryView: View {
    var body: some View {
        NavigationStack {
            List(MlsFixtures.all) { fixture in
                NavigationLink { MlsFixtureMenu(fixture: fixture) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: fixture.id + "  " + fixture.heading)
                        Text(verbatim: fixture.expected).font(.caption).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("mls-fixture-" + fixture.id)
            }
            .accessibilityIdentifier("mls-gallery")
            .navigationTitle(Text(verbatim: "MLS gallery"))
        }
    }
}

/// The screens one fixture can open. Each opens fresh fixture repositories, so its script starts again.
private struct MlsFixtureMenu: View {
    let fixture: MlsFixture
    var body: some View {
        List {
            NavigationLink { MlsChatScreen(fixture: fixture, openDetails: false) } label: { Text(verbatim: "Chat") }.accessibilityIdentifier("mls-open-chat")
            NavigationLink { MlsChatScreen(fixture: fixture, openDetails: true) } label: { Text(verbatim: "Chat details") }.accessibilityIdentifier("mls-open-details")
            NavigationLink { MlsContactScreen(fixture: fixture) } label: { Text(verbatim: "Contact profile") }.accessibilityIdentifier("mls-open-contact")
            NavigationLink { MlsConversationListScreen(fixture: fixture) } label: { Text(verbatim: "Conversation list") }.accessibilityIdentifier("mls-open-list")
        }
        .navigationTitle(Text(verbatim: fixture.id + "  " + fixture.name))
    }
}

/// Developer footer: the fixture and the number of `conversation.security` reads (the F1-9 silent re-read check).
private struct MlsFooter: View {
    let repositories: MlsFixtureRepositories
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            Text(verbatim: repositories.fixture.id + " reads " + String(repositories.identity.securityReads))
                .font(.caption2).padding(4).background(.thinMaterial, in: Capsule())
                .accessibilityIdentifier("mls-read-count")
        }
        .padding(.top, 2).padding(.trailing, 8).allowsHitTesting(false)
    }
}

private struct MlsChatScreen: View {
    let openDetails: Bool
    @State private var repositories: MlsFixtureRepositories
    @State private var coordinator: ChatCoordinator
    init(fixture: MlsFixture, openDetails: Bool) {
        self.openDetails = openDetails
        let repositories = MlsFixtureRepositories(fixture)
        _repositories = State(initialValue: repositories)
        _coordinator = State(initialValue: ChatCoordinator(repository: repositories.chat, identity: repositories.identity, peerContact: fixture.contact, account: MlsFixtureRepositories.account, conversation: repositories.conversationID, title: fixture.name, peerIsAgent: fixture.aiFlag))
    }
    var body: some View {
        ChatHost(coordinator: coordinator)
            .overlay(alignment: .topTrailing) { MlsFooter(repositories: repositories) }
            .task { if openDetails { try? await Task.sleep(for: .milliseconds(400)); coordinator.send(.detailsRequested) } }
    }
}

private struct MlsContactScreen: View {
    @State private var repositories: MlsFixtureRepositories
    @State private var coordinator: ContactsCoordinator
    init(fixture: MlsFixture) {
        let repositories = MlsFixtureRepositories(fixture)
        _repositories = State(initialValue: repositories)
        _coordinator = State(initialValue: ContactsCoordinator(repository: repositories.contacts, identity: repositories.identity, account: MlsFixtureRepositories.account, mode: .profile(fixture.contact), navigate: { _ in }))
    }
    var body: some View { ContactsHost(coordinator: coordinator).overlay(alignment: .bottomTrailing) { MlsFooter(repositories: repositories) } }
}

private struct MlsConversationListScreen: View {
    @State private var repositories: MlsFixtureRepositories
    @State private var coordinator: ConversationsCoordinator
    init(fixture: MlsFixture) {
        let repositories = MlsFixtureRepositories(fixture)
        _repositories = State(initialValue: repositories)
        _coordinator = State(initialValue: ConversationsCoordinator(repository: repositories.conversations, identity: repositories.identity, account: MlsFixtureRepositories.account, accountTitle: "Gallery", navigate: { _ in }))
    }
    var body: some View { ConversationsHost(coordinator: coordinator).overlay(alignment: .bottomTrailing) { MlsFooter(repositories: repositories) } }
}
#endif
