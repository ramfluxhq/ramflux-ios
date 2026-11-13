// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import RamfluxCore
@testable import AppData
@Suite(.timeLimit(.minutes(1))) struct GroupsRepositoryTests {
    private func transport(excludeOwner: Bool = false, expiredRequest: Bool = false) -> ProxyTransport {
        ProxyTransport { request in
            if request.method == "account.status" { return .object(["principal_id": .string("owner"), "principal_commitment": .string("root-owner"), "device_id": .string("phone"), "local_device_authorized": .bool(true), "authority_blocked": .bool(false)]) }
            let roster: JSONValue = .array([
                .object(["identity": .object(["principal_id": .string("owner"), "root_commitment": .string("root-owner"), "device_id": .string("phone"), "signing_public_key": .string("owner-key"), "target_delivery_id": .string("owner-target")]), "role": .string("owner"), "joined_epoch": .unsigned(1)]),
                .object(["identity": .object(["principal_id": .string("peer"), "root_commitment": .string("root-peer"), "device_id": .string("peer-phone"), "signing_public_key": .string("peer-key"), "target_delivery_id": .string("peer-target")]), "role": .string("member"), "joined_epoch": .unsigned(2)]),
            ])
            let row: JSONValue = .object(["group_id": .string("g"), "name": .string("Group"), "group_epoch": .unsigned(UInt64.max), "max_members": .number(256), "new_member_history": .string("since_join"), "name_epoch": .unsigned(9), "members": .array([.string("phone"), .string("peer-phone")]), "roles": .object(["phone": .string("owner"), "peer-phone": .string("member")]), "member_roster": roster, "excluded_devices": .array(excludeOwner ? [.object(["root_commitment": .string("root-owner"), "device_id": .string("phone")])] : [])])
            switch request.method {
            case "group.list": return .object(["groups": .array([row])])
            case "group.members": return row
            case "group.history":
                #expect(request.body["group_id"] == .string("g")); #expect(request.body["conversation_id"] == .string("g")); #expect(request.body["limit"] == .number(0))
                return .object(["group_id": .string("g"), "conversation_id": .string("canonical-g-thread"), "metadata": row, "messages": .array([]), "decrypted_messages": .array([])])
            case "group.name.set":
                if expiredRequest { return .object(["group_id": .string("g"), "accepted": .bool(false), "pending": .bool(false), "status": .string("expired"), "request_id": .string("expired-request")]) }
                #expect(request.body["name"] == .string("New name")); #expect(request.operationID?.rawValue == "rename")
                return .object(["group_id": .string("g"), "accepted": .bool(true), "pending": .bool(true), "request_id": .string("owner-request")])
            case "group.role.set":
                #expect(request.body["member_id"] == .string("peer-phone")); #expect(request.body["member_principal_commitment"] == .string("root-peer")); #expect(request.body["role"] == .string("admin"))
                return .object(["group_id": .string("g"), "accepted": .bool(true)])
            default: return .object([:])
            }
        }
    }
    @Test func exactEpochRootQualifiedTargetAndPendingOwnerOutcomeArePreserved() async {
        let fixture = transport(), client = RamfluxClient(transport: transport())
        let repository = NativeGroupsRepository(client: RamfluxClient(transport: fixture), updates: NativeUpdateSource(client: client))
        guard case .success(let detail) = await repository.detail(account: "a", group: "g") else { Issue.record("Detail mapping failed"); return }
        #expect(detail.group.epoch == UInt64.max); #expect(detail.canManage)
        #expect(await repository.conversation(account: "a", group: "g") == .success("canonical-g-thread"))
        let stale = await repository.mutate(account: "a", mutation: .rename(group: "g", epoch: 1, name: "Stale"), operationID: "stale")
        #expect(stale == .failure(.invalidInput)); #expect(!fixture.calls.withLock { $0.contains { $0.method == "group.name.set" } })
        let rename = await repository.mutate(account: "a", mutation: .rename(group: "g", epoch: UInt64.max, name: "New name"), operationID: "rename")
        #expect(rename == .success(GroupMutationOutcome(groupID: "g", waitingForOwner: true, requestID: "owner-request")))
        guard let peer = detail.roster.first(where: { $0.root == "root-peer" }) else { Issue.record("Peer absent"); return }
        #expect(await repository.mutate(account: "a", mutation: .role(group: "g", epoch: UInt64.max, member: peer, role: "admin"), operationID: "role") == .success(GroupMutationOutcome(groupID: "g", waitingForOwner: false)))
        let replaced = GroupMemberRecord(principal: "peer", root: "replaced-root", device: peer.device, role: "member")
        #expect(await repository.mutate(account: "a", mutation: .remove(group: "g", epoch: UInt64.max, member: replaced), operationID: "replaced") == .failure(.invalidInput))
    }
    @Test func expiredOwnerRequestIsTerminalWithoutClaimingAppliedPermissions() async {
        let fixture = transport(expiredRequest: true), client = RamfluxClient(transport: transport())
        let repository = NativeGroupsRepository(client: RamfluxClient(transport: fixture), updates: NativeUpdateSource(client: client))
        #expect(await repository.mutate(account: "a", mutation: .rename(group: "g", epoch: UInt64.max, name: "New name"), operationID: "expired") == .success(GroupMutationOutcome(groupID: "g", waitingForOwner: false, requestID: "expired-request", expired: true)))
        #expect(await repository.pending(account: "a") == nil)
    }
    @Test func excludedOwnerDeviceCannotAuthorizeManagement() async {
        let fixture = transport(excludeOwner: true), client = RamfluxClient(transport: transport())
        let repository = NativeGroupsRepository(client: RamfluxClient(transport: fixture), updates: NativeUpdateSource(client: client))
        guard case .success(let detail) = await repository.detail(account: "a", group: "g") else { Issue.record("Detail mapping failed"); return }
        #expect(!detail.canManage); #expect(detail.ownRole == nil)
        #expect(await repository.mutate(account: "a", mutation: .rename(group: "g", epoch: UInt64.max, name: "New name"), operationID: "blocked") == .failure(repository.unavailable(.managementPermission)))
        #expect(!fixture.calls.withLock { $0.contains { $0.method == "group.name.set" } })
    }
}
