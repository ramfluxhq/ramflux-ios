// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import CRamflux

/// The attended request core makes during one call. Only `unlock` exists: the account's own code, given once.
public enum CredentialAction: String, Sendable { case unlock }

/// Asks the host for the account code of one attended call. Nil means the host refused (dismissed, backgrounded,
/// or no answer). The SDK copies the answer once and the bridge erases its copy on every path.
public typealias CredentialAsk = @Sendable (CredentialAction) async -> SecretBytes?

/// One attended call's exchange. The SDK callback thread waits here (at most 60 s) while the host answers.
/// An answer that arrives after the wait has ended is erased, never delivered.
final class CredentialExchange: Sendable {
    private struct State: Sendable { var answer: SecretBytes?; var delivered = false; var abandoned = false }
    static let waitSeconds: Double = 60
    static let codeCapacity = 1024
    private let state = Mutex(State())
    private let signal = DispatchSemaphore(value: 0)
    private let ask: CredentialAsk
    init(ask: @escaping CredentialAsk) { self.ask = ask }
    func request() -> SecretBytes? {
        Task.detached { [self] in deliver(await ask(.unlock)) }
        _ = signal.wait(timeout: .now() + Self.waitSeconds)
        return state.withLock { state in
            state.abandoned = true
            let answer = state.answer
            state.answer = nil
            return answer
        }
    }
    private func deliver(_ answer: SecretBytes?) {
        let late: SecretBytes? = state.withLock { state in
            guard !state.abandoned, !state.delivered else { return answer }
            state.delivered = true; state.answer = answer
            return nil
        }
        late?.erase()
        signal.signal()
    }
    /// The `unlock` action only. Any other action, or metadata that does not parse, is refused.
    static func isUnlock(_ metadata: UnsafePointer<UInt8>, _ count: Int) -> Bool {
        guard count > 0, count <= 4096, let json = try? JSONValue.decode(Data(bytes: metadata, count: count)) else { return false }
        return json["action"]?.string == CredentialAction.unlock.rawValue
    }
}

/// The `CredentialProviderCallback` of `ramflux_v2_set_credential_provider`. `context` is the retained exchange.
let credentialProviderCallback: CredentialProviderCallback = { metadata, metadataLength, output, capacity, length, confirmOutput, confirmCapacity, confirmLength, context in
    confirmLength?.pointee = 0
    length?.pointee = 0
    guard let context, let metadata, let output, let length, CredentialExchange.isUnlock(metadata, metadataLength) else { return 1 }
    _ = confirmOutput; _ = confirmCapacity
    let exchange = Unmanaged<CredentialExchange>.fromOpaque(context).takeUnretainedValue()
    guard let secret = exchange.request() else { return 1 }
    let copied = (try? secret.consume { bytes -> Bool in
        guard bytes.count > 0, bytes.count <= min(capacity, CredentialExchange.codeCapacity), let source = bytes.baseAddress else { return false }
        output.update(from: source.assumingMemoryBound(to: UInt8.self), count: bytes.count)
        length.pointee = bytes.count
        return true
    }) ?? false
    return copied ? 0 : 1
}
