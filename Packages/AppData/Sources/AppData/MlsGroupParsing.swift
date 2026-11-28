// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// Pure parsers over the response objects, error frames and `group.event` bodies of the M2 methods (r3 table). They
/// follow the assumptions Q1 to Q4 and Q8 to Q12 of the common contract. Nothing here logs a payload.
public enum MlsGroupParsing {
    static let maxName = 64
    static let maxDisplay = 128
    static let maxText = 65_536
    static let maxRows = 500

    // MARK: Scalars
    static func int(_ value: JSONValue?) -> Int64? {
        switch value {
        case .number(let number): Int64(exactly: number.rounded(.towardZero))
        case .unsigned(let number): Int64(exactly: number)
        case .string(let text): Int64(text)
        default: nil
        }
    }
    static func count(_ value: JSONValue?) -> Int { int(value).map { Int(clamping: max(0, $0)) } ?? 0 }
    static func text(_ value: JSONValue?, limit: Int = 4096) -> String? {
        guard let text = value?.string, !text.isEmpty, text.utf8.count <= limit else { return nil }
        return text
    }
    static func clipped(_ value: JSONValue?, limit: Int) -> String? {
        guard let text = value?.string, !text.isEmpty else { return nil }
        return String(text.prefix(limit))
    }
    static func array(_ value: JSONValue?) -> [JSONValue] { if case .array(let items)? = value { Array(items.prefix(maxRows)) } else { [] } }
    private static func object(_ value: JSONValue?) -> JSONValue? { if case .object? = value { value } else { nil } }

    // MARK: Shared objects
    /// `author{anchor, display, ai_flag, is_me}`; a bare anchor string is accepted as a non-contact (Q2).
    public static func author(_ value: JSONValue?) -> MlsAuthor? {
        if let bare = text(value, limit: 2048) { return MlsAuthor(anchor: bare) }
        guard let anchor = text(value?["anchor"], limit: 2048) else { return nil }
        return MlsAuthor(anchor: anchor, display: clipped(value?["display"], limit: maxDisplay), aiFlag: value?["ai_flag"] == .bool(true), isMe: value?["is_me"] == .bool(true))
    }
    public static func quota(_ value: JSONValue?) -> MlsQuota? {
        guard let value, object(value) != nil, let limit = int(value["limit"]) else { return nil }
        return MlsQuota(limit: Int(clamping: limit), remaining: count(value["remaining"]), firstDay: value["first_day"] == .bool(true), resetsAt: int(value["resets_at"]))
    }
    static func privacyDelay(_ value: JSONValue?) -> MlsPrivacyDelay {
        guard let value, object(value) != nil else { return .none }
        if let after = int(value["send_after"]) { return .waiting(sendAfter: after) }
        return .armed
    }
    static func queueReason(_ raw: String?) -> MlsQueueReason {
        switch raw {
        case "catching_up": .catchingUp
        case "host_unreachable": .hostUnreachable
        case "fetching_tokens": .fetchingTokens
        default: .unknown(String((raw ?? "").prefix(64)))
        }
    }

