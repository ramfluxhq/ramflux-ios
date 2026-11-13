// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
/// Repository-owned attempts outlive cancelled UI waiters. Only identical arguments/key may retry.
public actor RetainedMutation<Arguments: Equatable & Sendable, Value: Sendable> {
    public struct Snapshot: Sendable {
        public let arguments: Arguments
        public let operationID: String
        public let result: RepositoryResult<Value>?
        public var unresolved: Bool {
            switch result { case nil, .failure(.outcomeUnknown), .failure(.offline): true; default: false }
        }
    }
    private struct Entry: Sendable {
        let arguments: Arguments
        let operationID: String
        let task: Task<RepositoryResult<Value>, Never>
        var result: RepositoryResult<Value>?
    }
    private var entries: [String: Entry] = [:]
    public init() {}
    public func snapshot(scope: String) -> Snapshot? {
        entries[scope].map { Snapshot(arguments: $0.arguments, operationID: $0.operationID, result: $0.result) }
    }
    public func run(scope: String, arguments: Arguments, operationID: String,
                    operation: @escaping @Sendable () async -> RepositoryResult<Value>) async -> RepositoryResult<Value> {
        var reconcilingUnknown = false
        if let old = entries[scope] {
            let unresolved = Snapshot(arguments: old.arguments, operationID: old.operationID, result: old.result).unresolved
            if unresolved {
                guard old.arguments == arguments, old.operationID == operationID else { return .failure(.outcomeUnknown) }
                if case nil = old.result { return await old.task.value }
                reconcilingUnknown = true
            }
        }
        let task = Task { await operation() }
        entries[scope] = Entry(arguments: arguments, operationID: operationID, task: task)
        var result = await task.value
        if reconcilingUnknown, case .failure = result { result = .failure(.outcomeUnknown) }
        // An older waiter must never replace a newer attempt.
        if entries[scope]?.operationID == operationID { entries[scope]?.result = result }
        return result
    }
    deinit { for entry in entries.values { entry.task.cancel() } }
}
