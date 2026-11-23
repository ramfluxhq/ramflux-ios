// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import Testing
import AppData
@testable import FeatureGroups
/// 50,000 groups behind the snapshot pager and one group with a 50,000-member roster.
private final class SyntheticGroups: GroupsRepository, Sendable {
    let reads = Mutex(0)
    private let pager = SnapshotPager<GroupRecord>()
    func list(account: String) async -> RepositoryResult<[GroupRecord]> {
        reads.withLock { $0 += 1 }
        return .success((0..<50_000).map { GroupRecord(id: String(format: "g%05d", $0), name: $0 % 100 == 0 ? "Hundred \($0)" : "Group \($0)", epoch: 1, members: []) })
    }
    func page(account: String, query: String, cursor: String?, limit: Int) async -> RepositoryResult<RowPage<GroupRecord>> {
        await pager.page(cursor: cursor, limit: limit, read: { await self.list(account: account) }, include: { GroupRecord.matches($0, query) })
    }
    func conversation(account: String, group: String) async -> RepositoryResult<String> { .success(group) }
    func detail(account: String, group: String) async -> RepositoryResult<GroupDetail> {
        let roster = (0..<50_000).map { GroupMemberRecord(principal: "p\($0)", root: "root\($0)", device: "d\($0)", role: $0 == 0 ? "owner" : "member") }
        return .success(GroupDetail(group: GroupRecord(id: group, name: "Big", epoch: 1, members: roster.map(\.device)), roster: roster, ownRoot: "root0", ownDevice: "d0", authorized: true))
    }
    func invitations(account: String) async -> RepositoryResult<[GroupInvitation]> { .success([]) }
    func requests(account: String, group: String) async -> RepositoryResult<[GroupRequestRecord]> { .success([]) }
    func pending(account: String) async -> PendingGroupMutation? { nil }
    func mutate(account: String, mutation: GroupMutation, operationID: String) async -> RepositoryResult<GroupMutationOutcome> { .failure(.unsupported) }
    func observe(account: String) async -> RepositoryObservation {
        let pair = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1)); pair.continuation.yield(.invalidated)
        return RepositoryObservation(stream: pair.stream, onStop: { pair.continuation.finish() })
    }
    func unavailable(_ capability: GroupUnavailable) -> AppFailure { .unsupported }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct GroupsWindowTests {
    @Test func fiftyThousandGroupsAndMembersRenderThroughBoundedWindows() async {
        let source = SyntheticGroups()
        let model = GroupsViewModel(repository: source, contacts: UnavailableContactsRepository(), account: "a", emit: { _ in })
        let clock = ContinuousClock()
        let first = await clock.measure { model.send(.refresh); await model.settle() }
        #expect(model.state.visibleGroups.count == 50); #expect(model.state.canLoadMore)
        var scroll = Duration.zero
        while model.state.canLoadMore { scroll += await clock.measure { model.send(.loadMore); await model.settle() }; #expect(model.state.groups.count <= 300) }
        #expect(model.state.groups.last?.id == "g49999")
        let filter = await clock.measure { model.send(.filter("Hundred")); await model.settle() }
        #expect(model.state.visibleGroups.count == 50); #expect(model.state.visibleGroups.allSatisfy { $0.name?.hasPrefix("Hundred") == true })
        model.send(.mode(.members("g00000"))); await model.settle()
        #expect(model.state.memberRows.count == 50); #expect(model.state.canLoadMoreMembers)
        var members = Duration.zero
        for _ in 0..<10 { members += await clock.measure { model.send(.loadMore); await model.settle() } }
        #expect(model.state.memberRows.count == 550); #expect(model.state.memberRows.first?.canManage == false); #expect(model.state.memberRows[1].canManage)
        print("GROUPS_50K first=\(first) scrollToEnd=\(scroll) filter=\(filter) members10Pages=\(members) listReads=\(source.reads.withLock { $0 })")
        model.send(.disappeared)
    }
}
