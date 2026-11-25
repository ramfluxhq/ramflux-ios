// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// The route map of this device, `push/routes.json` in the App Group container: `{route_tag: account_id}`. The
/// app writes it and the notification extension reads it. One tag per account; the file has the data root's file
/// protection (readable after the first unlock since boot). Tags and account ids are never logged.
public final class RouteRegistry: @unchecked Sendable {
    private let file: URL
    private let lock = NSLock()
    public init(container: URL) { file = container.appendingPathComponent("push", isDirectory: true).appendingPathComponent("routes.json") }
    public convenience init?(info: [String: Any]? = Bundle.main.infoDictionary) {
        guard let container = SharedContainer.containerURL(info: info) else { return nil }
        self.init(container: container)
    }
    /// The tag of `account`, created when it has none.
    public func ensureTag(for account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        var map = read()
        if let existing = map.first(where: { $0.value == account })?.key { return existing }
        guard let tag = RouteTag.make() else { return nil }
        map[tag] = account
        return write(map) ? tag : nil
    }
    /// Any one tag of the map; used by the Debug injector to address a wake to this device's own account.
    public func anyTag() -> String? { lock.lock(); defer { lock.unlock() }; return read().keys.sorted().first }
    public func account(for tag: String) -> String? { lock.lock(); defer { lock.unlock() }; return read()[tag] }
    public func remove(account: String) {
        lock.lock(); defer { lock.unlock() }
        let map = read().filter { $0.value != account }
        _ = write(map)
    }
    /// Whether the map can be read now (false before the first unlock after a restart).
    public func isReadable() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: file.path) else { return true }
        return (try? Data(contentsOf: file)) != nil
    }
    private func read() -> [String: String] {
        guard let data = try? Data(contentsOf: file), let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }
    private func write(_ map: [String: String]) -> Bool {
        do {
            let directory = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(map).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch { return false }
    }
}
