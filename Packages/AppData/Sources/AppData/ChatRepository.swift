// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public enum ChatCapability: Sendable { case attachmentTransfer, calls, details }
public enum MessageDeleteScope: String, Sendable, Equatable { case local, everyone }
public struct SendOutcome: Equatable, Sendable {
    public enum State: String, Sendable { case submitted, failed }
    public let messageID: String
    public let state: State
    public init(messageID: String, state: State) { self.messageID = messageID; self.state = state }
}
public protocol ChatRepository: Sendable {
    func unavailable(_ capability: ChatCapability) -> AppFailure
    func sendState(account: String, conversation: String) async -> PendingChatSend?
    func messages(account: String, conversation: String) async -> RepositoryResult<[MessageRecord]>
    func send(account: String, conversation: String, text: String, operationID: String) async -> RepositoryResult<SendOutcome>
    func edit(account: String, conversation: String, message: String, text: String, operationID: String) async -> RepositoryResult<Void>
    func reply(account: String, conversation: String, message: String, text: String, operationID: String) async -> RepositoryResult<Void>
    func react(account: String, conversation: String, message: String, token: String, remove: Bool, operationID: String) async -> RepositoryResult<Void>
    func delete(account: String, conversation: String, message: String, scope: MessageDeleteScope, operationID: String) async -> RepositoryResult<Void>
    func observe(account: String) async -> RepositoryObservation
}
public struct NativeChatRepository: ChatRepository {
    private let sends = RetainedMutation<String, SendOutcome>()
    public func sendState(account: String, conversation: String) async -> PendingChatSend? {
        guard let entry = await sends.snapshot(scope: account + "\u{0}" + conversation) else { return nil }
        return PendingChatSend(operationID: entry.operationID, text: entry.arguments, unresolved: entry.unresolved, result: entry.result)
    }
    private let gateway: ProxyGateway
    private let updates: NativeUpdateSource
    public init(client: RamfluxClient, updates: NativeUpdateSource) { gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.updates = updates }
    public func unavailable(_ capability: ChatCapability) -> AppFailure {
        switch capability {
        case .calls: .unavailableResource("copy.8f3374ffa405")
        case .details: .unavailableResource("copy.98b57b0920ec")
        case .attachmentTransfer: .unavailableResource("copy.0e3b0c4afad6")
        }
    }
    public func messages(account: String, conversation: String) async -> RepositoryResult<[MessageRecord]> {
        do {
            let body = try await gateway.call(.messageList, account: account, body: .object(["conversation_id": .string(conversation), "read_model": .bool(true), "limit": .number(100)]))
            return .success(try MessagePage.records(body: body, conversation: conversation))
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func send(account: String, conversation: String, text: String, operationID: String) async -> RepositoryResult<SendOutcome> {
        guard Self.usableText(text), Self.identity(conversation), Self.identity(operationID) else { return .failure(.invalidInput) }
        return await sends.run(scope: account + "\u{0}" + conversation, arguments: text, operationID: operationID) { [gateway] in
        do {
            let body = try await gateway.call(.conversationSend, account: account, body: .object(["conversation_id": .string(conversation), "text": .string(text)]), operationID: operationID)
            guard body["conversation_id"] == .string(conversation), let state = body["delivery_state"]?.string.flatMap(SendOutcome.State.init(rawValue:)) else { throw AppFailure.outcomeUnknown }
            guard let message = body["message_id"]?.string, !message.isEmpty, message.utf8.count <= 65_536 else { throw AppFailure.outcomeUnknown }
            return .success(SendOutcome(messageID: message, state: state))
        } catch { return .failure(AppFailure.map(error)) }
        }
    }
    public func edit(account: String, conversation: String, message: String, text: String, operationID: String) async -> RepositoryResult<Void> {
        await mutate(.conversationEdit, account: account, conversation: conversation, message: message, operationID: operationID, text: text, extra: [:], states: ["submitted"])
    }
    public func reply(account: String, conversation: String, message: String, text: String, operationID: String) async -> RepositoryResult<Void> {
        await mutate(.conversationReply, account: account, conversation: conversation, message: message, operationID: operationID, text: text, extra: [:], states: ["submitted"])
    }
    public func react(account: String, conversation: String, message: String, token: String, remove: Bool, operationID: String) async -> RepositoryResult<Void> {
        guard ReactionToken.valid(token) else { return .failure(.invalidInput) }
        var extra: [String: JSONValue] = ["token": .string(token)]
        if remove { extra["remove"] = .bool(true) }
        return await mutate(.conversationReact, account: account, conversation: conversation, message: message, operationID: operationID, text: nil, extra: extra, states: ["submitted"])
    }
    public func delete(account: String, conversation: String, message: String, scope: MessageDeleteScope, operationID: String) async -> RepositoryResult<Void> {
        await mutate(.conversationDelete, account: account, conversation: conversation, message: message, operationID: operationID, text: nil, extra: ["scope": .string(scope.rawValue)], states: ["submitted", "local"])
    }
    public func observe(account: String) async -> RepositoryObservation { await updates.observe(account: account) }

    private func mutate(_ operation: SDKOperation, account: String, conversation: String, message: String, operationID: String, text: String?, extra: [String: JSONValue], states: Set<String>) async -> RepositoryResult<Void> {
        guard Self.identity(conversation), Self.identity(message), Self.identity(operationID) else { return .failure(.invalidInput) }
        if let text, !Self.usableText(text) { return .failure(.invalidInput) }
        var body: [String: JSONValue] = ["conversation_id": .string(conversation), "message_id": .string(message)]
        if let text { body["text"] = .string(text) }
        for (key, value) in extra { body[key] = value }
        do {
            let result = try await gateway.call(operation, account: account, body: .object(body), operationID: operationID)
            guard result["conversation_id"] == .string(conversation), let state = result["delivery_state"]?.string else { throw AppFailure.outcomeUnknown }
            let target = result["target_message_id"]?.string ?? result["message_id"]?.string
            guard target == message else { throw AppFailure.outcomeUnknown }
            if state == "failed" { throw AppFailure.failed }
            guard states.contains(state) else { throw AppFailure.outcomeUnknown }
            return .success(())
        } catch { return .failure(AppFailure.map(error)) }
    }
    private static func usableText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= 65_536
    }
    private static func identity(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 256 }
}
public struct UnavailableChatRepository: ChatRepository {
    public init() {}
    public func unavailable(_ capability: ChatCapability) -> AppFailure {
        switch capability {
        case .calls: .unavailableResource("copy.8f3374ffa405")
        case .details: .unavailableResource("copy.98b57b0920ec")
        case .attachmentTransfer: .unavailableResource("copy.0e3b0c4afad6")
        }
    }
    public func messages(account: String, conversation: String) async -> RepositoryResult<[MessageRecord]> { .failure(.sdkUnavailable) }
    public func send(account: String, conversation: String, text: String, operationID: String) async -> RepositoryResult<SendOutcome> { .failure(.sdkUnavailable) }
    public func edit(account: String, conversation: String, message: String, text: String, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func reply(account: String, conversation: String, message: String, text: String, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func react(account: String, conversation: String, message: String, token: String, remove: Bool, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func delete(account: String, conversation: String, message: String, scope: MessageDeleteScope, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func observe(account: String) async -> RepositoryObservation { RepositoryObservation(failure: .sdkUnavailable) }
}

public extension ChatRepository { func sendState(account: String, conversation: String) async -> PendingChatSend? { nil } }
