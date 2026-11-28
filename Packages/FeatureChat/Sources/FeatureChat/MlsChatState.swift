// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
import RFLocalization

/// What the shared chat screen shows extra for an MLS group (MLS-GUI M2). Nil for a direct chat, so a direct chat renders
/// exactly as before. The entries come from the account-scoped `MlsGroupSession`; the screen only displays them.
public struct MlsChatState: Equatable, Sendable {
    public var entries: [MlsTimelineEntry] = []
    /// The composer is removed and a banner shows instead (removed, banned or left).
    public var readOnly: MlsReadOnly?
    /// The daily limit is used up: the composer is off until this time (unix milliseconds).
    public var composerOffUntil: Int64?
    /// The post waiting for the "Delete for everyone" confirmation.
    public var deleteTarget: String?
    public var mentionPicker = false
    public var mentionCandidates: [MlsMemberRow] = []
    /// The error of the last explicit action (delete), shown once.
    public var actionError: MlsGroupError?
    public init() {}
    /// The posted rows as the records the shared bubble draws, newest first: what the action menu, the text selection and
    /// the reply quote look up by id.
    public func messageRecords(locale: Locale = .current) -> [MessageRecord] {
        var previews: [String: String] = [:]
        for case .post(let row) in entries { if case .text(let text) = row.post.body, !row.isDeleted { previews[row.post.postID] = String(text.prefix(120)) } }
        return entries.compactMap { if case .post(let row) = $0 { MlsChatMapping.record(row, locale: locale, previews: previews) } else { nil } }.reversed()
    }
}

/// Localised text of the group chat: send states, typed errors and timeline lines. Names are bidi-isolated.
public enum MlsChatText {
    static func name(_ actor: MlsActorName, locale: Locale) -> String {
        if actor.isMe { return FeatureChatStrings.text("group.members.you", locale: locale) }
        guard let display = actor.display, !display.isEmpty else { return FeatureChatStrings.text("group.member.unnamed", locale: locale) }
        return RFBidi.isolate(display)
    }
    public static func displayName(_ author: MlsAuthor?, locale: Locale) -> String {
        guard let author else { return FeatureChatStrings.text("group.member.unnamed", locale: locale) }
        if author.isMe { return FeatureChatStrings.text("group.members.you", locale: locale) }
        guard let display = author.display, !display.isEmpty else { return FeatureChatStrings.text("group.member.unnamed", locale: locale) }
        return display
    }
    static func time(_ millis: Int64, locale: Locale) -> String {
        Date(timeIntervalSince1970: TimeInterval(millis) / 1000).formatted(.dateTime.hour().minute().locale(locale))
    }
    static func dateTime(_ millis: Int64, locale: Locale) -> String {
        Date(timeIntervalSince1970: TimeInterval(millis) / 1000).formatted(.dateTime.month().day().hour().minute().locale(locale))
    }
    /// A duration in minutes under one hour, otherwise hours.
    static func duration(_ seconds: Int, locale: Locale) -> String {
        let style = Duration.UnitsFormatStyle(allowedUnits: seconds < 3600 ? [.minutes] : [.hours], width: .wide).locale(locale)
        let value = seconds < 3600 ? max(1, (seconds + 59) / 60) : max(1, (seconds + 3599) / 3600)
        return (seconds < 3600 ? Duration.seconds(value * 60) : Duration.seconds(value * 3600)).formatted(style)
    }

    /// The text of a typed refusal (`group.error.*`).
    public static func error(_ error: MlsGroupError, locale: Locale, now: Date = Date()) -> String {
        switch error {
        case .notMember: FeatureChatStrings.text("group.error.notMember", locale: locale)
        case .notAdmin: FeatureChatStrings.text("group.error.notAdmin", locale: locale)
        case .ownerProtected: FeatureChatStrings.text("group.error.ownerProtected", locale: locale)
        case .tierUnavailable: FeatureChatStrings.text("group.error.tierUnavailable", locale: locale)
        case .groupFull: FeatureChatStrings.text("group.error.groupFull", locale: locale)
        case .paced(let retryAt): retryAt.map { FeatureChatStrings.format("group.error.paced", time($0, locale: locale), locale: locale) } ?? FeatureChatStrings.text("group.error.rateLimited", locale: locale)
        case .rateLimited: FeatureChatStrings.text("group.error.rateLimited", locale: locale)
        case .rejoinNeeded: FeatureChatStrings.text("group.error.rejoinNeeded", locale: locale)
        case .tooLarge(let bytes): FeatureChatStrings.format("group.error.tooLarge", (bytes.map { Int64($0) } ?? 0).formatted(.byteCount(style: .file).locale(locale)), locale: locale)
        case .hostUnreachable, .offline: FeatureChatStrings.text("group.error.hostUnreachable", locale: locale)
        case .unknownInvite: FeatureChatStrings.text("group.error.unknownInvite", locale: locale)
        case .requestNotFound: FeatureChatStrings.text("group.error.requestNotFound", locale: locale)
        case .messageNotFound: FeatureChatStrings.text("group.error.messageNotFound", locale: locale)
        case .notAuthor: FeatureChatStrings.text("group.error.notAuthor", locale: locale)
        case .voidNotHead: FeatureChatStrings.text("group.error.voidNotHead", locale: locale)
        case .unavailable: FeatureChatStrings.text("group.error.unavailable", locale: locale)
        case .generic: FeatureChatStrings.text("group.error.generic", locale: locale)
        }
    }

