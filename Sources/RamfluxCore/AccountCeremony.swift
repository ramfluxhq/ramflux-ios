// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// One account-setup flow on the client's connection. The SDK remains the authority.
/// Do not interleave two ceremonies on a client. Confirmation is a single attempt.
public actor AccountCeremony {
    public enum Kind: Sendable { case creation, recovery }
    public enum State: Sendable { case idle, beginning, pending, showingPhrase, phraseVisible, hidden, requestingChallenge, challenged, confirming, cancelling, finished, cancelled, failed }
    public private(set) var state: State = .idle
    private let proxy: SDKProxy
    private let kind: Kind
    private var phrase: SecretBytes?
    public init(proxy: SDKProxy, kind: Kind) { self.proxy = proxy; self.kind = kind }
    public func begin(context: RequestContext, body: JSONValue) async throws -> SecretBytes {
        guard state == .idle else { throw BridgeError.invalidCeremonyState }
        state = .beginning
        do {
            let response = try await proxy.performSecretRequestResponse(kind == .creation ? .accountCreateBegin : .accountRecoverBegin, context: context, body: body, secrets: [:])
            state = .pending
            return response
        }
        catch { state = .failed; throw error }
    }
    /// The sealed complete response frame. Parse only inside SecretBytes.consume; do not persist.
    public func showPhraseOnce(context: RequestContext) async throws -> SecretBytes {
        guard kind == .creation, state == .pending else { throw BridgeError.invalidCeremonyState }
        state = .showingPhrase
        do {
            let secret = try await proxy.performSecretResponse(.accountCreateShowOnce, context: context)
            phrase = secret; state = .phraseVisible
            return secret
        } catch { state = .failed; throw error }
    }
    public func hidePhrase() throws {
        guard state == .phraseVisible else { throw BridgeError.invalidCeremonyState }
        phrase?.erase(); phrase = nil; state = .hidden
    }
    public func challenge(context: RequestContext) async throws -> SecretBytes {
        guard kind == .creation, state == .hidden else { throw BridgeError.invalidCeremonyState }
        state = .requestingChallenge
        do {
            let response = try await proxy.performSecretResponse(.accountCreateHiddenChallenge, context: context)
            state = .challenged
            return response
        }
        catch { state = .failed; throw error }
    }
    public func confirm(context: RequestContext, body: JSONValue = .object([:]), fields: [String: SecretField]) async throws -> CeremonyResult {
        guard (kind == .creation && state == .challenged) || (kind == .recovery && state == .pending) else {
            fields.values.forEach { $0.erase() }; throw BridgeError.invalidCeremonyState
        }
        state = .confirming
        do {
            let result: CeremonyResult
            let operation: SDKOperation = kind == .creation ? .accountCreateConfirm : .accountRecoverConfirm
            if operation.requiresSecureOutput {
                result = .sealed(try await proxy.performSecretRequestResponse(operation, context: context, body: body, secrets: fields))
            } else {
                result = .frame(try await proxy.performSecret(operation, context: context, body: body, secrets: fields))
            }
            state = .finished; return result
        } catch { state = .failed; throw error }
    }
    public func cancel(context: RequestContext) async throws {
        guard state != .finished && state != .cancelled else { return }
        // First cancel and await an in-flight Swift Task, then end the SDK ceremony.
        guard state != .beginning, state != .showingPhrase, state != .requestingChallenge,
              state != .confirming, state != .cancelling else { throw BridgeError.invalidCeremonyState }
        phrase?.erase(); phrase = nil; state = .cancelling
        do {
            _ = try await proxy.perform(kind == .creation ? .accountCreateCancel : .accountRecoverCancel, context: context)
            state = .cancelled
        } catch { state = .failed; throw error }
    }
    deinit { phrase?.erase() }
}
