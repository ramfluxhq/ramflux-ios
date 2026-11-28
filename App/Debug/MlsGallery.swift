// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if RAMFLUX_MLS_GALLERY
import SwiftUI
import AppData
import FeatureChat
import FeatureContacts
import FeatureMlsGroups
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
    /// The groups module owns a NavigationStack. Pushed inside the gallery stack it would be nested, and SwiftUI ignores
    /// its second-level pushes (chat to group info), so the group fixtures open as full-screen covers.
    @State private var groupFixture: MlsGroupFixture?
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(verbatim: "Identity (M1)")) {
                    ForEach(MlsFixtures.all) { fixture in
                        NavigationLink { MlsFixtureMenu(fixture: fixture) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: fixture.id + "  " + fixture.heading)
                                Text(verbatim: fixture.expected).font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("mls-fixture-" + fixture.id)
                    }
                }
                Section(header: Text(verbatim: "Groups (M2)")) {
                    ForEach(MlsGroupFixtures.all) { fixture in
                        Button { groupFixture = fixture } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: fixture.id + "  " + fixture.heading)
                                Text(verbatim: fixture.expected).font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("mls-fixture-" + fixture.id)
                    }
                }
                Section(header: Text(verbatim: "Admin (M3)")) {
                    ForEach(MlsGroupFixtures.admin) { fixture in
                        Button { groupFixture = fixture } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: fixture.id + "  " + fixture.heading)
                                Text(verbatim: fixture.expected).font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("mls-fixture-" + fixture.id)
                    }
                }
            }
            .accessibilityIdentifier("mls-gallery")
            .navigationTitle(Text(verbatim: "MLS gallery"))
        }
        .fullScreenCover(item: $groupFixture) { fixture in MlsGroupFixtureScreen(fixture: fixture, close: { groupFixture = nil }) }
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

/// A groups fixture (F2-1 to F2-11, F3-1 to F3-14): the real MLS groups module over a real `MlsGroupSession` bound to the
/// fixture repository. F2-11 binds the native repository instead, which answers every call with the typed unavailable
/// outcome; F3-14 binds the native repository for every M3 method (the M2 reads still come from the fixture so the screens
/// can be opened). The F3 fixtures have Lock now and Unlock buttons that call `clear()` and `admit()` of the session the
/// way `AppComposition` does on a lock and an unlock.
private struct MlsGroupFixtureScreen: View {
    let fixture: MlsGroupFixture
    let close: () -> Void
    private let repository: FixtureMlsGroupRepository?
    private let session: MlsGroupSession
    @State private var model: MlsGroupsCoordinator
    @State private var showCalls = false
    init(fixture: MlsGroupFixture, close: @escaping () -> Void) {
        self.fixture = fixture
        self.close = close
        let fake: FixtureMlsGroupRepository? = fixture.id == "F2-11" ? nil : FixtureMlsGroupRepository(fixture)
        repository = fake
        let source: any MlsGroupRepository = fake ?? NativeMlsGroupRepository()
        let defaults = UserDefaults(suiteName: "ramflux.mls.gallery") ?? .standard
        defaults.removePersistentDomain(forName: "ramflux.mls.gallery")
        let session = MlsGroupSession(account: FixtureMlsGroupRepository.account, repository: source)
        self.session = session
        _model = State(initialValue: MlsGroupsCoordinator(session: session, account: FixtureMlsGroupRepository.account, defaults: defaults))
    }
    var body: some View {
        MlsGroupsHost(model: model)
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                HStack(spacing: 6) {
                    Button { close() } label: { Text(verbatim: "Close").font(.caption2).padding(4).background(.thinMaterial, in: Capsule()) }.accessibilityIdentifier("mls-gallery-close")
                    if fixture.id.hasPrefix("F3-") {
                        Button { lock() } label: { Text(verbatim: "Lock now").font(.caption2).padding(4).background(.thinMaterial, in: Capsule()) }.accessibilityIdentifier("mls-lock")
                        Button { unlock() } label: { Text(verbatim: "Unlock").font(.caption2).padding(4).background(.thinMaterial, in: Capsule()) }.accessibilityIdentifier("mls-unlock")
                    }
                    Button { showCalls = true } label: { Text(verbatim: "Calls").font(.caption2).padding(4).background(.thinMaterial, in: Capsule()) }.accessibilityIdentifier("mls-calls-open")
                }.padding(.vertical, 2).padding(.trailing, 8)
            }
            .sheet(isPresented: $showCalls) { MlsCallsView(fixture: fixture, repository: repository) }
    }
    /// The same order as `AppComposition` on `.willLock`: the module stops and forgets its models, then the session clears.
    private func lock() { Task { model.stop(); model.reset(); await session.clear() } }
    /// As after an unlock: the session accepts writes and restarts its event consumer; the module reads the list again.
    private func unlock() { Task { await session.admit(); model.start() } }
}

/// The per-method call counters of the fake (`mls-calls-<method>`): what the runner checks for "no call" and "one call".
private struct MlsCallsView: View {
    let fixture: MlsGroupFixture
    let repository: FixtureMlsGroupRepository?
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                List {
                    Section(header: Text(verbatim: fixture.id + "  " + fixture.hint)) {
                        ForEach(MlsCallCounts.methods, id: \.self) { method in
                            HStack { Text(verbatim: method); Spacer(); Text(verbatim: String(repository?.count(method) ?? 0)) }
                                .accessibilityElement(children: .combine).accessibilityIdentifier("mls-calls-" + method)
                        }
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Calls"))
        }
    }
}
#endif