    /// The status line under an own bubble that is not posted yet.
    public static func status(_ state: MlsPendingPost.State, locale: Locale) -> String {
        switch state {
        case .submitting: FeatureChatStrings.text("group.send.sending", locale: locale)
        case .queued(let reason):
            switch reason {
            case .catchingUp: FeatureChatStrings.text("group.send.queued.catchingUp", locale: locale)
            case .hostUnreachable: FeatureChatStrings.text("group.send.queued.hostUnreachable", locale: locale)
            case .fetchingTokens: FeatureChatStrings.text("group.send.queued.fetchingTokens", locale: locale)
            case .unknown: FeatureChatStrings.text("group.send.queued.generic", locale: locale)
            }
        case .delayed(let after): FeatureChatStrings.format("group.send.delayed", time(after, locale: locale), locale: locale)
        case .notSent: FeatureChatStrings.text("group.send.failed", locale: locale)
        }
    }
    public static func notSentDetail(_ reason: MlsNotSentReason, locale: Locale) -> String {
        switch reason {
        case .error(let error): self.error(error, locale: locale)
        case .rateLimited(let quota):
            if quota.firstDay { FeatureChatStrings.format("group.send.rateLimited.firstDay", quota.limit, locale: locale) }
            else if let reset = quota.resetsAt { FeatureChatStrings.format("group.send.rateLimited", time(reset, locale: locale), locale: locale) }
            else { FeatureChatStrings.text("group.send.rateLimited.noReset", locale: locale) }
        case .failed: FeatureChatStrings.text("group.error.generic", locale: locale)
        }
    }

    /// One service line of the group timeline.
    public static func line(_ line: MlsServiceLine, locale: Locale) -> String {
        func n(_ actor: MlsActorName?) -> String { actor.map { name($0, locale: locale) } ?? FeatureChatStrings.text("group.member.unnamed", locale: locale) }
        return switch line.kind {
        case .joined(let names): many(names, one: "group.timeline.joined", other: "group.timeline.joinedMany", locale: locale)
        case .left(let names): many(names, one: "group.timeline.left", other: "group.timeline.leftMany", locale: locale)
        case .removed(let by, let target): by.map { FeatureChatStrings.format("group.timeline.removed", name($0, locale: locale), name(target, locale: locale), locale: locale) } ?? FeatureChatStrings.format("group.timeline.removedPassive", name(target, locale: locale), locale: locale)
        case .banned(let by, let target): by.map { FeatureChatStrings.format("group.timeline.banned", name($0, locale: locale), name(target, locale: locale), locale: locale) } ?? FeatureChatStrings.format("group.timeline.bannedPassive", name(target, locale: locale), locale: locale)
        case .roleAdmin(let by, let target): FeatureChatStrings.format("group.timeline.roleAdmin", n(by), name(target, locale: locale), locale: locale)
        case .roleMember(let by, let target): FeatureChatStrings.format("group.timeline.roleMember", n(by), name(target, locale: locale), locale: locale)
        case .name(let by, let value): FeatureChatStrings.format("group.timeline.name", n(by), RFBidi.isolate(String(value.text.prefix(64))), locale: locale)
        case .approvalOn(let by): FeatureChatStrings.format("group.timeline.approvalOn", n(by), locale: locale)
        case .approvalOff(let by): FeatureChatStrings.format("group.timeline.approvalOff", n(by), locale: locale)
        case .void: FeatureChatStrings.text("group.timeline.void", locale: locale)
        case .updated: FeatureChatStrings.text("group.timeline.updated", locale: locale)
        }
    }
    private static func many(_ names: [MlsActorName], one: String, other: String, locale: Locale) -> String {
        guard let first = names.first else { return FeatureChatStrings.text("group.timeline.updated", locale: locale) }
        if names.count == 1 { return FeatureChatStrings.format(one, name(first, locale: locale), locale: locale) }
        return FeatureChatStrings.format(other, name(first, locale: locale), names.count - 1, locale: locale)
    }
    public static func banner(_ reason: MlsReadOnly, locale: Locale) -> String {
        switch reason {
        case .left: FeatureChatStrings.text("group.leave.done", locale: locale)
        case .removed: FeatureChatStrings.text("group.state.removed", locale: locale)
        case .banned: FeatureChatStrings.text("group.state.banned", locale: locale)
        }
    }
}

/// How a posted group row becomes the record the shared bubble draws.
enum MlsChatMapping {
    static func record(_ row: MlsPostRow, locale: Locale, previews: [String: String]) -> MessageRecord {
        let post = row.post
        let kind: MessageRecord.Kind
        if row.isDeleted { kind = .deleted }
        else {
            switch post.body {
            case .text(let value): kind = .text(value)
            case .media(let caption): kind = caption.flatMap { $0.isEmpty ? nil : $0 }.map { .text($0) } ?? .unsupported(FeatureChatStrings.text("group.message.attachment", locale: locale))
            default: kind = .unsupported(FeatureChatStrings.text("group.timeline.updated", locale: locale))
            }
        }
        return MessageRecord(id: post.postID, sender: row.isMine ? "" : MlsChatText.displayName(post.author, locale: locale), kind: kind, isOwn: row.isMine, timestamp: post.appendedAt.map { $0 / 1000 }, delivery: row.isMine ? .sent : nil, replyTo: post.replyTo, replyPreview: post.replyTo.flatMap { previews[$0] }, authorAnchor: post.author?.anchor)
    }
}
