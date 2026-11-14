// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import CRamflux
import Darwin

/// A C ABI v2 supervisor. Construct/start through RamfluxClient to keep filesystem work off UI.
public final class NativeCore: CoreTransport {
    private struct State { var handle: UInt64 = 0; var closing = false; var opening = false; var lifecycleBusy = false; var streamOpened = false; var generation: UInt64 = 0 }
    private let state = Mutex(State())
    private let configuration: Data
    private let dataRoot: URL
    private let custody: HostCustodyProvider?
    public let methods: Set<String>
    public let descriptorFingerprint: String
    public init(dataRoot: URL, builtinNodes: [JSONValue] = [], expectedDescriptorFingerprint: String? = nil, custody: HostCustodyProvider? = nil) throws {
        guard dataRoot.isFileURL, builtinNodes.count <= 64 else { throw BridgeError.invalidInput }
        #if os(iOS)
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              dataRoot.standardizedFileURL == support.appendingPathComponent("ramflux", isDirectory: true).standardizedFileURL else {
            throw BridgeError.unsafeStoragePath
        }
        #endif
        self.dataRoot = dataRoot; self.custody = custody
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
        let advertised = names.compactMap(\.string)
        let expected = Set(SDKOperation.allCases.map(\.rawValue))
        guard advertised.count == names.count, Set(advertised).count == names.count,
              Set(advertised) == expected,
              let policy = metadata["method_policy"], policy["abi_major"] == .number(2),
              policy["policy_version"] == .number(2), case .array(let rows) = policy["methods"] else { throw BridgeError.incompatibleABI }
        var seen = Set<String>()
        var allowed = Set<String>()
        for row in rows {
            guard let name = row["name"]?.string, seen.insert(name).inserted,
                  let bridgeAllowed = row["bridge_allowed"]?.bool,
                  let keyExport = row["key_export"]?.bool else { throw BridgeError.incompatibleABI }
            if !bridgeAllowed {
                guard SDKOperation(rawValue: name) == nil else { throw BridgeError.incompatibleABI }
                continue
            }
            guard let operation = SDKOperation(rawValue: name),
                  row["capability"] == .string(operation.capability),
                  row["secret_input"] == .bool(operation.requiresSecureInput),
                  row["secret_output"] == .bool(operation.requiresSecureOutput),
                  row["show_once"] == .bool(operation.showOnce),
                  keyExport == operation.requiresKeyExport else { throw BridgeError.incompatibleABI }
            allowed.insert(name)
        }
        guard allowed == expected else { throw BridgeError.incompatibleABI }
        methods = expected
    }
    func currentHandle() throws -> UInt64 {
        try state.withLock {
            guard !$0.closing, $0.handle != 0 else { throw BridgeError.closed }
            return $0.handle
        }
    }
    public func newCancellation() throws -> any CancellationHandle { NativeCancellation() }
    public func execute(_ request: CoreRequest, cancellation: any CancellationHandle) throws -> JSONValue {
        guard let policy = SDKOperation(rawValue: request.method), !policy.requiresSecureInput, !policy.requiresSecureOutput else { throw BridgeError.invalidInput }
        var data = try request.envelope().encodedRequest()
        defer { data.resetBytes(in: 0..<data.count) }
        return try data.withUnsafeBytes {
            try requestResult($0, request: request, cancellation: cancellation) { try self.jsonCompletion($0, request: request) }.response
        }
    }
    public func executeSecret(_ request: SecretRequest, cancellation: any CancellationHandle) throws -> JSONValue {
        guard let policy = SDKOperation(rawValue: request.request.method), !policy.requiresSecureOutput else { throw BridgeError.invalidInput }
        return try request.json.consume {
            try requestResult($0, request: request.request, cancellation: cancellation) { try self.jsonCompletion($0, request: request.request) }.response
        }
    }
    public func executeSecretResponse(_ request: CoreRequest, cancellation: any CancellationHandle) throws -> SecretBytes {
        guard let policy = SDKOperation(rawValue: request.method), !policy.requiresSecureInput else { throw BridgeError.invalidInput }
        var data = try request.envelope().encodedRequest()
        defer { data.resetBytes(in: 0..<data.count) }
        return try data.withUnsafeBytes {
            try requestResult($0, request: request, cancellation: cancellation) { try self.sealedCompletion($0, request: request) }.response
        }
    }
    public func executeSecretRequestResponse(_ request: SecretRequest, cancellation: any CancellationHandle) throws -> SecretBytes {
        try request.json.consume {
            try requestResult($0, request: request.request, cancellation: cancellation) { try self.sealedCompletion($0, request: request.request) }.response
        }
    }
    private func sealedCompletion(_ buffer: UnsafeMutablePointer<RamfluxBuffer>, request: CoreRequest) throws -> SecretBytes {
        var code: Int32 = 0
        guard rf_completion_code(buffer, &code) == 1 else {
            throw CoreFailure(code: 16, effect: .unknown, operationID: request.operationID?.rawValue, reasonCode: "invalid_completion")
        }
        let value = buffer.pointee
        let secret = try SecretBytes(copying: UnsafeRawBufferPointer(start: value.ptr, count: value.len), maximumBytes: CoreLimits.frameBytes)
        guard code == 0 else {
            let reason = rf_completion_refusal_reason(buffer).map { String(cString: $0) }
            throw CoreFailure(code: code, effect: .unknown, operationID: request.operationID?.rawValue, reasonCode: reason, typedName: typedName(buffer), sealedResponse: secret)
        }
        return secret
    }
    private func typedName(_ buffer: UnsafeMutablePointer<RamfluxBuffer>) -> String? {
        rf_completion_typed_name(buffer).map { String(cString: $0) }
    }
    private func jsonCompletion(_ buffer: UnsafeMutablePointer<RamfluxBuffer>, request: CoreRequest) throws -> JSONValue {
        let terminal: JSONValue
        do { terminal = try JSONValue.decode(NativeBuffers.copy(buffer)) }
        catch { throw CoreFailure(code: 16, effect: .unknown, operationID: request.operationID?.rawValue, reasonCode: "invalid_completion") }
        guard case .number(let value) = terminal["code"], let status = Int32(exactly: value) else {
            throw CoreFailure(code: 16, effect: .unknown, operationID: request.operationID?.rawValue, reasonCode: "invalid_completion")
        }
        if status != 0 {
            let effect = terminal["effects"]?.string.flatMap(CoreFailure.Effect.init(rawValue:)) ?? .unknown
            throw CoreFailure(code: status, effect: effect, operationID: request.operationID?.rawValue,
                reasonCode: terminal["response"]?["error"]?["reason_code"]?.string, typedName: typedName(buffer), response: terminal["response"])
        }
        guard let frame = terminal["response"] else { throw CoreFailure(code: 16, effect: .unknown, operationID: request.operationID?.rawValue, reasonCode: "missing_response") }
        return frame
    }
    private func requestResult<T: Sendable>(_ bytes: UnsafeRawBufferPointer, request: CoreRequest,
        cancellation: any CancellationHandle, keepOperation: Bool = false,
        parse: (UnsafeMutablePointer<RamfluxBuffer>) throws -> T) throws -> (response: T, operation: NativeOperation?) {
        guard let cancellation = cancellation as? NativeCancellation else { throw BridgeError.invalidInput }
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
        let owner = NativeOperation(client: client, id: operation)
        var transferred = false
        defer { cancellation.detach(); if !transferred { owner.finish() } }
        while true {
            var response: UnsafeMutablePointer<RamfluxBuffer>?
            let code = ramflux_v2_operation_poll(client, operation, &response)
            if code == 0 {
                guard let response else { throw CoreFailure(code: 16, effect: .unknown, operationID: request.operationID?.rawValue) }
                defer { rf_buffer_wipe_free(response) }
                let value = try parse(response)
                transferred = keepOperation
                return (value, keepOperation ? owner : nil)
            }
            if let response { rf_buffer_wipe_free(response) }
            guard code == 24 else { throw CoreFailure(code: code, effect: .unknown, operationID: request.operationID?.rawValue) }
            if cancellation.isCancelled { throw CoreFailure(code: 25, effect: .unknown, operationID: request.operationID?.rawValue) }
            if Date().timeIntervalSince1970 * 1_000 >= Double(request.deadlineUnixMilliseconds) {
                cancellation.cancel()
                throw CoreFailure(code: 10, effect: .unknown, operationID: request.operationID?.rawValue)
            }
            usleep(10_000)
        }
    }
    public func start() throws {
        let shouldOpen = try state.withLock { state in
            guard !state.closing, !state.opening, !state.lifecycleBusy else { throw BridgeError.closed }
            guard state.handle == 0 else { return false }
            state.opening = true; state.lifecycleBusy = true
            return true
        }
        guard shouldOpen else { return }
        var handle: UInt64 = 0
        var code: Int32 = 0
        do {
            #if os(iOS)
            _ = try AppStorage.prepare(applicationSupport: dataRoot.deletingLastPathComponent())
            #endif
            code = configuration.withUnsafeBytes { bytes in
                if let custody { var table = custody.table(); return ramflux_v2_client_open_with_custody(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &table, &handle) }
                return ramflux_v2_client_open(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &handle)
            }
        } catch {
            state.withLock { $0.opening = false; $0.lifecycleBusy = false; $0.closing = false }
            throw error
        }
        let interrupted = state.withLock { state in
            state.opening = false; state.lifecycleBusy = false
            state.handle = handle; state.streamOpened = false; state.generation = 0
            if code != 0, handle != 0 { state.closing = true }
            return state.closing
        }
        if interrupted {
            if handle != 0 { try close() }
            else { state.withLock { $0.closing = false } }
            throw BridgeError.closed
        }
        guard code == 0, handle != 0 else { throw CoreFailure(code: code == 0 ? 16 : code, effect: .none) }
    }
    public func resume() throws { try start() }
    public func suspend() throws -> JSONValue {
        try close()
        return .object(["data_root_lock_released": .bool(true)])
    }
    public func close() throws {
        let handle = try state.withLock { state in
            if state.opening { state.closing = true; throw BridgeError.lockStillHeld }
            guard !state.lifecycleBusy else { throw BridgeError.lockStillHeld }
            guard state.handle != 0 else { return UInt64(0) }
            state.closing = true; state.lifecycleBusy = true
            return state.handle
        }
        guard handle != 0 else { return }
        let code = ramflux_v2_client_close(handle)
        // release is itself a nonblocking terminal-state probe: Pending preserves the fence.
        let released = code != 0 && code != 26 && ramflux_v2_client_release(handle) == 0
        state.withLock { state in
            state.lifecycleBusy = false
            if code == 0 || code == 26 || released {
                state.handle = 0; state.closing = false; state.streamOpened = false
            }
        }
        if released { throw CoreFailure(code: code, effect: .unknown, writerReleaseConfirmed: true) }
        guard code == 0 || code == 26 else { throw BridgeError.lockStillHeld }
    }
    func finishSubscription(client: UInt64) throws {
        guard try currentHandle() == client else { throw BridgeError.closed }
        let deadline = UInt64(Date().timeIntervalSince1970 * 1000) + 5_000
        for attempt in 0..<3 {
            let request = try CoreRequest(method: "subscription.close", sdkAPI: "subscription", body: .object([:]), deadlineUnixMilliseconds: deadline)
            do {
                _ = try execute(request, cancellation: NativeCancellation())
                subscriptionEnded(client: client)
                return
            } catch let error as CoreFailure where error.rawCode == 15 && error.effect == .none && attempt < 2 {
                usleep(20_000)
            }
        }
    }
    public func subscribe(_ filter: SubscriptionFilter) throws -> any EventQueue {
        // The C ABI exposes one event queue per client, so it has one app-session consumer.
        let handle = try state.withLock { state in
            guard !state.closing, state.handle != 0, !state.streamOpened else { throw BridgeError.invalidInput }
            state.streamOpened = true
            return state.handle
        }
        var transferred = false
        defer { if !transferred { try? finishSubscription(client: handle) } }
        let request = try CoreRequest(method: "subscription.open", sdkAPI: "subscription", accountID: filter.accountID,
            body: filter.body, deadlineUnixMilliseconds: UInt64(Date().timeIntervalSince1970 * 1000) + 5_000)
        let body = try request.envelope().encodedRequest()
        let result = try body.withUnsafeBytes {
            try requestResult($0, request: request, cancellation: NativeCancellation(), keepOperation: true) { try self.jsonCompletion($0, request: request) }
        }
        guard let operation = result.operation else { throw BridgeError.invalidResponse }
        let identity: EventIdentity
        do { identity = try EventIdentity(snapshot: result.response, accountID: filter.accountID) }
        catch { operation.finish(); throw error }
        state.withLock { $0.generation = identity.generation }
        transferred = true
        return NativeEventQueue(core: self, operation: operation, snapshot: result.response, identity: identity)
    }
    func subscriptionEnded(client: UInt64) {
        state.withLock { if $0.handle == client { $0.streamOpened = false } }
    }
    public func resetEvents() throws {
        try state.withLock { state in
            guard !state.closing, state.handle != 0, !state.streamOpened else { throw BridgeError.invalidInput }
            let code = ramflux_v2_event_reset(state.handle, state.generation)
            guard code == 0 else { throw CoreFailure(code: code, effect: .none) }
        }
    }

    deinit {
        let handle = state.withLock { $0.handle }
        if handle != 0 { DispatchQueue.global(qos: .utility).async {
            let code = ramflux_v2_client_close(handle)
            if code != 0 && code != 26 { _ = ramflux_v2_client_release(handle) }
        } }
    }
}
