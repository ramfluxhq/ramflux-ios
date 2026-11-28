// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

// MLS groups (MLS-GUI M2): the value types of the r3 method table. Every enum has `unknown(String)`. Times are unix
// milliseconds (`*At`), durations are seconds (`*Seconds`). Nothing here is persisted, and nothing prints an anchor, a
// name, a body or a link.

/// A member as a post or a roster entry names it. `display` is nil for a non-contact: the screen shows "Member", never the anchor.
public struct MlsAuthor: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let anchor: String
    public let display: String?
    /// From the SDK `ai_flag` only (S8); the session merges it so it is never dropped on a re-read.
    public let aiFlag: Bool
    public let isMe: Bool
    public init(anchor: String, display: String? = nil, aiFlag: Bool = false, isMe: Bool = false) { self.anchor = anchor; self.display = display; self.aiFlag = aiFlag; self.isMe = isMe }
    public var description: String { "MlsAuthor" }
    public var debugDescription: String { description }
}

public enum MlsRole: Equatable, Sendable {
    case owner, admin, member, unknown(String)
    public init(raw: String?) {
        switch raw { case "owner": self = .owner; case "admin": self = .admin; case "member": self = .member; default: self = .unknown(String((raw ?? "").prefix(64))) }
    }
    /// r4 item 9: every member may create invites; admins and the owner spend no commit token.
    public var canInvite: Bool { true }
}

public enum MlsPush: Equatable, Sendable {
    case mentionsReplies, all, none, unknown(String)
    public init(raw: String?) {
        switch raw { case "mentions_replies": self = .mentionsReplies; case "all": self = .all; case "none": self = .none; default: self = .unknown(String((raw ?? "").prefix(64))) }
    }
}

public struct MlsQuota: Equatable, Sendable {
    public let limit: Int
    public let remaining: Int
    public let firstDay: Bool
    public let resetsAt: Int64?
    public init(limit: Int, remaining: Int, firstDay: Bool, resetsAt: Int64? = nil) { self.limit = limit; self.remaining = remaining; self.firstDay = firstDay; self.resetsAt = resetsAt }
}

/// `privacy_delay` (r3 item 5): parsed in M2, shown in M3.
public enum MlsPrivacyDelay: Equatable, Sendable {
    case none
    case armed
    case waiting(sendAfter: Int64)
}

/// Why a device must rejoin (`rejoin_needed.params.reason`, r3 item 10).
public enum MlsRejoinReason: Equatable, Sendable, Hashable {
    case pruned, gateRejected, applyFailed, welcomeExpired, stateLost, unknown(String)
    public init(raw: String?) {
        switch raw {
        case "pruned": self = .pruned; case "gate_rejected": self = .gateRejected; case "apply_failed": self = .applyFailed
        case "welcome_expired": self = .welcomeExpired; case "state_lost": self = .stateLost
        default: self = .unknown(String((raw ?? "").prefix(64)))
        }
    }
}

public enum MlsHostUnusualKind: Equatable, Sendable, Hashable {
    case lateRoll, lateReply, unknown(String)
    public init(raw: String?) {
        switch raw { case "late_roll": self = .lateRoll; case "late_reply": self = .lateReply; default: self = .unknown(String((raw ?? "").prefix(64))) }
    }
}

/// A warning code with its params (common 2.7). `unknown` keeps the raw code for the generic row only.
public enum MlsWarningCode: Equatable, Sendable, Hashable {
    case forkAlarm(headN: Int?)
    case rejoinNeeded(MlsRejoinReason)
    case undecryptable(count: Int, fromLogSeq: Int64?)
    case admissionNeedsOnline
    case hostUnusual(MlsHostUnusualKind)
    case headCommitRejected(logSeq: Int64?)
    case hostIpVisible(hostNode: String?)
    case unknown(String)
    /// The set key: one warning per code name.
    public var key: String {
        switch self {
        case .forkAlarm: "fork_alarm"
        case .rejoinNeeded: "rejoin_needed"
        case .undecryptable: "undecryptable"
        case .admissionNeedsOnline: "admission_needs_online"
        case .hostUnusual: "host_unusual"
        case .headCommitRejected: "head_commit_rejected"
        case .hostIpVisible: "host_ip_visible"
        case .unknown(let raw): "unknown:" + raw
        }
    }
    /// The accessibility id suffix and the log name: a code only, never a param value.
    public var name: String {
        if case .unknown = self { return "unknown" }
        return key
    }
}

