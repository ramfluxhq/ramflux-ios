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
        _ = await repository.setRequestPolicy(account: "a", autoAccept: false, operationID: "manual")
        #expect(transport.calls.withLock { $0.last?.body["contact_requests"] } == .string("manual"))
        _ = await repository.setRequestPolicy(account: "a", autoAccept: true, operationID: "auto")
        #expect(transport.calls.withLock { $0.last?.body["contact_requests"] } == .string("auto_accept"))
    }
    @Test func changeCodeChecksBothCodesLocallyAndSendsThemAsSecrets() async {
        let transport = ProxyTransport { _ in .object(["rotated": .bool(true)]) }, client = RamfluxClient(transport: ProxyTransport { _ in .object([:]) })
        let repository = NativeSettingsRepository(client: RamfluxClient(transport: transport), nodes: UnavailableNodeRepository(), updates: NativeUpdateSource(client: client))
        let badCurrent = SensitiveSubmission(values: ["oldPassphrase": "12", "passphrase": "274915", "passphraseRepeat": "274915"], accountCode: .new)
        guard case .failure(.accountCode(.notSixDigits)) = await repository.changeCode(account: "a", credentials: badCurrent, operationID: "c1") else { Issue.record("malformed current code accepted"); return }
        let trivial = SensitiveSubmission(values: ["oldPassphrase": "274915", "passphrase": "000000", "passphraseRepeat": "000000"], accountCode: .new)
        guard case .failure(.accountCode(.trivial)) = await repository.changeCode(account: "a", credentials: trivial, operationID: "c2") else { Issue.record("trivial new code accepted"); return }
        #expect(transport.calls.withLock { $0.isEmpty })
        let valid = SensitiveSubmission(values: ["oldPassphrase": "274915", "passphrase": "592714", "passphraseRepeat": "592714"], accountCode: .new)
        guard case .success = await repository.changeCode(account: "a", credentials: valid, operationID: "c3") else { Issue.record("valid change refused"); return }
        #expect(transport.calls.withLock { $0.last?.method } == "account.passphrase.rotate")
    }
    @Test func attendedFrontendIsAnExplicitOptIn() throws {
        #expect(try SubscriptionFilter(topics: []).body["attended_frontend"] == nil)
        #expect(try SubscriptionFilter(topics: [], attendedFrontend: true).body["attended_frontend"] == .bool(true))
    }
}
