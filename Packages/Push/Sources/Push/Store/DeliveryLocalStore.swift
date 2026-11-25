// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import CryptoKit
import Foundation

/// Small state shared by the app and the extension, in the App Group's defaults suite. Keys are salted hashes
/// of the account id; values are statuses, times and counters: no ids, tokens or route tags.
public final class DeliveryLocalStore: @unchecked Sendable {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults) { self.defaults = defaults }
    public convenience init?(info: [String: Any]? = Bundle.main.infoDictionary) {
        guard let group = SharedContainer.appGroup(info: info), let defaults = UserDefaults(suiteName: group) else { return nil }
        self.init(defaults: defaults)
    }
    private var salt: String {
        if let saved = defaults.string(forKey: "delivery.salt") { return saved }
        let fresh = (0..<16).map { _ in String(UInt8.random(in: 0...255), radix: 16) }.joined()
        defaults.set(fresh, forKey: "delivery.salt"); return fresh
    }
    private func digest(_ value: String) -> String {
        SHA256.hash(data: Data((salt + value).utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
    public func status(account: String) -> DeliveryStatus {
        defaults.string(forKey: "delivery.status." + digest(account)).flatMap(DeliveryStatus.init(rawValue:)) ?? .pending
    }
    public func setStatus(_ status: DeliveryStatus, account: String) { defaults.set(status.rawValue, forKey: "delivery.status." + digest(account)) }
    /// Records the token's salted hash; true when it differs from the one recorded before.
    public func tokenChanged(_ token: String, account: String) -> Bool {
        let key = "delivery.token." + digest(account), hash = digest(token)
        defer { defaults.set(hash, forKey: key) }
        return defaults.string(forKey: key) != hash
    }
    public func forget(account: String) {
        defaults.removeObject(forKey: "delivery.status." + digest(account)); defaults.removeObject(forKey: "delivery.token." + digest(account))
    }
}
