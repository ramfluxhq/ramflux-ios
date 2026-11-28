// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import AppData
@testable import FeatureMlsGroups

struct MlsAdminScreensTests {
    private func row(_ anchor: String, _ role: MlsRole, me: Bool = false) -> MlsMemberRow { MlsMemberRow(anchor: anchor, display: anchor, role: role, isMe: me) }

    @Test func theMemberMenuFollowsTheViewersRoleAndNeverOffersTheOwnerOrOwnRow() {
        typealias A = MlsMemberActions
        #expect(A.entries(for: row("m", .member), viewer: .owner, readOnly: false) == [.makeAdmin, .remove, .ban])
        #expect(A.entries(for: row("a", .admin), viewer: .owner, readOnly: false) == [.makeMember, .remove, .ban])
        #expect(A.entries(for: row("o", .owner), viewer: .owner, readOnly: false).isEmpty)
        #expect(A.entries(for: row("me", .member, me: true), viewer: .owner, readOnly: false).isEmpty)
        #expect(A.entries(for: row("m", .member), viewer: .admin, readOnly: false) == [.remove, .ban])
        #expect(A.entries(for: row("a", .admin), viewer: .admin, readOnly: false).isEmpty)
        #expect(A.entries(for: row("o", .owner), viewer: .admin, readOnly: false).isEmpty)
        #expect(A.entries(for: row("m", .member), viewer: .member, readOnly: false).isEmpty)
        #expect(A.entries(for: row("m", .member), viewer: .owner, readOnly: true).isEmpty)
    }
    @Test func aConfirmationNamesTheMemberAndTheGroupAndNeverTheAnchor() {
        let en = Locale(identifier: "en")
        let named = MlsAdminConfirmation(kind: .remove(anchor: "anchor-secret"), display: "Dana", aiFlag: false, groupName: "Design")
        #expect(named.title(locale: en).contains("Dana") && named.title(locale: en).contains("Design"))
        #expect(!named.title(locale: en).contains("anchor-secret") && !String(describing: named).contains("anchor-secret"))
        let unnamed = MlsAdminConfirmation(kind: .approve(requestID: "rq-secret"), display: nil, aiFlag: true, groupName: "Design")
        #expect(unnamed.title(locale: en).contains("this member") && !unnamed.title(locale: en).contains("rq-secret"))
        #expect(unnamed.aiFlag && !String(describing: unnamed).contains("rq-secret"))
        #expect(FeatureMlsGroupsStrings.text("group.member.agentNote", locale: en) == "This member is an agent.")
    }
    @Test func removeBanAndApprovalOffAreTheDestructiveConfirmations() {
        func destructive(_ kind: MlsAdminConfirmation.Kind) -> Bool { MlsAdminConfirmation(kind: kind, groupName: "G").destructive }
        #expect(destructive(.remove(anchor: "a")) && destructive(.ban(anchor: "a")) && destructive(.approvalOff))
        #expect(!destructive(.approve(requestID: "r")) && !destructive(.decline(requestID: "r")) && !destructive(.makeAdmin(anchor: "a")) && !destructive(.makeMember(anchor: "a")))
    }
    @Test func theDeclineBodyNamesTheExpiryAndTheBanBodySaysTheyCannotRejoin() {
        let en = Locale(identifier: "en")
        #expect(MlsAdminConfirmation(kind: .decline(requestID: "r"), display: "Chen", groupName: "G", expiresAt: 1_767_258_000_000).body(locale: en).hasPrefix("They won't be notified."))
        #expect(MlsAdminConfirmation(kind: .ban(anchor: "a"), groupName: "G").body(locale: en) == "They're removed and can't join again, even with an invite.")
    }
    @Test func everyM3KeyOfThePackageResolvesInEnglishAndChinese() {
        let keys = ["group.requests.title", "group.requests.approveConfirm.title", "group.requests.declineConfirm.body", "group.requests.approvalOff", "group.member.action.makeAdmin", "group.member.banConfirm.body", "group.settings.approvalOffConfirm.body", "group.push.title", "group.push.failed", "group.join.pending.onlineNote", "group.member.menu"]
        for key in keys {
            let en = FeatureMlsGroupsStrings.text(key, locale: Locale(identifier: "en")), zh = FeatureMlsGroupsStrings.text(key, locale: Locale(identifier: "zh-CN"))
            #expect(en != key && zh != key && en != zh)
        }
        #expect(FeatureMlsGroupsStrings.format("group.requests.entry", 1, locale: Locale(identifier: "en")) == "1 join request")
        #expect(FeatureMlsGroupsStrings.format("group.requests.entry", 7, locale: Locale(identifier: "en")) == "7 join requests")
        #expect(FeatureMlsGroupsStrings.format("group.requests.entryMore", 200, locale: Locale(identifier: "en")) == "More than 200 join requests")
    }
    @Test func aRowIdentifierIsTheIndexInProductionAndTheFixtureIdInTheGallery() {
        #if RAMFLUX_MLS_GALLERY
        #expect(mlsRowTag("mls-request-approve-", index: 2, fixtureID: "rq-ana") == "mls-request-approve-rq-ana")
        #else
        #expect(mlsRowTag("mls-request-approve-", index: 2, fixtureID: "rq-ana") == "mls-request-approve-2")
        #endif
    }
}

