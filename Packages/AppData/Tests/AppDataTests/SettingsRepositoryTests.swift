// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import RamfluxCore
@testable import AppData

@Suite(.timeLimit(.minutes(1))) struct SettingsRepositoryTests {
    @Test func localDeviceAndInvalidRetentionNeverReachSDK() async {
        let transport = ProxyTransport { _ in .object([:]) }, client = RamfluxClient(transport: ProxyTransport { _ in .object([:]) })
        let repository = NativeSettingsRepository(client: RamfluxClient(transport: transport), nodes: UnavailableNodeRepository(), updates: NativeUpdateSource(client: client))
        guard case .failure(.invalidInput) = await repository.revoke(account: "a", device: DeviceRecord(id: "local", isLocal: true, capabilities: []), operationID: "key") else { Issue.record("Local device revoke was not refused"); return }
        guard case .failure(.invalidInput) = await repository.retention(account: "a", seconds: 1, operationID: "key") else { Issue.record("Invalid retention was not refused"); return }
        #expect(transport.calls.withLock { $0.isEmpty })
        _ = await repository.requireManualRequests(account: "a", operationID: "manual")
        #expect(transport.calls.withLock { $0.last?.body["contact_requests"] } == .string("manual"))
    }
    @Test func attendedFrontendIsAnExplicitOptIn() throws {
        #expect(try SubscriptionFilter(topics: []).body["attended_frontend"] == nil)
        #expect(try SubscriptionFilter(topics: [], attendedFrontend: true).body["attended_frontend"] == .bool(true))
    }
}
