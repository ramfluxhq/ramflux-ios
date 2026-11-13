// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public protocol GroupsRepository: Sendable {
    func list(account: String) async -> RepositoryResult<[GroupRecord]>
    func conversation(account: String, group: String) async -> RepositoryResult<String>
    func detail(account: String, group: String) async -> RepositoryResult<GroupDetail>
    func invitations(account: String) async -> RepositoryResult<[GroupInvitation]>
    func requests(account: String, group: String) async -> RepositoryResult<[GroupRequestRecord]>
    func pending(account: String) async -> PendingGroupMutation?
    func mutate(account: String, mutation: GroupMutation, operationID: String) async -> RepositoryResult<GroupMutationOutcome>
    func observe(account: String) async -> RepositoryObservation
    func unavailable(_ capability: GroupUnavailable) -> AppFailure
}
public struct NativeGroupsRepository: GroupsRepository {
    private let gateway: ProxyGateway
    private let updates: NativeUpdateSource
    private let creationPins = GroupCreationPins()
    private let mutations = RetainedMutation<GroupMutation, GroupMutationOutcome>()
    public init(client: RamfluxClient, updates: NativeUpdateSource) { gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.updates = updates }
    public func list(account: String) async -> RepositoryResult<[GroupRecord]> {
        do {
            let rows = try ProxyGateway.rows(await gateway.call(.groupList, account: account), "groups").map(Self.record)
            guard Set(rows.map(\.id)).count == rows.count else { throw AppFailure.invalidData }; return .success(rows)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func conversation(account: String, group: String) async -> RepositoryResult<String> {
        do {
            let body = try await gateway.call(.groupHistory, account: account, body: .object(["group_id": .string(group), "conversation_id": .string(group), "limit": .number(0)]))
            guard body["group_id"] == .string(group) else { throw AppFailure.invalidData }
            return .success(try ProxyGateway.text(body, "conversation_id"))
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func detail(account: String, group: String) async -> RepositoryResult<GroupDetail> {
        do {
            let status = try await gateway.call(.accountStatus, account: account)
            let value = try await gateway.call(.groupMembers, account: account, body: .object(["group_id": .string(group)]))
            let record = try Self.record(value); guard record.id == group else { throw AppFailure.invalidData }
            let roster: [GroupMemberRecord]
            if value["member_roster"] != nil {
                let exclusions = try ProxyGateway.rows(value, "excluded_devices")
                roster = try ProxyGateway.rows(value, "member_roster").map { row in
                    guard let identity = row["identity"] else { throw AppFailure.invalidData }
                    let role = try ProxyGateway.text(row, "role"); guard ["owner","admin","member","bot"].contains(role) else { throw AppFailure.invalidData }
                    let root = try ProxyGateway.text(identity, "root_commitment"), device = try ProxyGateway.text(identity, "device_id")
                    let excluded = exclusions.contains { $0["root_commitment"] == .string(root) && $0["device_id"] == .string(device) }
                    return GroupMemberRecord(principal: try ProxyGateway.text(identity, "principal_id"), root: root, device: device, role: role, isActive: !excluded && record.members.contains(device) && value["roles"]?[device]?.string == role)
                }
            } else {
                // Legacy display has no root-qualified authority. Render devices, withhold controls.
                roster = record.members.map { GroupMemberRecord(principal: "", root: nil, device: $0, role: value["roles"]?[$0]?.string ?? "") }
            }
            guard Set(roster.map(\.id)).count == roster.count else { throw AppFailure.invalidData }
            return .success(GroupDetail(group: record, roster: roster, ownRoot: try ProxyGateway.text(status, "principal_commitment"), ownDevice: try ProxyGateway.text(status, "device_id"), authorized: status["local_device_authorized"] == .bool(true) && status["authority_blocked"] != .bool(true)))
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func invitations(account: String) async -> RepositoryResult<[GroupInvitation]> {
        do {
            let rows = try ProxyGateway.rows(await gateway.call(.groupInvitationsList, account: account), "invitations").map { row in
                guard let expiry = ProxyGateway.integer(row["expires_at"]) else { throw AppFailure.invalidData }
                return GroupInvitation(id: try ProxyGateway.text(row, "group_id"), name: row["name"]?.string, creator: try ProxyGateway.text(row, "creator"), inviter: try ProxyGateway.text(row, "inviter"), expiresAt: expiry)
            }
            guard Set(rows.map(\.id)).count == rows.count else { throw AppFailure.invalidData }; return .success(rows)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func requests(account: String, group: String) async -> RepositoryResult<[GroupRequestRecord]> {
        do {
            let rows = try ProxyGateway.rows(await gateway.call(.groupRequestsList, account: account, body: .object(["group_id": .string(group)])), "requests").map { row in
                guard let waiting = row["waiting_for_owner"]?.bool, let expiry = ProxyGateway.integer(row["expires_at"]), row["group_id"] == .string(group) else { throw AppFailure.invalidData }
                return GroupRequestRecord(id: try ProxyGateway.text(row, "request_id"), groupID: group, status: try ProxyGateway.text(row, "status"), waitingForOwner: waiting, expiresAt: expiry)
            }
            guard Set(rows.map(\.id)).count == rows.count else { throw AppFailure.invalidData }; return .success(rows)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func pending(account: String) async -> PendingGroupMutation? {
        guard let entry = await mutations.snapshot(scope: account), entry.unresolved else { return nil }
        return PendingGroupMutation(mutation: entry.arguments, operationID: entry.operationID)
    }
    public func mutate(account: String, mutation: GroupMutation, operationID: String) async -> RepositoryResult<GroupMutationOutcome> {
        await mutations.run(scope: account, arguments: mutation, operationID: operationID) {
            do {
                let operation: SDKOperation
                var fields: [String: JSONValue] = ["group_id": .string(mutation.groupID)]
                switch mutation {
                case .create(let id, let name):
                    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 512 else { return .failure(.invalidInput) }
                    let status = try await gateway.call(.accountStatus, account: account)
                    guard status["local_device_authorized"] == .bool(true), status["authority_blocked"] != .bool(true) else { return .failure(.locked) }
                    let principal = try ProxyGateway.text(status, "principal_id"), root = try ProxyGateway.text(status, "principal_commitment")
                    guard try await creationPins.admit(account: account, operation: operationID, principal: principal, root: root) else { return .failure(.outcomeUnknown) }
                    fields["creator_id"] = .string(principal); fields["conversation_id"] = .string(id); fields["name"] = .string(name); operation = .groupCreate
                case .invitation(let invitation, let accept):
                    guard case .success(let current) = await invitations(account: account), current.contains(invitation), invitation.expiresAt > Int64(Date().timeIntervalSince1970) else { return .failure(.invalidData) }
                    operation = accept ? .groupInvitationAccept : .groupInvitationDecline
                default:
                    let detail: GroupDetail
                    switch await self.detail(account: account, group: mutation.groupID) { case .success(let value): detail = value; case .failure(let failure): return .failure(failure) }
                    guard detail.canManage else { return .failure(Self.refusal(.managementPermission)) }
                    switch mutation {
                    case .rename(_, let epoch, let name):
                        guard epoch == detail.group.epoch, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 512 else { return .failure(.invalidInput) }
                        fields["name"] = .string(name); operation = .groupNameSet
                    case .role(_, let epoch, let member, let role):
                        guard epoch == detail.group.epoch, detail.roster.contains(member), member.root != nil, member.isActive, !(member.device == detail.ownDevice && member.root == detail.ownRoot), member.role != "owner", ["admin","member"].contains(role) else { return .failure(.invalidInput) }
                        fields["member_id"] = .string(member.device); fields["member_principal_commitment"] = member.root.map(JSONValue.string); fields["role"] = .string(role); operation = .groupRoleSet
                    case .remove(_, let epoch, let member):
                        guard epoch == detail.group.epoch, detail.roster.contains(member), member.root != nil, member.isActive, !(member.device == detail.ownDevice && member.root == detail.ownRoot), member.role != "owner" else { return .failure(.invalidInput) }
                        fields["member_id"] = .string(member.device); fields["member_principal_commitment"] = member.root.map(JSONValue.string); operation = .groupMemberRemove
                    case .add(_, let epoch, let principal, let root):
                        guard epoch == detail.group.epoch, !principal.isEmpty, principal.utf8.count <= 2048, !root.isEmpty, root.utf8.count <= 1024 else { return .failure(.invalidInput) }
                        fields["member_id"] = .string(principal); fields["member_principal_commitment"] = .string(root); fields["role"] = .string("member"); operation = .groupMemberAdd
                    default: return .failure(.invalidInput)
                    }
                }
                let body = try await gateway.call(operation, account: account, body: .object(fields), operationID: operationID)
                guard body["group_id"] == .string(mutation.groupID) else { throw AppFailure.outcomeUnknown }
                if body["accepted"] == .bool(false), body["pending"] == .bool(false), body["status"] == .string("expired"), let request = body["request_id"]?.string, !request.isEmpty, request.utf8.count <= 65_536 {
                    return .success(GroupMutationOutcome(groupID: mutation.groupID, waitingForOwner: false, requestID: request, expired: true))
                }
                if case .invitation(_, let accept) = mutation {
                    guard body["accepted"] == .bool(accept), body["declined"] == .bool(!accept) else { throw AppFailure.outcomeUnknown }
                } else { guard body["accepted"] == .bool(true) else { throw AppFailure.outcomeUnknown } }
                if body["pending"] != nil, body["pending"]?.bool == nil { throw AppFailure.outcomeUnknown }
                if body["pending"] == .bool(true) {
                    guard let request = body["request_id"]?.string, !request.isEmpty, request.utf8.count <= 65_536 else { throw AppFailure.outcomeUnknown }
                    return .success(GroupMutationOutcome(groupID: mutation.groupID, waitingForOwner: true, requestID: request))
                }
                // Mutation acknowledgement is not a claim that member devices received state.
                return .success(GroupMutationOutcome(groupID: mutation.groupID, waitingForOwner: false))
            } catch { return .failure(AppFailure.map(error)) }
        }
    }
    public func observe(account: String) async -> RepositoryObservation { await updates.observe(account: account) }
    public func unavailable(_ capability: GroupUnavailable) -> AppFailure { Self.refusal(capability) }
    static func refusal(_ capability: GroupUnavailable) -> AppFailure {
        let key: String = switch capability { case .managementPermission: "groups.unavailable.permission"; case .threads: "groups.unavailable.threads"; case .ownershipTransfer: "groups.unavailable.transfer"; case .leave: "groups.unavailable.leave"; case .historyPolicy: "groups.unavailable.history"; case .archive: "groups.unavailable.archive" }
        return .unavailableResource(key)
    }
    private static func record(_ row: JSONValue) throws -> GroupRecord {
        let epoch: UInt64?
        switch row["group_epoch"] { case .unsigned(let value): epoch = value; case .number(let value): epoch = UInt64(exactly: value); case .string(let value): epoch = UInt64(value); default: epoch = nil }
        guard let epoch else { throw AppFailure.invalidData }
        let members = try ProxyGateway.rows(row, "members").map { value in guard let text = value.string, !text.isEmpty else { throw AppFailure.invalidData }; return text }
        guard Set(members).count == members.count else { throw AppFailure.invalidData }
        return GroupRecord(id: try ProxyGateway.text(row, "group_id"), name: row["name"]?.string, epoch: epoch, members: members)
    }
}
public struct UnavailableGroupsRepository: GroupsRepository {
    public func conversation(account: String, group: String) async -> RepositoryResult<String> { .failure(.sdkUnavailable) }
    public init() {}
    public func list(account: String) async -> RepositoryResult<[GroupRecord]> { .failure(.sdkUnavailable) }
    public func detail(account: String, group: String) async -> RepositoryResult<GroupDetail> { .failure(.sdkUnavailable) }
    public func invitations(account: String) async -> RepositoryResult<[GroupInvitation]> { .failure(.sdkUnavailable) }
    public func requests(account: String, group: String) async -> RepositoryResult<[GroupRequestRecord]> { .failure(.sdkUnavailable) }
    public func pending(account: String) async -> PendingGroupMutation? { nil }
    public func mutate(account: String, mutation: GroupMutation, operationID: String) async -> RepositoryResult<GroupMutationOutcome> { .failure(.sdkUnavailable) }
    public func observe(account: String) async -> RepositoryObservation { RepositoryObservation(failure: .sdkUnavailable) }
    public func unavailable(_ capability: GroupUnavailable) -> AppFailure { NativeGroupsRepository.refusal(capability) }
}