    // MARK: group.list / group.info
    public static func info(_ body: JSONValue) -> MlsGroupInfo? {
        guard let id = text(body["group_id"], limit: 512) else { return nil }
        let catchState: MlsCatchUp.State = switch body["catch_up"]?["state"]?.string { case "running": .running; case "rejoining": .rejoining; default: .idle }
        let warnings: [MlsWarning] = array(body["warnings"]).prefix(16).compactMap { row in
            warning(row)
        }
        return MlsGroupInfo(groupID: id, name: String((body["name"]?.string ?? "").prefix(maxName)), tier: Int(clamping: int(body["tier"]) ?? 1000), members: count(body["members"]), leaves: count(body["leaves"]), agents: count(body["agents"]),
                            approval: body["approval"] != .bool(false), myRole: MlsRole(raw: body["my_role"]?.string), hostNode: clipped(body["host_node"], limit: 256), push: MlsPush(raw: body["push"]?.string),
                            catchUp: MlsCatchUp(state: catchState, done: count(body["catch_up"]?["done"]), total: count(body["catch_up"]?["total"])), privacyDelay: privacyDelay(body["privacy_delay"]),
                            postQuota: quota(body["quota"]?["post"]), commitQuota: quota(body["quota"]?["commit"]), lastLogSeq: int(body["last_log_seq"]) ?? 0, warnings: warnings, lastActivityAt: int(body["last_activity_at"]) ?? 0,
                            unread: count(body["unread"]), unreadMentions: count(body["unread_mentions"]), readLogSeq: int(body["read_log_seq"]) ?? 0, lastPost: lastPost(body["last_post"]))
    }
    /// One `{code, params, cleared?}` of `group.info.warnings` or the body of a `warning` event (common 2.7).
    public static func warning(_ row: JSONValue?) -> MlsWarning? {
        guard let code = text(row?["code"], limit: 128) else { return nil }
        let params = row?["params"]
        let parsed: MlsWarningCode
        switch code {
        case "fork_alarm": parsed = .forkAlarm(headN: int(params?["head_n"]).map { Int(clamping: $0) })
        case "rejoin_needed": parsed = .rejoinNeeded(MlsRejoinReason(raw: params?["reason"]?.string))
        case "undecryptable": parsed = .undecryptable(count: count(params?["count"]), fromLogSeq: int(params?["from_log_seq"]))
        case "admission_needs_online": parsed = .admissionNeedsOnline
        case "host_unusual": parsed = .hostUnusual(MlsHostUnusualKind(raw: params?["kind"]?.string))
        case "head_commit_rejected": parsed = .headCommitRejected(logSeq: int(params?["log_seq"]))
        case "host_ip_visible": parsed = .hostIpVisible(hostNode: clipped(params?["host_node"], limit: 256))
        default: parsed = .unknown(String(code.prefix(64)))
        }
        return MlsWarning(code: parsed, cleared: row?["cleared"] == .bool(true))
    }
    static func lastPost(_ value: JSONValue?) -> MlsLastPost? {
        guard let value, object(value) != nil, let seq = int(value["log_seq"]) else { return nil }
        return MlsLastPost(logSeq: seq, kind: MlsPostKind(raw: value["kind"]?.string), author: author(value["author"]), snippet: value["snippet"]?.string.map { String($0.prefix(100)) }, appendedAt: int(value["appended_at"]))
    }
    public static func list(_ body: JSONValue) -> MlsGroupPage {
        MlsGroupPage(groups: array(body["groups"]).compactMap(info), cursor: text(body["cursor"], limit: 512))
    }

    // MARK: Invites
    public static func invite(_ body: JSONValue?) -> MlsInvite? {
        guard let body, let id = text(body["invite_id"], limit: 512), let link = text(body["link"], limit: 512) else { return nil }
        return MlsInvite(inviteID: id, link: link, maxUses: Int(clamping: int(body["max_uses"]) ?? 0), usesLeft: int(body["uses_left"]).map { Int(clamping: $0) }, expiresAt: int(body["expires_at"]) ?? 0, revoked: body["revoked"] == .bool(true))
    }
    public static func created(_ body: JSONValue) -> MlsCreated? {
        guard let id = text(body["group_id"], limit: 512), let invite = invite(body["invite"]) else { return nil }
        return MlsCreated(groupID: id, invite: invite)
    }
    public static func invites(_ body: JSONValue) -> [MlsInvite] { array(body["invites"]).compactMap { invite($0) } }