public struct MlsWarning: Equatable, Sendable {
    public let code: MlsWarningCode
    /// A `warning` event with `cleared: true`; a `group.info` row is never cleared.
    public let cleared: Bool
    public init(code: MlsWarningCode, cleared: Bool = false) { self.code = code; self.cleared = cleared }
    /// The M2 shape: a raw code name and `params.host_node`.
    public init(code: String, hostNode: String? = nil) {
        self.init(code: code == "host_ip_visible" ? .hostIpVisible(hostNode: hostNode) : .unknown(code))
    }
    /// `params.host_node` of `host_ip_visible`.
    public var hostNode: String? { if case .hostIpVisible(let node) = code { node } else { nil } }
}

public struct MlsCatchUp: Equatable, Sendable {
    public enum State: Equatable, Sendable { case idle, running, rejoining }
    public let state: State
    public let done: Int
    public let total: Int
    public init(state: State = .idle, done: Int = 0, total: Int = 0) { self.state = state; self.done = done; self.total = total }
}

/// `group.info` and a `group.list` row (which adds `last_activity_at`).
public struct MlsGroupInfo: Equatable, Sendable, Identifiable {
    public var id: String { groupID }
    public let groupID: String
    public let name: String
    public let tier: Int
    public let members: Int
    public let leaves: Int
    public let agents: Int
    public let approval: Bool
    public let myRole: MlsRole
    public let hostNode: String?
    public let push: MlsPush
    public let catchUp: MlsCatchUp
    public let privacyDelay: MlsPrivacyDelay
    public let postQuota: MlsQuota?
    public let commitQuota: MlsQuota?
    public let lastLogSeq: Int64
    public let warnings: [MlsWarning]
    public let lastActivityAt: Int64
    /// r4 item 18: computed locally from decrypted history.
    public let unread: Int
    public let unreadMentions: Int
    public let readLogSeq: Int64
    public let lastPost: MlsLastPost?
    public init(groupID: String, name: String, tier: Int = 1000, members: Int = 0, leaves: Int = 0, agents: Int = 0, approval: Bool = true, myRole: MlsRole = .member, hostNode: String? = nil, push: MlsPush = .mentionsReplies, catchUp: MlsCatchUp = MlsCatchUp(), privacyDelay: MlsPrivacyDelay = .none, postQuota: MlsQuota? = nil, commitQuota: MlsQuota? = nil, lastLogSeq: Int64 = 0, warnings: [MlsWarning] = [], lastActivityAt: Int64 = 0, unread: Int = 0, unreadMentions: Int = 0, readLogSeq: Int64 = 0, lastPost: MlsLastPost? = nil) {
        self.unread = unread; self.unreadMentions = unreadMentions; self.readLogSeq = readLogSeq; self.lastPost = lastPost
        self.groupID = groupID; self.name = name; self.tier = tier; self.members = members; self.leaves = leaves; self.agents = agents; self.approval = approval; self.myRole = myRole; self.hostNode = hostNode; self.push = push; self.catchUp = catchUp; self.privacyDelay = privacyDelay; self.postQuota = postQuota; self.commitQuota = commitQuota; self.lastLogSeq = lastLogSeq; self.warnings = warnings; self.lastActivityAt = lastActivityAt
    }
    /// The `host_ip_visible` host: the warning's `host_node`, else `host_node` of the info.
    public var visibleHost: String? { warnings.first { if case .hostIpVisible = $0.code { true } else { false } }?.hostNode ?? hostNode }
}

/// `last_post` of a list row: a text-only snippet of at most 100 characters.
public struct MlsLastPost: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let logSeq: Int64
    public let kind: MlsPostKind
    public let author: MlsAuthor?
    public let snippet: String?
    public let appendedAt: Int64?
    public init(logSeq: Int64, kind: MlsPostKind, author: MlsAuthor?, snippet: String?, appendedAt: Int64?) { self.logSeq = logSeq; self.kind = kind; self.author = author; self.snippet = snippet; self.appendedAt = appendedAt }
    public var description: String { "MlsLastPost" }
    public var debugDescription: String { description }
}

