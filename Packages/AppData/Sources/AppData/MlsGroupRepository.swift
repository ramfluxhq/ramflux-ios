// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// The M2 group calls (method table r4). One async method per call with a typed result. Nothing here retries, and
/// nothing logs a link, a name or a body. Only `MlsGroupSession` calls these, so an outcome never depends on a view.
public protocol MlsGroupRepository: Sendable {
    func list(account: String, cursor: String?, limit: Int) async -> Result<MlsGroupPage, MlsGroupError>
    func info(account: String, groupID: String) async -> Result<MlsGroupInfo, MlsGroupError>
    func create(account: String, name: String, approval: Bool) async -> Result<MlsCreated, MlsGroupError>
    func inviteCreate(account: String, groupID: String, maxUses: Int, ttlSeconds: Int) async -> Result<MlsInvite, MlsGroupError>
    func inviteList(account: String, groupID: String) async -> Result<[MlsInvite], MlsGroupError>
    func inviteRevoke(account: String, groupID: String, inviteID: String) async -> Result<Void, MlsGroupError>
    func join(account: String, link: String) async -> Result<MlsJoinResult, MlsGroupError>
    /// `group.join.pending{}`: the requests still waiting, read from the local account database.
    func joinPending(account: String) async -> Result<[MlsPendingJoin], MlsGroupError>
    func members(account: String, groupID: String, cursor: String?, limit: Int) async -> Result<MlsMemberPage, MlsGroupError>
    func send(account: String, groupID: String, text: String, replyTo: String?, mentions: [String]) async -> Result<MlsSendReceipt, MlsGroupError>
    func history(account: String, groupID: String, afterLogSeq: Int64?, beforeLogSeq: Int64?, limit: Int) async -> Result<MlsHistoryPage, MlsGroupError>
    /// `group.refresh`: fetch from the host now. Results arrive as events; it marks nothing read.
    func refresh(account: String, groupID: String?) async -> Result<[MlsRefreshRow], MlsGroupError>
    func markRead(account: String, groupID: String, logSeq: Int64) async -> Result<MlsReadState, MlsGroupError>
    func deleteMessage(account: String, groupID: String, postID: String) async -> Result<MlsDeleteOutcome, MlsGroupError>
    func leave(account: String, groupID: String) async -> Result<MlsCommit, MlsGroupError>
    /// `group.event` frames of the account, parsed. The stream finishes with the hub.
    func events(account: String) -> AsyncStream<MlsGroupEvent>
}

/// The repository of a build that has no group SDK: every call is the typed unavailable outcome.
public struct UnavailableMlsGroupRepository: MlsGroupRepository {
    public init() {}
    public func list(account: String, cursor: String?, limit: Int) async -> Result<MlsGroupPage, MlsGroupError> { .failure(.unavailable) }
    public func info(account: String, groupID: String) async -> Result<MlsGroupInfo, MlsGroupError> { .failure(.unavailable) }
    public func create(account: String, name: String, approval: Bool) async -> Result<MlsCreated, MlsGroupError> { .failure(.unavailable) }
    public func inviteCreate(account: String, groupID: String, maxUses: Int, ttlSeconds: Int) async -> Result<MlsInvite, MlsGroupError> { .failure(.unavailable) }
    public func inviteList(account: String, groupID: String) async -> Result<[MlsInvite], MlsGroupError> { .failure(.unavailable) }
    public func inviteRevoke(account: String, groupID: String, inviteID: String) async -> Result<Void, MlsGroupError> { .failure(.unavailable) }
    public func join(account: String, link: String) async -> Result<MlsJoinResult, MlsGroupError> { .failure(.unavailable) }
    public func joinPending(account: String) async -> Result<[MlsPendingJoin], MlsGroupError> { .failure(.unavailable) }
    public func members(account: String, groupID: String, cursor: String?, limit: Int) async -> Result<MlsMemberPage, MlsGroupError> { .failure(.unavailable) }
    public func send(account: String, groupID: String, text: String, replyTo: String?, mentions: [String]) async -> Result<MlsSendReceipt, MlsGroupError> { .failure(.unavailable) }
    public func history(account: String, groupID: String, afterLogSeq: Int64?, beforeLogSeq: Int64?, limit: Int) async -> Result<MlsHistoryPage, MlsGroupError> { .failure(.unavailable) }
    public func refresh(account: String, groupID: String?) async -> Result<[MlsRefreshRow], MlsGroupError> { .failure(.unavailable) }
    public func markRead(account: String, groupID: String, logSeq: Int64) async -> Result<MlsReadState, MlsGroupError> { .failure(.unavailable) }
    public func deleteMessage(account: String, groupID: String, postID: String) async -> Result<MlsDeleteOutcome, MlsGroupError> { .failure(.unavailable) }
    public func leave(account: String, groupID: String) async -> Result<MlsCommit, MlsGroupError> { .failure(.unavailable) }
    public func events(account: String) -> AsyncStream<MlsGroupEvent> { AsyncStream { $0.finish() } }
}