    // MARK: group.join
    public static func refusal(reason: String?, params: JSONValue?) -> MlsJoinRefusal {
        switch reason {
        case "link_invalid": .linkInvalid
        case "invite_expired": .inviteExpired(expiredAt: int(params?["expired_at"]))
        case "invite_invalid": .inviteInvalid
        case "queue_full": .queueFull
        case "group_full": .groupFull
        case "request_expired": .requestExpired(expiredAt: int(params?["expired_at"]))
        case "already_member": .alreadyMember(groupID: text(params?["group_id"], limit: 512))
        case "rate_limited": .rateLimited(retryAfterSeconds: int(params?["retry_after_s"]).map { Int(clamping: $0) })
        default: .unknown(String((reason ?? "").prefix(64)))
        }
    }
    /// `joined{group_id}`, `pending{request_id, reason, expires_at}` or `refused{reason, params}`; nil for a malformed reply.
    public static func join(_ body: JSONValue) -> MlsJoinResult? {
        switch body["state"]?.string {
        case "joined":
            guard let id = text(body["group_id"], limit: 512) else { return nil }
            return .joined(groupID: id)
        case "pending":
            guard let request = text(body["request_id"], limit: 512) else { return nil }
            return .pending(requestID: request, reason: pendingReason(body["reason"]?.string), expiresAt: int(body["expires_at"]) ?? 0)
        case "refused": return .refused(refusal(reason: body["reason"]?.string, params: body["params"]))
        default: return nil
        }
    }

    static func pendingReason(_ raw: String?) -> MlsPendingReason {
        switch raw { case "awaiting_admin": .awaitingAdmin; case "awaiting_member_online": .awaitingMemberOnline; default: .unknown(String((raw ?? "").prefix(64))) }
    }
    /// `group.join.pending{}` (r4 item 7): at most 100 rows.
    public static func pendingJoins(_ body: JSONValue) -> [MlsPendingJoin] {
        array(body["requests"]).prefix(100).compactMap { row in
            guard let request = text(row["request_id"], limit: 512), let group = text(row["group_id"], limit: 512) else { return nil }
            return MlsPendingJoin(requestID: request, groupID: group, hostNode: clipped(row["host_node"], limit: 256), reason: pendingReason(row["reason"]?.string), requestedAt: int(row["requested_at"]) ?? 0, expiresAt: int(row["expires_at"]) ?? 0)
        }
    }
    /// `group.refresh` (r4 item 17).
    public static func refresh(_ body: JSONValue) -> [MlsRefreshRow] {
        array(body["groups"]).compactMap { row in text(row["group_id"], limit: 512).map { MlsRefreshRow(groupID: $0, lastLogSeq: int(row["last_log_seq"]) ?? 0, newPosts: count(row["new_posts"])) } }
    }
    /// `group.mark_read` (r4 item 18).
    public static func readState(_ body: JSONValue) -> MlsReadState? {
        guard let seq = int(body["read_log_seq"]) else { return nil }
        return MlsReadState(readLogSeq: seq, unread: count(body["unread"]), unreadMentions: count(body["unread_mentions"]))
    }

    // MARK: group.members
    public static func member(_ row: JSONValue) -> MlsMemberRow? {
        guard let anchor = text(row["anchor"], limit: 2048) else { return nil }
        return MlsMemberRow(anchor: anchor, display: clipped(row["display"], limit: maxDisplay), role: MlsRole(raw: row["role"]?.string), aiFlag: row["ai_flag"] == .bool(true), devices: max(1, count(row["devices"])), isMe: row["is_me"] == .bool(true))
    }
    public static func members(_ body: JSONValue) -> MlsMemberPage { MlsMemberPage(rows: array(body["rows"]).compactMap(member), cursor: text(body["cursor"], limit: 512)) }