/// `group.mark_read` result.
public struct MlsReadState: Equatable, Sendable {
    public let readLogSeq: Int64
    public let unread: Int
    public let unreadMentions: Int
    public init(readLogSeq: Int64, unread: Int, unreadMentions: Int) { self.readLogSeq = readLogSeq; self.unread = unread; self.unreadMentions = unreadMentions }
}

/// One row of `group.join.pending` (r4 item 7): a join request still waiting, rebuilt after a relaunch.
public struct MlsPendingJoin: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let requestID: String
    public let groupID: String
    public let hostNode: String?
    public let reason: MlsPendingReason
    public let requestedAt: Int64
    public let expiresAt: Int64
    public init(requestID: String, groupID: String, hostNode: String?, reason: MlsPendingReason, requestedAt: Int64, expiresAt: Int64) { self.requestID = requestID; self.groupID = groupID; self.hostNode = hostNode; self.reason = reason; self.requestedAt = requestedAt; self.expiresAt = expiresAt }
    public var description: String { "MlsPendingJoin" }
    public var debugDescription: String { description }
}

public struct MlsGroupPage: Equatable, Sendable {
    public let groups: [MlsGroupInfo]
    public let cursor: String?
    public init(groups: [MlsGroupInfo], cursor: String?) { self.groups = groups; self.cursor = cursor }
}

/// An invite. The link is a secret (S1): it is never printed, logged or stored beyond the session's memory.
public struct MlsInvite: Equatable, Sendable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var id: String { inviteID }
    public let inviteID: String
    public let link: String
    public let maxUses: Int
    /// Known only right after create (r2 item 4); nil in a listing.
    public let usesLeft: Int?
    public let expiresAt: Int64
    public let revoked: Bool
    public init(inviteID: String, link: String, maxUses: Int, usesLeft: Int? = nil, expiresAt: Int64, revoked: Bool = false) { self.inviteID = inviteID; self.link = link; self.maxUses = maxUses; self.usesLeft = usesLeft; self.expiresAt = expiresAt; self.revoked = revoked }
    public var description: String { "MlsInvite(link=<redacted>)" }
    public var debugDescription: String { description }
    /// `dump()` and `Mirror` never reveal the link (S9).
    public var customMirror: Mirror { Mirror(self, children: ["inviteID": inviteID, "link": "<redacted>", "maxUses": maxUses, "expiresAt": expiresAt, "revoked": revoked], displayStyle: .struct) }
    public func isExpired(now: Int64) -> Bool { expiresAt > 0 && expiresAt <= now }
}

public struct MlsCreated: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let groupID: String
    public let invite: MlsInvite
    public init(groupID: String, invite: MlsInvite) { self.groupID = groupID; self.invite = invite }
    public var description: String { "MlsCreated(link=<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["groupID": groupID, "invite": invite], displayStyle: .struct) }
}

public enum MlsPendingReason: Equatable, Sendable { case awaitingAdmin, awaitingMemberOnline, unknown(String) }

public enum MlsJoinRefusal: Equatable, Sendable {
    case linkInvalid
    case inviteExpired(expiredAt: Int64?)
    /// r4 item 5: covers unknown, used-up, revoked and stale invites.
    case inviteInvalid
    case groupFull
    case queueFull
    case requestExpired(expiredAt: Int64?)
    case alreadyMember(groupID: String?)
    case rateLimited(retryAfterSeconds: Int?)
    /// A reason this client does not know; shows the generic refusal text.
    case unknown(String)
}

/// The three outcomes of `group.join`.
public enum MlsJoinResult: Equatable, Sendable {
    case joined(groupID: String)
    case pending(requestID: String, reason: MlsPendingReason, expiresAt: Int64)
    case refused(MlsJoinRefusal)
}

