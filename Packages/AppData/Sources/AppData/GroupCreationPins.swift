// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
/// A retained create key cannot be retried under a replaced local account authority.
actor GroupCreationPins {
    private var pins: [String: (operation: String, principal: String, root: String)] = [:]
    func admit(account: String, operation: String, principal: String, root: String) throws -> Bool {
        if let pin = pins[account], pin.operation == operation { return pin.principal == principal && pin.root == root }
        guard pins[account] != nil || pins.count < 4096 else { throw AppFailure.busy }
        pins[account] = (operation, principal, root); return true
    }
}
