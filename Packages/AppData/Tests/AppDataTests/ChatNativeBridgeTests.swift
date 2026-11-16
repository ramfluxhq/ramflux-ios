// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import Foundation
import RamfluxCore
@testable import AppData

#if RF_NATIVE_SDK
@Suite(.timeLimit(.minutes(1))) struct ChatNativeBridgeTests {
    @Test func bothDeleteScopesReachThePinnedSdkAndAreRefused() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rf-ios-chat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let core = try NativeCore(dataRoot: root, custody: HostCustodyProvider())
        let client = RamfluxClient(transport: core)
        try await client.start()
        for scope in [MessageDeleteScope.local, MessageDeleteScope.everyone] {
            let repo = NativeChatRepository(client: client, updates: NativeUpdateSource(client: client))
            let operation = "sdk-delete-\(scope.rawValue)-0123456789"
            let result = await repo.delete(account: "missing-account", conversation: "conversation", message: "message", scope: scope, operationID: operation)
            guard case .failure(let error) = result else {
                Issue.record("delete \(scope.rawValue) succeeded without a live account")
                continue
            }
            #expect(error == .outcomeUnknown)
            let pending = await repo.mutationState(account: "missing-account", conversation: "conversation")
            #expect(pending?.unresolved == true)
            #expect(pending?.operationID == operation)
            #expect(pending?.key.scope == scope.rawValue)
        }
        try await client.close()
    }
}
#endif