public struct MlsMemberRow: Equatable, Sendable, Identifiable {
    public var id: String { anchor }
    public let anchor: String
    public let display: String?
    public let role: MlsRole
    public let aiFlag: Bool
    public let devices: Int
    public let isMe: Bool
    public init(anchor: String, display: String? = nil, role: MlsRole = .member, aiFlag: Bool = false, devices: Int = 1, isMe: Bool = false) { self.anchor = anchor; self.display = display; self.role = role; self.aiFlag = aiFlag; self.devices = devices; self.isMe = isMe }
}

public struct MlsMemberPage: Equatable, Sendable {
    public let rows: [MlsMemberRow]
    public let cursor: String?
    public init(rows: [MlsMemberRow], cursor: String?) { self.rows = rows; self.cursor = cursor }
}

public enum MlsPostKind: Equatable, Sendable {
    case text, attachment, card, membership, settings, void, unknown(String)
    public init(raw: String?) {
        switch raw {
        case "text": self = .text; case "attachment": self = .attachment; case "card": self = .card
        case "membership": self = .membership; case "settings": self = .settings; case "void": self = .void
        default: self = .unknown(String((raw ?? "").prefix(64)))
        }
    }
}

public enum MlsQueueReason: Equatable, Sendable { case catchingUp, hostUnreachable, fetchingTokens, unknown(String) }

/// A post's state in history and in `post_state` events.
public enum MlsPostState: Equatable, Sendable {
    case sent
    case queued(MlsQueueReason)
    case delayed(sendAfter: Int64)
    case rateLimited(MlsQuota?)
    case failed(String)
    case deleted
    /// r4 item 8: an own unsent post (`state: pending`) with the send state of the SDK outbox.
    case pending(MlsSendState?)
    case unknown(String)
}

public enum MlsChangeKind: Equatable, Sendable { case joined, left, removed, banned, roleChanged, deviceAdded, deviceRemoved, unknown(String) }

public struct MlsMembershipChange: Equatable, Sendable {
    public let change: MlsChangeKind
    public let actor: MlsAuthor
    public let role: MlsRole?
    /// r4 item 13: `changes[].is_me`.
    public let isMe: Bool
    public init(change: MlsChangeKind, actor: MlsAuthor, role: MlsRole? = nil, isMe: Bool = false) { self.change = change; self.actor = actor; self.role = role; self.isMe = isMe || actor.isMe }
}

public enum MlsPostBody: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case text(String)
    /// An attachment or card row: only the caption text, when the row carries one.
    case media(caption: String?)
    case membership(changes: [MlsMembershipChange], by: MlsAuthor?)
    case settings(name: String?, approval: Bool?, by: MlsAuthor?)
    case void(voidedLogSeq: Int64?, by: MlsAuthor?)
    case none
    public var description: String { "MlsPostBody" }
    public var debugDescription: String { description }
}

/// One history row, or the row of a `post`, `membership` or `settings` event.
public struct MlsPost: Equatable, Sendable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible {
    public var id: String { postID }
    public let logSeq: Int64?
    public let postID: String
    /// Nil for a service row (r4 item 11): only `by` names the actor.
    public let author: MlsAuthor?
    public let appendedAt: Int64?
    public let kind: MlsPostKind
    public let body: MlsPostBody
    public let replyTo: String?
    public let mentions: [String]
    public let state: MlsPostState
    public init(logSeq: Int64?, postID: String, author: MlsAuthor?, appendedAt: Int64? = nil, kind: MlsPostKind = .text, body: MlsPostBody = .none, replyTo: String? = nil, mentions: [String] = [], state: MlsPostState = .sent) {
        self.logSeq = logSeq; self.postID = postID; self.author = author; self.appendedAt = appendedAt; self.kind = kind; self.body = body; self.replyTo = replyTo; self.mentions = mentions; self.state = state
    }
    public var description: String { "MlsPost" }
    public var debugDescription: String { description }
}

public struct MlsHistoryPage: Equatable, Sendable {
    public let posts: [MlsPost]
    public let floorLogSeq: Int64
    public let lastLogSeq: Int64
    public let more: Bool
    public init(posts: [MlsPost], floorLogSeq: Int64, lastLogSeq: Int64, more: Bool) { self.posts = posts; self.floorLogSeq = floorLogSeq; self.lastLogSeq = lastLogSeq; self.more = more }
}