    // MARK: Post state, history, send
    private static func stateName(_ value: JSONValue?) -> (String?, JSONValue?) {
        if let name = value?.string { return (name, nil) }
        if let name = value?["state"]?.string ?? value?["name"]?.string { return (name, value) }
        return (nil, nil)
    }
    /// A history row `state`: the string and the row's `params`.
    public static func postState(_ value: JSONValue?, params: JSONValue?, send: JSONValue? = nil) -> MlsPostState {
        let (name, inline) = stateName(value)
        let params = params ?? inline
        switch name {
        case "pending": return .pending(send.map { sendState($0["state"], params: $0["params"]) })
        case "sent": return .sent
        case "queued": return .queued(queueReason(params?["reason"]?.string))
        case "delayed_privacy": return .delayed(sendAfter: int(params?["send_after"]) ?? 0)
        case "rate_limited": return .rateLimited(quota(params))
        case "failed": return .failed(String((params?["reason"]?.string ?? "").prefix(64)))
        case "deleted": return .deleted
        default: return .unknown(String((name ?? "").prefix(64)))
        }
    }
    static func change(_ row: JSONValue) -> MlsMembershipChange? {
        guard let author = author(row) else { return nil }
        let kind: MlsChangeKind = switch row["change"]?.string {
        case "joined": .joined; case "left": .left; case "removed": .removed; case "banned": .banned; case "role_changed": .roleChanged
        case "device_added": .deviceAdded; case "device_removed": .deviceRemoved
        default: .unknown(String((row["change"]?.string ?? "").prefix(64)))
        }
        return MlsMembershipChange(change: kind, actor: author, role: row["role"]?.string.map { MlsRole(raw: $0) }, isMe: row["is_me"] == .bool(true))
    }
    static func body(kind: MlsPostKind, row: JSONValue) -> MlsPostBody {
        let body = row["body"]
        switch kind {
        case .text: return .text(body?.string.map { String($0.prefix(maxText)) } ?? body?["text"]?.string.map { String($0.prefix(maxText)) } ?? "")
        case .attachment, .card: return .media(caption: body?["text"]?.string ?? body?["caption"]?.string)
        case .membership:
            let source = body ?? row
            return .membership(changes: array(source["changes"]).compactMap(change), by: author(source["by"]))
        case .settings:
            let source = body ?? row
            return .settings(name: clipped(source["name"], limit: maxName), approval: source["approval"]?.bool, by: author(source["by"]))
        case .void:
            let source = body ?? row
            return .void(voidedLogSeq: int(source["voided_log_seq"]), by: author(source["by"]))
        case .unknown: return .none
        }
    }
    /// One `group.history` row, or the row of a `post` event.
    public static func post(_ row: JSONValue, kind forced: MlsPostKind? = nil) -> MlsPost? {
        let kind = forced ?? MlsPostKind(raw: row["kind"]?.string)
        let service = kind == .membership || kind == .settings || kind == .void
        guard let id = text(row["post_id"], limit: 512) ?? (service ? "log:" + String(int(row["log_seq"]) ?? 0) : nil) else { return nil }
        let author = author(row["author"])
        // Only service rows may lack an author (r4 item 11); a text, attachment or card row without one is malformed.
        guard author != nil || service || { if case .unknown = kind { true } else { false } }() else { return nil }
        let mentions = array(row["mentions"]).prefix(64).compactMap { text($0, limit: 2048) }
        return MlsPost(logSeq: int(row["log_seq"]), postID: id, author: author, appendedAt: int(row["appended_at"]) ?? int(row["at"]), kind: kind, body: body(kind: kind, row: row), replyTo: text(row["reply_to"], limit: 512), mentions: mentions, state: postState(row["state"], params: row["params"], send: row["send"]))
    }
    public static func history(_ body: JSONValue) -> MlsHistoryPage {
        MlsHistoryPage(posts: array(body["posts"]).compactMap { post($0) }, floorLogSeq: int(body["floor_log_seq"]) ?? 0, lastLogSeq: int(body["last_log_seq"]) ?? 0, more: body["more"] == .bool(true))
    }
    /// `{post_id, state, params}` of `group.send`; nil when the post id is missing.
    public static func send(_ body: JSONValue) -> MlsSendReceipt? {
        guard let id = text(body["post_id"], limit: 512) else { return nil }
        return MlsSendReceipt(postID: id, state: sendState(body["state"], params: body["params"] ?? body))
    }
    static func sendState(_ value: JSONValue?, params: JSONValue?) -> MlsSendState {
        let (name, inline) = stateName(value)
        let params = params ?? inline
        switch name {
        case "sent": return .sent(logSeq: int(params?["log_seq"]) ?? 0)
        case "queued": return .queued(queueReason(params?["reason"]?.string))
        case "delayed_privacy": return .delayed(sendAfter: int(params?["send_after"]) ?? 0, delaySeconds: Int(clamping: int(params?["delay_s"]) ?? 0))
        case "rate_limited": return .rateLimited(quota(params) ?? MlsQuota(limit: 0, remaining: 0, firstDay: false))
        case "failed": return .failed(String((params?["reason"]?.string ?? "").prefix(64)))
        default: return .unknown(String((name ?? "").prefix(64)))
        }
    }
    /// `{state: committed, log_seq}` of `group.leave` and `group.message.delete`; nil when the state is not `committed`.
    public static func commit(_ body: JSONValue) -> MlsCommit? {
        guard body["state"]?.string == "committed" else { return nil }
        return MlsCommit(logSeq: int(body["log_seq"]))
    }

