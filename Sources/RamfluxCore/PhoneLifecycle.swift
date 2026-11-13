// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// Serializes transitions even across actor reentrancy. Failed shutdown never permits reopen.
public actor PhoneLifecycle {
    public enum State: Sendable { case stopped, running, suspended, failed }
    private enum Event: Sendable { case foreground, background, close }
    public private(set) var state: State = .stopped
    private let client: RamfluxClient
    private let dataRoot: URL
    private var transition: Task<Void, any Error>?
    public init(client: RamfluxClient, dataRoot: URL) { self.client = client; self.dataRoot = dataRoot }
    public func foreground() async throws { try await enqueue(.foreground) }
    public func background() async throws { try await enqueue(.background) }
    public func close() async throws { try await enqueue(.close) }
    private func enqueue(_ event: Event) async throws {
        let previous = transition
        let task = Task {
            if let previous { _ = try? await previous.value }
            try await self.apply(event)
        }
        transition = task
        try await task.value
    }
    private func apply(_ event: Event) async throws {
        do {
            switch event {
            case .foreground:
                guard state != .failed else { throw BridgeError.lockStillHeld }
                guard state != .running else { return }
                if state == .stopped { try await client.start() } else { try await client.resume() }
                do { try AppStorage.protectDatabaseFiles(in: dataRoot) }
                catch { try await client.close(); throw error }
                state = .running
            case .background:
                guard state != .failed else { throw BridgeError.lockStillHeld }
                guard state == .running else { return }
                try await client.suspend(); state = .suspended
            case .close:
                try await client.close(); state = .stopped
            }
        } catch {
            if (error as? BridgeError) == .lockStillHeld { state = .failed }
            throw error
        }
    }
}