/// The state a `group.send` reply (or a `post_state` event) reports.
public enum MlsSendState: Equatable, Sendable {
    case sent(logSeq: Int64)
    case queued(MlsQueueReason)
    case delayed(sendAfter: Int64, delaySeconds: Int)
    case rateLimited(MlsQuota)
    case failed(String)
    case unknown(String)
}

public struct MlsSendReceipt: Equatable, Sendable {
    public let postID: String
    public let state: MlsSendState
    public init(postID: String, state: MlsSendState) { self.postID = postID; self.state = state }
}

/// A committed `group.leave`.
public struct MlsCommit: Equatable, Sendable {
    public let logSeq: Int64?
    public init(logSeq: Int64?) { self.logSeq = logSeq }
}

/// `group.message.delete` (r4 item 10): written (`deleted`), or queued / delayed like a send. The final truth is `post_deleted`.
public enum MlsDeleteOutcome: Equatable, Sendable {
    case deleted(logSeq: Int64?)
    case queued(MlsQueueReason)
    case delayed(sendAfter: Int64)
    case unknown(String)
}

/// The typed refusals of every M2 method (error frame `error.code` and `error.details`). `unavailable` is the native
/// repository before the pin; it is never retried.
public enum MlsGroupError: Error, Equatable, Sendable {
    case notMember, notAdmin, ownerProtected, tierUnavailable, groupFull
    /// `not_admin{required: owner}` (M3): the action is the owner's.
    case notOwner
    case paced(retryAt: Int64?)
    case rateLimited
    case rejoinNeeded
    case tooLarge(maxBytes: Int?)
    case hostUnreachable
    case unknownInvite, requestNotFound, messageNotFound, notAuthor
    /// `void_not_head{head_log_seq}` (M3).
    case voidNotHead(headLogSeq: Int64?)
    case unavailable
    case offline
    case generic(String?)
}

/// A `join_result` event (assumed shape, Q4).
public struct MlsJoinEvent: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum Outcome: Equatable, Sendable { case joined, refused(MlsJoinRefusal) }
    public let requestID: String
    public let groupID: String?
    public let outcome: Outcome
    public init(requestID: String, groupID: String?, outcome: Outcome) { self.requestID = requestID; self.groupID = groupID; self.outcome = outcome }
    public var description: String { "MlsJoinEvent" }
    public var debugDescription: String { description }
}

/// The `group.event` kinds M2 acts on; anything else is skipped without logging the payload.
public enum MlsGroupEvent: Equatable, Sendable {
    /// `read`: the read position moved (`group.mark_read`).
    case read(groupID: String, readLogSeq: Int64, unread: Int, unreadMentions: Int)
    case post(groupID: String, seq: Int64?, at: Int64?, post: MlsPost)
    case postState(groupID: String, postID: String, state: MlsPostState, logSeq: Int64?)
    case postDeleted(groupID: String, postID: String, postLogSeq: Int64?, logSeq: Int64?)
    case membership(groupID: String, seq: Int64?, at: Int64?, post: MlsPost)
    case settings(groupID: String, seq: Int64?, at: Int64?, post: MlsPost)
    case joinResult(MlsJoinEvent)
    /// M3: a request arrived for an approval group (admins only act on it).
    case pendingJoin(groupID: String, seq: Int64?, request: MlsJoinRequest)
    case catchUp(groupID: String, seq: Int64?, state: MlsCatchUp)
    case warning(groupID: String, seq: Int64?, warning: MlsWarning)
    case ignored
}

/// Why a group is read-only (S13): the composer is removed and neither `group.send` nor `group.read` is called.
/// `group.refresh` rows.
public struct MlsRefreshRow: Equatable, Sendable { public let groupID: String; public let lastLogSeq: Int64; public let newPosts: Int; public init(groupID: String, lastLogSeq: Int64, newPosts: Int) { self.groupID = groupID; self.lastLogSeq = lastLogSeq; self.newPosts = newPosts } }

public enum MlsReadOnly: Equatable, Sendable { case left, removed, banned }