/// The native repository. Five method names (`group.history`, `.leave`, `.members`, `.read`, `.send`) exist at the
/// current pin with the old sender-key shapes and the rest do not exist, so until the pin batch (W) every call is the
/// typed unavailable outcome and nothing is sent to the SDK. Only `events` is live: it filters the hub's `group.event`
/// frames.
public struct NativeMlsGroupRepository: MlsGroupRepository {
    private let updates: NativeUpdateSource?
    /// `updates` is nil in the gallery's unavailable fixture (F2-11): there is no hub, so `events` ends at once.
    public init(updates: NativeUpdateSource? = nil) { self.updates = updates }
    public func list(account: String, cursor: String?, limit: Int) async -> Result<MlsGroupPage, MlsGroupError> {
        // W: SDKOperation.groupList after the pin, body {cursor?, limit}; parse with MlsGroupParsing.list.
        .failure(.unavailable)
    }
    public func info(account: String, groupID: String) async -> Result<MlsGroupInfo, MlsGroupError> {
        // W: SDKOperation.groupInfo after the pin, body {group_id}; parse with MlsGroupParsing.info.
        .failure(.unavailable)
    }
    public func create(account: String, name: String, approval: Bool) async -> Result<MlsCreated, MlsGroupError> {
        // W: SDKOperation.groupCreate after the pin, body {name, tier: 1000, approval}; parse with MlsGroupParsing.created.
        .failure(.unavailable)
    }
    public func inviteCreate(account: String, groupID: String, maxUses: Int, ttlSeconds: Int) async -> Result<MlsInvite, MlsGroupError> {
        // W: SDKOperation.groupInviteCreate after the pin, body {group_id, max_uses, ttl_s}; parse with MlsGroupParsing.invite.
        .failure(.unavailable)
    }
    public func inviteList(account: String, groupID: String) async -> Result<[MlsInvite], MlsGroupError> {
        // W: SDKOperation.groupInviteList after the pin, body {group_id}; parse with MlsGroupParsing.invites.
        .failure(.unavailable)
    }
    public func inviteRevoke(account: String, groupID: String, inviteID: String) async -> Result<Void, MlsGroupError> {
        // W: SDKOperation.groupInviteRevoke after the pin, body {group_id, invite_id}; refusals through MlsGroupParsing.error.
        .failure(.unavailable)
    }
    public func join(account: String, link: String) async -> Result<MlsJoinResult, MlsGroupError> {
        // W: SDKOperation.groupJoin after the pin, body {link} passed verbatim; parse with MlsGroupParsing.join.
        .failure(.unavailable)
    }
    public func joinPending(account: String) async -> Result<[MlsPendingJoin], MlsGroupError> {
        // W: SDKOperation.groupJoinPending after the pin, body {}; parse with MlsGroupParsing.pendingJoins.
        .failure(.unavailable)
    }
    public func members(account: String, groupID: String, cursor: String?, limit: Int) async -> Result<MlsMemberPage, MlsGroupError> {
        // W: SDKOperation.groupMembers is the old shape at the pin; use the new one after it, body {group_id, cursor?, limit}; parse with MlsGroupParsing.members.
        .failure(.unavailable)
    }
    public func send(account: String, groupID: String, text: String, replyTo: String?, mentions: [String]) async -> Result<MlsSendReceipt, MlsGroupError> {
        // W: SDKOperation.groupSend is the old shape at the pin; use the new one after it, body {group_id, text, reply_to?, mentions}; parse with MlsGroupParsing.send.
        .failure(.unavailable)
    }
    public func history(account: String, groupID: String, afterLogSeq: Int64?, beforeLogSeq: Int64?, limit: Int) async -> Result<MlsHistoryPage, MlsGroupError> {
        // W: SDKOperation.groupHistory is the old shape at the pin; use the new one after it, body {group_id, after_log_seq? | before_log_seq?, limit}; parse with MlsGroupParsing.history.
        .failure(.unavailable)
    }
    public func refresh(account: String, groupID: String?) async -> Result<[MlsRefreshRow], MlsGroupError> {
        // W: SDKOperation.groupRefresh after the pin (renamed from group.read), body {group_id?}; parse with MlsGroupParsing.refresh.
        .failure(.unavailable)
    }
    public func markRead(account: String, groupID: String, logSeq: Int64) async -> Result<MlsReadState, MlsGroupError> {
        // W: SDKOperation.groupMarkRead after the pin, body {group_id, log_seq}; parse with MlsGroupParsing.readState.
        .failure(.unavailable)
    }
    public func deleteMessage(account: String, groupID: String, postID: String) async -> Result<MlsDeleteOutcome, MlsGroupError> {
        // W: SDKOperation.groupMessageDelete after the pin, body {group_id, post_id}; parse with MlsGroupParsing.deleteOutcome.
        .failure(.unavailable)
    }
    public func leave(account: String, groupID: String) async -> Result<MlsCommit, MlsGroupError> {
        // W: SDKOperation.groupLeave is the old shape at the pin; use the new one after it, body {group_id}; parse with MlsGroupParsing.commit.
        .failure(.unavailable)
    }
    public func events(account: String) -> AsyncStream<MlsGroupEvent> {
        let (stream, continuation) = AsyncStream<MlsGroupEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        guard let updates else { continuation.finish(); return stream }
        let pump = Task {
            let hub = await updates.observe(account: account, eventFrames: true)
            if let events = hub.events {
                for await frame in events where frame.topic == NativeUpdateSource.groupEventTopic {
                    guard let body = try? JSONDecoder().decode(JSONValue.self, from: frame.body) else { continue }
                    let event = MlsGroupParsing.event(body)
                    if event != .ignored { continuation.yield(event) }
                }
            }
            await hub.stop(); continuation.finish()
        }
        continuation.onTermination = { _ in pump.cancel() }
        return stream
    }
}