    /// `group.message.delete` (r4 item 10): `{post_id, state: deleted, log_seq}` or `{post_id, state: queued|delayed_privacy, params}`.
    public static func deleteOutcome(_ body: JSONValue) -> MlsDeleteOutcome? {
        switch body["state"]?.string {
        case "deleted": return .deleted(logSeq: int(body["log_seq"]))
        case "queued": return .queued(queueReason(body["params"]?["reason"]?.string))
        case "delayed_privacy": return .delayed(sendAfter: int(body["params"]?["send_after"]) ?? 0)
        case nil: return nil
        case let other?: return .unknown(String(other.prefix(64)))
        }
    }

    // MARK: M3 results
    /// A `group.requests.list` row, or the body of a `pending_join` event.
    public static func joinRequest(_ row: JSONValue?) -> MlsJoinRequest? {
        guard let row, object(row) != nil, let id = text(row["request_id"], limit: 512), let anchor = text(row["anchor"], limit: 2048) else { return nil }
        return MlsJoinRequest(requestID: id, anchor: anchor, display: clipped(row["display"], limit: maxDisplay), aiFlag: row["ai_flag"] == .bool(true), requestedAt: int(row["requested_at"]) ?? 0, expiresAt: int(row["expires_at"]) ?? 0)
    }
    /// `{requests[], cursor?}` (Q2).
    public static func requests(_ body: JSONValue) -> MlsRequestsPage {
        MlsRequestsPage(rows: array(body["requests"]).compactMap(joinRequest), cursor: text(body["cursor"], limit: 512))
    }
    /// `{state: committed, log_seq}` or `{state: declined}` (Q3); nil for any other reply.
    public static func adminOutcome(_ body: JSONValue) -> MlsAdminOutcome? {
        switch body["state"]?.string {
        case "committed": .committed(logSeq: int(body["log_seq"]))
        case "declined": .declined
        default: nil
        }
    }
    /// `{push}` of the per-device push method (Q1).
    public static func pushResult(_ body: JSONValue) -> MlsPush? {
        guard let raw = body["push"]?.string else { return nil }
        return MlsPush(raw: raw)
    }
    /// `{state: rejoining}` or `{state: running, done, total}` of `group.catch_up{skip: true}`.
    public static func catchUpResult(_ body: JSONValue) -> MlsCatchUpResult? {
        switch body["state"]?.string {
        case "rejoining": .rejoining
        case "running": .running(done: count(body["done"]), total: count(body["total"]))
        case "idle": .idle
        default: nil
        }
    }
    static func catchUp(_ body: JSONValue?) -> MlsCatchUp? {
        switch body?["state"]?.string {
        case "idle": MlsCatchUp(state: .idle)
        case "running": MlsCatchUp(state: .running, done: count(body?["done"]), total: count(body?["total"]))
        case "rejoining": MlsCatchUp(state: .rejoining, done: count(body?["done"]), total: count(body?["total"]))
        default: nil
        }
    }

