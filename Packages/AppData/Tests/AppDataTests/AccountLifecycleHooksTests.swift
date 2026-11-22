// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Synchronization
import Testing
import RamfluxCore
@testable import AppData
struct AccountLifecycleHooksTests {
    @Test func lockNotifiesRegisteredStoresBeforeTheSDKCall() async {
        let order = Mutex<[String]>([])
        let transport = ProxyTransport { request in order.withLock { $0.append(request.method) }; return .object([:]) }
        let hooks = AccountLifecycleHooks()
        let token = hooks.register { event in if case .willLock(let account) = event { order.withLock { $0.append("purge:" + account) } } }
        let repo = NativeSettingsRepository(client: RamfluxClient(transport: transport), nodes: UnavailableNodeRepository(),
                                            updates: NativeUpdateSource(client: RamfluxClient(transport: transport)), lifecycle: hooks)
        _ = await repo.lock(account: "a")
        #expect(order.withLock { $0 } == ["purge:a", "account.lock"])
        hooks.unregister(token); _ = await repo.lock(account: "a")
        #expect(order.withLock { $0 }.filter { $0.hasPrefix("purge") }.count == 1)
    }
}