#if RAMFLUX_MLS_GALLERY
import FeatureChat
/// The chat model on the gallery fixture (Debug only): A3, the skip dialog is the only path to `skip: true`, and A1 for void.
struct MlsChatModelAdminTests {
    @MainActor private func wait(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
    }
    @Test @MainActor func skipIsSentOnlyByTheDialogsConfirmAndNeverByCancelOrWithoutTheDialog() async throws {
        let fixture = try #require(MlsGroupFixtures.admin.first { $0.id == "F3-12" })
        let repository = FixtureMlsGroupRepository(fixture)
        let session = MlsGroupSession(account: "gallery", repository: repository)
        let model = MlsGroupChatModel(session: session, groupID: "g-bookclub", title: "Book club", openInfo: {})
        model.send(.appeared)
        await wait { model.state.mls?.catchUp != nil }
        #expect(model.state.mls?.catchUp != nil)
        model.send(.mlsConfirmSkip)                                   // no dialog: nothing
        model.send(.mlsSkipCatchUp); #expect(model.state.mls?.skipDialog == true)
        model.send(.mlsCancelSkip); #expect(model.state.mls?.skipDialog == false)
        model.send(.mlsConfirmSkip)                                   // the dialog is closed again: nothing
        try? await Task.sleep(for: .milliseconds(200))
        #expect(repository.count("group.catch_up") == 0)
        model.send(.mlsSkipCatchUp); model.send(.mlsConfirmSkip)
        await wait { repository.count("group.catch_up") == 1 }
        #expect(repository.count("group.catch_up") == 1)
        model.send(.disappeared)
    }
    @Test @MainActor func undoIsSentOnlyByItsConfirmation() async throws {
        let fixture = try #require(MlsGroupFixtures.admin.first { $0.id == "F3-10" })
        let repository = FixtureMlsGroupRepository(fixture)
        let session = MlsGroupSession(account: "gallery", repository: repository)
        let model = MlsGroupChatModel(session: session, groupID: "g-design", title: "Design", openInfo: {})
        model.send(.appeared)
        await wait { !(model.state.mls?.entries.isEmpty ?? true) }
        model.send(.mlsConfirmVoid)                                   // nothing is waiting for a confirmation
        model.send(.mlsVoid(250)); #expect(model.state.mls?.voidTarget == 250)
        model.send(.mlsCancelVoid)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(repository.count("group.void") == 0)
        model.send(.mlsVoid(250)); model.send(.mlsConfirmVoid)
        await wait { repository.count("group.void") == 1 }
        #expect(repository.count("group.void") == 1)
        model.send(.disappeared)
    }
}
#endif