extension MlsGroupInfo {
    /// A copy with the fields a local event or an own action moves.
    func with(lastLogSeq: Int64? = nil, lastActivityAt: Int64? = nil, unread: Int? = nil, unreadMentions: Int? = nil, readLogSeq: Int64? = nil, name: String? = nil, approval: Bool? = nil, push: MlsPush? = nil, myRole: MlsRole? = nil, catchUp: MlsCatchUp? = nil, warnings: [MlsWarning]? = nil, postQuota: MlsQuota? = nil, commitQuota: MlsQuota? = nil, members: Int? = nil) -> MlsGroupInfo {
        MlsGroupInfo(groupID: groupID, name: name ?? self.name, tier: tier, members: members ?? self.members, leaves: leaves, agents: agents, approval: approval ?? self.approval, myRole: myRole ?? self.myRole, hostNode: hostNode, push: push ?? self.push, catchUp: catchUp ?? self.catchUp, privacyDelay: privacyDelay, postQuota: postQuota ?? self.postQuota, commitQuota: commitQuota ?? self.commitQuota, lastLogSeq: lastLogSeq ?? self.lastLogSeq, warnings: warnings ?? self.warnings, lastActivityAt: lastActivityAt ?? self.lastActivityAt, unread: unread ?? self.unread, unreadMentions: unreadMentions ?? self.unreadMentions, readLogSeq: readLogSeq ?? self.readLogSeq, lastPost: lastPost)
    }
}

// MARK: M3 (admin and edge states)

/// One join request of `group.requests.list` or a `pending_join` event. The request id and the anchor are never printed or logged (A13).
public struct MlsJoinRequest: Equatable, Sendable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var id: String { requestID }
    public let requestID: String
    public let anchor: String
    /// Nil for a non-contact: the screen shows "Member", never the anchor.
    public let display: String?
    public let aiFlag: Bool
    public let requestedAt: Int64
    public let expiresAt: Int64
    public init(requestID: String, anchor: String, display: String? = nil, aiFlag: Bool = false, requestedAt: Int64 = 0, expiresAt: Int64 = 0) { self.requestID = requestID; self.anchor = anchor; self.display = display; self.aiFlag = aiFlag; self.requestedAt = requestedAt; self.expiresAt = expiresAt }
    public var description: String { "MlsJoinRequest" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["aiFlag": aiFlag, "requestedAt": requestedAt, "expiresAt": expiresAt], displayStyle: .struct) }
    public func isExpired(now: Int64) -> Bool { expiresAt > 0 && expiresAt <= now }
}

public struct MlsRequestsPage: Equatable, Sendable {
    public let rows: [MlsJoinRequest]
    public let cursor: String?
    public init(rows: [MlsJoinRequest], cursor: String?) { self.rows = rows; self.cursor = cursor }
}

/// The commit-producing admin actions (common 3.1). Decline, push and skip are not in this list: they produce no commit.
public enum MlsAdminKind: Equatable, Sendable { case approve, role, remove, ban, settings, void }

public enum MlsSettingField: Equatable, Sendable { case name, approval }

/// What an admin action is aimed at. Request ids and anchors are redacted in every debug output (A13).
public enum MlsAdminTarget: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case request(String), member(String), setting(MlsSettingField), logSeq(Int64)
    public var description: String { "MlsAdminTarget" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .enum) }
}

/// The reply of an admin write: `{state: committed, log_seq}` or, for a decline, `{state: declined}`.
public enum MlsAdminOutcome: Equatable, Sendable {
    case committed(logSeq: Int64?)
    case declined
}

/// The reply of `group.catch_up{skip: true}`.
public enum MlsCatchUpResult: Equatable, Sendable {
    case rejoining
    case running(done: Int, total: Int)
    case idle
}

/// The newest value of a refusal the screens show once (a toast or a line), with the kind of action it came from.
public struct MlsAdminNotice: Equatable, Sendable {
    public let error: MlsGroupError
    /// `request_not_found` on an approve or decline: the row is gone and a toast says so.
    public let isToast: Bool
    /// The commit-producing action it came from (the chat shows only a void refusal).
    public let kind: MlsAdminKind?
    public init(error: MlsGroupError, isToast: Bool = false, kind: MlsAdminKind? = nil) { self.error = error; self.isToast = isToast; self.kind = kind }
}
