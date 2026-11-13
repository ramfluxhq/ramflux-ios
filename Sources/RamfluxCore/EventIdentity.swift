// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
struct EventIdentity: Sendable {
    let generation: UInt64
    let accountID: String?
    init(snapshot: JSONValue, accountID: String?) throws {
        guard let text = snapshot["subscription_generation"]?.string,
              let generation = UInt64(text), generation != 0, String(generation) == text else {
            throw BridgeError.invalidResponse
        }
        self.generation = generation; self.accountID = accountID
    }
    func accepts(_ frame: JSONValue) -> Bool {
        guard frame["subscription_generation"] == .string(String(generation)) else { return false }
        return accountID == nil || frame["account_id"] == .string(accountID ?? "")
    }
}
