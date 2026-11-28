// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import AppData
@testable import FeatureChat

struct MlsChatM3Tests {
    private let en = Locale(identifier: "en"), zh = Locale(identifier: "zh-CN")

    @Test func theSkipDialogBodyIsTheFixedSentenceInEnglishAndTheAgreedChinese() {
        #expect(FeatureChatStrings.text("group.skip.body", locale: en) == "Messages in the skipped range can never be read on this device.")
        #expect(FeatureChatStrings.text("group.skip.body", locale: zh) == "被跳过范围内的消息永远无法在此设备上阅读。")
        #expect(FeatureChatStrings.text("group.skip.cancel", locale: en) == "Keep catching up")
        #expect(FeatureChatStrings.text("group.skip.confirm", locale: en) == "Skip")
    }
    @Test func everyWarningCodeHasItsOwnTextAndAnUnknownCodeShowsTheGenericOne() {
        let codes: [MlsWarningCode] = [.forkAlarm(headN: 2), .rejoinNeeded(.pruned), .undecryptable(count: 12, fromLogSeq: 140), .admissionNeedsOnline, .hostUnusual(.lateRoll), .headCommitRejected(logSeq: 250)]
        let texts = codes.map { MlsChatText.warning($0, locale: en) }
        #expect(Set(texts).count == codes.count && texts.allSatisfy { !$0.hasPrefix("group.") })
        #expect(MlsChatText.warning(.unknown("weird"), locale: en) == "This group reported a problem.")
        #expect(MlsChatText.warning(.hostUnusual(.unknown("x")), locale: en) == MlsChatText.warning(.hostUnusual(.lateReply), locale: en))
        #expect(MlsChatText.warning(.undecryptable(count: 1, fromLogSeq: nil), locale: en) == "1 message can't be read on this device.")
        #expect(MlsChatText.warning(.undecryptable(count: 12, fromLogSeq: nil), locale: en) == "12 messages can't be read on this device.")
    }
    @Test func theRejoinTextFollowsTheReasonAndStateLostHasItsOwnWording() {
        let reasons: [MlsRejoinReason?] = [nil, .pruned, .gateRejected, .applyFailed, .welcomeExpired, .stateLost, .unknown("banana")]
        let texts = reasons.map { MlsChatText.rejoin($0, locale: en) }
        #expect(Set(texts).count == reasons.count)
        #expect(MlsChatText.rejoin(.stateLost, locale: en).hasPrefix("This device lost its keys"))
        #expect(MlsChatText.rejoin(.unknown("banana"), locale: en) == "This device needs to rejoin the group to read new messages.")
        #expect(MlsChatText.rejoin(.pruned, locale: zh) != MlsChatText.rejoin(.pruned, locale: en))
    }
    @Test func theCatchUpLineShowsTheNumbersOrTheIndeterminateTextWhenTheTotalIsZero() {
        #expect(MlsChatText.catchUp(.running(done: 40, total: 120, skipping: false, error: nil), locale: en) == "Catching up on messages… 40 of 120")
        #expect(MlsChatText.catchUp(.running(done: 0, total: 0, skipping: false, error: nil), locale: en) == "Catching up on messages…")
        #expect(MlsChatText.catchUp(.rejoining(reason: nil), locale: en).hasPrefix("Rejoining the group."))
    }
    @Test func theQuotaLinesFollowTheFirstDayFlagAndTheResetTime() {
        #expect(MlsChatText.postQuota(MlsQuota(limit: 500, remaining: 60, firstDay: false), locale: en) == "60 of 500 messages left today")
        #expect(MlsChatText.postQuota(MlsQuota(limit: 20, remaining: 3, firstDay: true), locale: en) == "First day: 3 of 20 messages left")
        #expect(MlsChatText.commitQuota(MlsQuota(limit: 20, remaining: 2, firstDay: false), locale: en) == "2 of 20 group changes left today on this device")
        #expect(MlsChatText.postQuota(MlsQuota(limit: 20, remaining: 0, firstDay: false, resetsAt: 1_767_258_000_000), locale: en).hasPrefix("Resets "))
    }
    @Test func aVoidLineNamesWhoUndidTheChangeAndTheUndecryptableLinePluralises() {
        let by = MlsActorName(display: "Ana", isMe: false)
        let line = MlsChatText.line(MlsServiceLine(id: "1", kind: .void(by: by)), locale: en)
        #expect(line.contains("Ana") && line.hasSuffix(" undid a change"))
        #expect(MlsChatText.line(MlsServiceLine(id: "2", kind: .void(by: nil)), locale: en) == "Change undone")
        #expect(MlsChatText.line(MlsServiceLine(id: "3", kind: .undecryptable(count: 2)), locale: en) == "2 messages can't be read on this device")
        #expect(MlsChatText.error(.notOwner, locale: en) == "Only the owner can do this.")
    }
    @Test func thePrivacyEtaShowsATimeAndTheInfoRowTextIsFixed() {
        #expect(MlsChatText.privacyEta(1_767_258_000_000, locale: en).hasPrefix("Messages you send now go out around "))
        #expect(MlsChatText.privacyInfo(locale: en) == "Messages are sent with a short random delay for privacy.")
        #expect(MlsChatText.hintMobile(locale: en) == "You can add an agent from your desktop to keep the group open for joins.")
    }
    @Test func aDirectChatCarriesNoMlsBlockAndTheNewActionsDoNothingThere() {
        #expect(ChatState(loading: false).mls == nil)
        let banners = MlsChatState()
        #expect(banners.banners.isEmpty && banners.catchUp == nil && !banners.skipDialog && banners.voidTarget == nil)
    }
}
