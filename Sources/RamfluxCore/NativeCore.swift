// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import CRamflux
import Darwin

/// A C ABI v2 supervisor. Construct/start through RamfluxClient to keep filesystem work off UI.
public final class NativeCore: CoreTransport {
    private struct State { var handle: UInt64 = 0; var failed = false; var streamOpened = false }
    private let state = Mutex(State())
    private let configuration: Data
    private let dataRoot: URL
    public let methods: Set<String>
    public let descriptorFingerprint: String
    public init(dataRoot: URL, builtinNodes: [JSONValue] = [], expectedDescriptorFingerprint: String? = nil) throws {
        guard dataRoot.isFileURL, builtinNodes.count <= 64 else { throw BridgeError.invalidInput }
        #if os(iOS)
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              dataRoot.standardizedFileURL == support.appendingPathComponent("ramflux", isDirectory: true).standardizedFileURL else {
            throw BridgeError.unsafeStoragePath
        }
        #endif
        self.dataRoot = dataRoot
        configuration = try JSONValue.object(["data_root": .string(dataRoot.path), "builtin_nodes": .array(builtinNodes)]).encoded()
        var pointer: UnsafeMutablePointer<RamfluxBuffer>?
        let code = ramflux_v2_negotiate(2, 0, &pointer)
        guard code == 0 else { if let pointer { rf_buffer_wipe_free(pointer) }; throw CoreFailure(code: code, effect: .none) }
        let metadata = try JSONValue.decode(NativeBuffers.take(pointer))
        guard metadata["abi_major"] == .number(2), case .array(let names) = metadata["methods"] else {
            throw BridgeError.incompatibleABI
        }
        guard let fingerprint = metadata["message_descriptor_blake3"]?.string,
              fingerprint.utf8.count == 64, fingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              metadata["bus_protocol"] == .string("ramflux.local_bus.v1"),
              expectedDescriptorFingerprint == nil || expectedDescriptorFingerprint == fingerprint else {
            throw BridgeError.incompatibleABI
        }
        descriptorFingerprint = fingerprint
        methods = Set(names.compactMap(\.string))
    }
    func currentHandle() throws -> UInt64 {
        try state.withLock {
            guard !$0.failed, $0.handle != 0 else { throw BridgeError.closed }
            return $0.handle
        }
    }
    public func newCancellation() throws -> any CancellationHandle { NativeCancellation() }
    public func execute(_ request: CoreRequest, cancellation: any CancellationHandle) throws -> JSONValue {
        guard let cancellation = cancellation as? NativeCancellation else { throw BridgeError.invalidInput }
        var data = try request.envelope().encoded()
        defer { data.resetBytes(in: 0..<data.count) }
        return try data.withUnsafeBytes { try executeBytes($0, request: request, cancellation: cancellation) }
    }
    public func executeSecret(_ request: SecretRequest, cancellation: any CancellationHandle) throws -> JSONValue {
        guard let cancellation = cancellation as? NativeCancellation else { throw BridgeError.invalidInput }
        return try request.json.consume { try executeBytes($0, request: request.request, cancellation: cancellation) }
    }
    private func executeBytes(_ bytes: UnsafeRawBufferPointer, request: CoreRequest,
                              cancellation: NativeCancellation) throws -> JSONValue {
        guard methods.contains(request.method) else { throw CoreFailure(code: 3, effect: .none, operationID: request.operationID?.rawValue) }
        if cancellation.isCancelled { throw CoreFailure(code: 25, effect: .none, operationID: request.operationID?.rawValue) }
        guard Date().timeIntervalSince1970 * 1_000 < Double(request.deadlineUnixMilliseconds) else {
            throw CoreFailure(code: 10, effect: .none, operationID: request.operationID?.rawValue)
        }
        let client = try currentHandle()
        var operation: UInt64 = 0
        let status = ramflux_v2_execute(client, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &operation)
        guard status == 0, operation != 0 else { throw CoreFailure(code: status == 0 ? 16 : status, effect: .none, operationID: request.operationID?.rawValue) }
        cancellation.attach(client: client, operation: operation)
        defer { cancellation.detach(); _ = ramflux_v2_operation_release(client, operation) }
        while true {
            var response: UnsafeMutablePointer<RamfluxBuffer>?
            let code = ramflux_v2_operation_poll(client, operation, &response)
            if code == 0 {
                let terminal: JSONValue
                do { terminal = try JSONValue.decode(NativeBuffers.take(response)) }
                catch { throw CoreFailure(code: 16, effect: .unknown, operationID: request.operationID?.rawValue, reasonCode: "invalid_completion") }
                guard case .number(let value) = terminal["code"], let status = Int32(exactly: value) else {
                    throw CoreFailure(code: 16, effect: .unknown, operationID: request.operationID?.rawValue, reasonCode: "invalid_completion")
                }
                if status != 0 {
                    let effect = terminal["effects"]?.string.flatMap(CoreFailure.Effect.init(rawValue:)) ?? .unknown
                    throw CoreFailure(code: status, effect: effect, operationID: request.operationID?.rawValue,
                        reasonCode: terminal["response"]?["error"]?["reason_code"]?.string, response: terminal["response"])
                }
                guard let frame = terminal["response"] else { throw CoreFailure(code: 16, effect: .unknown, operationID: request.operationID?.rawValue, reasonCode: "missing_response") }
                return frame
            }
            if let response { rf_buffer_wipe_free(response) }
            guard code == 24 else { throw CoreFailure(code: code, effect: .unknown, operationID: request.operationID?.rawValue) }
            if cancellation.isCancelled {
                throw CoreFailure(code: 25, effect: .unknown, operationID: request.operationID?.rawValue)
            }
            let now = Date().timeIntervalSince1970 * 1_000
            if now >= Double(request.deadlineUnixMilliseconds) {
                cancellation.cancel()
                throw CoreFailure(code: 10, effect: .unknown, operationID: request.operationID?.rawValue)
            }
            // Dedicated bounded worker, not the cooperative executor or UI thread.
            usleep(10_000)
        }
    }
    public func start() throws {
        try state.withLock { state in
            guard !state.failed else { throw BridgeError.closed }
            guard state.handle == 0 else { return }
            #if os(iOS)
            _ = try AppStorage.prepare(applicationSupport: dataRoot.deletingLastPathComponent())
            #endif
            var handle: UInt64 = 0
            let code = configuration.withUnsafeBytes { ramflux_v2_client_open($0.bindMemory(to: UInt8.self).baseAddress, $0.count, &handle) }
            guard code == 0, handle != 0 else { state.failed = true; throw CoreFailure(code: code == 0 ? 16 : code, effect: .unknown) }
            state.handle = handle; state.streamOpened = false
        }
    }
    public func resume() throws { try start() }
    public func suspend() throws -> JSONValue {
        try close()
        return .object(["data_root_lock_released": .bool(true)])
    }
    public func close() throws {
        try state.withLock { state in
            guard state.handle != 0 else {
                if state.failed { throw BridgeError.lockStillHeld }; return
            }
            let handle = state.handle; state.handle = 0
            let code = ramflux_v2_client_close(handle)
            guard code == 0 else { state.failed = true; throw CoreFailure(code: code, effect: .unknown) }
        }
    }
    public func subscribe(_ filter: SubscriptionFilter) throws -> any EventQueue {
        // The C ABI exposes one event queue per client, so it has one app-session consumer.
        let handle = try state.withLock { state in
            guard !state.failed, state.handle != 0, !state.streamOpened else { throw BridgeError.invalidInput }
            state.streamOpened = true
            return state.handle
        }
        let request = try CoreRequest(method: "subscription.open", sdkAPI: "subscription", accountID: filter.accountID,
            body: filter.body, deadlineUnixMilliseconds: UInt64(Date().timeIntervalSince1970 * 1000) + 5_000)
        let snapshot = try execute(request, cancellation: NativeCancellation())
        return NativeEventQueue(core: self, clientHandle: handle, snapshot: snapshot)
    }
    deinit {
        let handle = state.withLock { $0.handle }
        if handle != 0 { DispatchQueue.global(qos: .utility).async { _ = ramflux_v2_client_close(handle) } }
    }
}
