// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
import FeatureAgents
import FeatureChat
import FeatureConversations
import FeatureGroups

/// Data fixtures for design boards. Names, previews, counts and times are peer
/// or SDK data, never catalog copy, so each fixture language carries its own
/// sample. Chinese reproduces the zh boards; English reproduces the en boards
/// where the design has one; Arabic is the right-to-left sample with mixed
/// Latin names, digits and an @mention.
enum FixtureLanguage {
    case zh, en, ar

    init(localeID: String) {
        switch localeID {
        case "zh-CN": self = .zh
        case "ar": self = .ar
        default: self = .en
        }
    }
}

enum BoardFixtures {
    static func accountTitle(_ language: FixtureLanguage) -> String {
        switch language {
        case .zh: "林澈"
        case .en: "Lin Che"
        case .ar: "لين تشي"
        }
    }

    /// MOB-B01: the list rows as drawn on the board.
    static func conversationRows(_ language: FixtureLanguage) -> [ConversationRecord] {
        let text: [String]
        switch language {
        case .zh:
            text = ["林悦", "好的，附件里的版本说明也请一起看。", "Nova", "协作设置已确认", "产品探索", "收到，稍后一起看。", "你：", "周宁", "好的，明天继续。", "昨天", "团队公告", "本周安排与文档", "周二"]
        case .en:
            text = ["Lin Yue", "Sure, please read the release notes in the attachment too.", "Nova", "Collaboration settings confirmed", "Product discovery", "Got it, let us look at it later.", "You:", "Zhou Ning", "OK, let us continue tomorrow.", "Yesterday", "Team notices", "This week's schedule and documents", "Tue"]
        case .ar:
            text = ["ليلى أحمد", "حسنًا، راجع أيضًا ملاحظات الإصدار 2.4 في المرفق.", "Nova", "تم تأكيد إعدادات التعاون", "استكشاف المنتج", "تم، سنراجعها لاحقًا مع @Lina.", "أنت:", "مُحَمَّد", "حسنًا، نكمل غدًا.", "أمس", "إعلانات الفريق", "جدول هذا الأسبوع والمستندات", "الثلاثاء"]
        }
        return [
            ConversationRecord(id: "lin-yue", title: text[0], preview: text[1], unreadCount: 1, timeLabel: "10:24"),
            ConversationRecord(id: "nova", title: text[2], preview: text[3], timeLabel: "09:42", kind: "agent", avatarIcon: "orbit"),
            ConversationRecord(id: "product", title: text[4], preview: text[5], timeLabel: "10:23", kind: "channel", pinned: true, sender: text[6]),
            ConversationRecord(id: "zhou-ning", title: text[7], preview: text[8], timeLabel: text[9], readReceipt: true),
            ConversationRecord(id: "notice", title: text[10], preview: text[11], unreadCount: 5, timeLabel: text[12], kind: "group", muted: true),
        ]
    }

    static func conversations(_ board: String, _ language: FixtureLanguage) -> ConversationsState {
        var state: ConversationsState
        switch board {
        case "MOB-B01":
            state = ConversationsState(rows: conversationRows(language))
            state.strangersUnread = 3
        case "MOB-B01L":
            state = ConversationsState(loading: true)
        case "MOB-B01X":
            state = ConversationsState(failure: .offline)
        default:
            state = ConversationsState()
        }
        state.accountTitle = accountTitle(language)
        return state
    }

    static func peerName(_ language: FixtureLanguage) -> String {
        switch language {
        case .zh: "林悦"
        case .en: "Lin Yue"
        case .ar: "ليلى أحمد"
        }
    }

    /// MOB-B02 and MOB-B02E. Times are today in the simulator's time zone, so the
    /// view's locale formatting yields the board's clock values.
    static func chat(_ board: String, _ language: FixtureLanguage) -> ChatState {
        var state = ChatState()
        state.conversationID = "lin-yue"
        state.displayTitle = peerName(language)
        guard board == "MOB-B02" else { return state }
        let text: [String]
        switch language {
        case .zh:
            text = ["新版资料我整理好了，你有空时看一下。", "收到，我会把问题逐项回复。", "好的，附件里的版本说明也请一起看。", "版本说明.pdf"]
        case .en:
            text = ["I have put the new material together, take a look when you have time.", "Got it, I will reply to each point.", "Sure, please read the release notes in the attachment too.", "Release notes.pdf"]
        case .ar:
            text = ["جهّزت المواد الجديدة، ألقِ نظرة عندما يتسنى لك.", "تم، سأرد على كل نقطة مع @Lina.", "حسنًا، راجع أيضًا ملاحظات الإصدار 2.4 في المرفق.", "ملاحظات الإصدار.pdf"]
        }
        // The SDK page is newest first; the timeline reverses it.
        state.messages = [
            MessageRecord(id: "m3", sender: state.displayTitle, kind: .text(text[2]), isOwn: false, timestamp: today(10, 24), attachments: [AttachmentRecord(id: "notes", name: text[3], mime: "application/pdf")]),
            MessageRecord(id: "m2", sender: "", kind: .text(text[1]), isOwn: true, timestamp: today(10, 23), delivery: .delivered),
            MessageRecord(id: "m1", sender: state.displayTitle, kind: .text(text[0]), isOwn: false, timestamp: today(10, 21)),
        ]
        return state
    }

    static func groups(_ language: FixtureLanguage) -> GroupsState {
        let names: [String]
        switch language {
        case .zh: names = ["产品探索", "设计协作"]
        case .en: names = ["Product discovery", "Design collaboration"]
        case .ar: names = ["استكشاف المنتج", "التعاون في التصميم"]
        }
        let product = GroupRecord(id: "product-discovery", name: names[0], epoch: 3, members: ["phone", "peer-one", "peer-two"])
        let design = GroupRecord(id: "design-collaboration", name: names[1], epoch: 5, members: ["phone", "peer-one"])
        var state = GroupsState()
        state.accountID = "preview-account"
        state.groups = [product, design]
        state.visibleGroups = state.groups
        return state
    }

    /// MOB-C15: a signed-in account with no groups.
    static func groupsNoneYet() -> GroupsState {
        var state = GroupsState()
        state.accountID = "preview-account"
        return state
    }

    static func agents(_ language: FixtureLanguage) -> AgentsState {
        let detail: [String]
        switch language {
        case .zh: detail = ["研究搭档 · 协作设置已确认", "规划助手 · 协作设置已确认", "写作伙伴 · 协作已暂停"]
        case .en: detail = ["Research partner · Collaboration settings confirmed", "Planning assistant · Collaboration settings confirmed", "Writing partner · Collaboration paused"]
        case .ar: detail = ["شريك بحث · تم تأكيد إعدادات التعاون", "مساعد تخطيط · تم تأكيد إعدادات التعاون", "شريك كتابة · التعاون متوقف مؤقتًا"]
        }
        var state = AgentsState()
        state.entries = [
            AgentEntry(id: "nova", name: "Nova", detail: detail[0], icon: "orbit"),
            AgentEntry(id: "atlas", name: "Atlas", detail: detail[1], icon: "gem"),
            AgentEntry(id: "mira", name: "Mira", detail: detail[2], icon: "user-round"),
        ]
        return state
    }

    private static func today(_ hour: Int, _ minute: Int) -> Int64? {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()).map { Int64($0.timeIntervalSince1970) }
    }
}