    // MARK: group.event
    public static func event(_ body: JSONValue) -> MlsGroupEvent {
        guard let kind = body["kind"]?.string, let group = text(body["group_id"], limit: 512) else { return .ignored }
        let seq = int(body["seq"]), at = int(body["at"])
        let row = object(body["post"]) ?? body
        switch kind {
        case "post":
            // The row is the nested `post` object; a flattened row shares the envelope's `kind`, so its own kind comes from `post_kind`.
            let nested = object(body["post"]) != nil
            guard let post = post(row, kind: nested ? nil : MlsPostKind(raw: body["post_kind"]?.string ?? "text")) else { return .ignored }
            return .post(groupID: group, seq: seq, at: at, post: post)
        case "membership":
            guard let post = post(row, kind: .membership) else { return .ignored }
            return .membership(groupID: group, seq: seq, at: at, post: post)
        case "settings":
            guard let post = post(row, kind: .settings) else { return .ignored }
            return .settings(groupID: group, seq: seq, at: at, post: post)
        case "post_state":
            guard let id = text(body["post_id"], limit: 512) else { return .ignored }
            return .postState(groupID: group, postID: id, state: postState(body["state"], params: body["params"]), logSeq: int(body["log_seq"]))
        case "post_deleted":
            guard let id = text(body["post_id"], limit: 512) else { return .ignored }
            return .postDeleted(groupID: group, postID: id, postLogSeq: int(body["post_log_seq"]), logSeq: int(body["log_seq"]))
        case "read":
            return .read(groupID: group, readLogSeq: int(body["read_log_seq"]) ?? 0, unread: count(body["unread"]), unreadMentions: count(body["unread_mentions"]))
        case "join_result":
            guard let request = text(body["request_id"], limit: 512) else { return .ignored }
            let outcome: MlsJoinEvent.Outcome = body["state"]?.string == "joined" ? .joined : .refused(refusal(reason: body["reason"]?.string, params: body["params"]))
            return .joinResult(MlsJoinEvent(requestID: request, groupID: text(body["group_id"], limit: 512), outcome: outcome))
        case "void":
            // The same row as a `post{kind: void}`: the log row is keyed by `log_seq`, so the two deliveries deduplicate.
            guard int(row["log_seq"]) != nil, let post = post(row, kind: .void) else { return .ignored }
            return .post(groupID: group, seq: seq, at: at, post: post)
        case "pending_join":
            guard let request = joinRequest(object(body["body"]) ?? body) else { return .ignored }
            return .pendingJoin(groupID: group, seq: seq, request: request)
        case "catch_up":
            guard let state = catchUp(object(body["body"]) ?? body) else { return .ignored }
            return .catchUp(groupID: group, seq: seq, state: state)
        case "warning":
            guard let warning = warning(object(body["body"]) ?? body) else { return .ignored }
            return .warning(groupID: group, seq: seq, warning: warning)
        default: return .ignored
        }
    }
    // MARK: Errors
    /// The error frame of a refused call: `error.code` (or the typed name) and `error.details`.
    public static func error(_ failure: CoreFailure) -> MlsGroupError {
        let details = failure.response?["error"]?["details"] ?? failure.response?["details"]
        let names = [failure.typedName, failure.reasonCode, failure.response?["error"]?["code"]?.string, failure.reason].compactMap { $0 }
        for name in names { if let mapped = error(code: name, details: details) { return mapped } }
        return .generic(names.first.map { String($0.prefix(64)) })
    }
    public static func error(code: String, details: JSONValue? = nil) -> MlsGroupError? {
        switch code {
        case "not_member": .notMember
        case "not_admin": details?["required"]?.string == "owner" ? .notOwner : .notAdmin
        case "owner_protected": .ownerProtected
        case "tier_unavailable": .tierUnavailable
        case "group_full": .groupFull
        case "paced": .paced(retryAt: int(details?["retry_at"]))
        case "rate_limited": .rateLimited
        case "rejoin_needed": .rejoinNeeded
        case "too_large": .tooLarge(maxBytes: int(details?["max_bytes"]).map { Int(clamping: $0) })
        case "host_unreachable": .hostUnreachable
        case "unknown_invite": .unknownInvite
        case "request_not_found": .requestNotFound
        case "message_not_found": .messageNotFound
        case "not_author": .notAuthor
        case "void_not_head": .voidNotHead(headLogSeq: int(details?["head_log_seq"]))
        default: nil
        }
    }
    /// A refusal as the session sees it: a typed code, `offline` for a transport failure, a plain failure otherwise.
    public static func error(_ error: any Error) -> MlsGroupError {
        if let typed = error as? MlsGroupError { return typed }
        if let failure = error as? CoreFailure { return self.error(failure) }
        return AppFailure.map(error) == .offline ? .offline : .generic(nil)
    }
}
