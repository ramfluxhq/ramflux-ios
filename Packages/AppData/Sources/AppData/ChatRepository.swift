// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public enum ChatCapability: Sendable { case revisions, attachmentTransfer, calls, details }
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
    func delete(account: String, conversation: String, message: String, operationID: String) async -> RepositoryResult<Void>
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
        switch capability { case .calls: .notAvailable(AppDataStrings.text("copy.8f3374ffa405")); case .details: .notAvailable(AppDataStrings.text("copy.98b57b0920ec")); case .revisions: .notAvailable(AppDataStrings.text("copy.90e302595fee"))
        case .attachmentTransfer: .notAvailable(AppDataStrings.text("copy.0e3b0c4afad6")) }
    }
    public func messages(account: String, conversation: String) async -> RepositoryResult<[MessageRecord]> {
        do {
            let body = try await gateway.call(.messageList, account: account, body: .object(["conversation_id": .string(conversation)]))
            let records = try ProxyGateway.rows(body, "messages").map { row -> MessageRecord in
                let id = try ProxyGateway.text(row, "message_id")
                guard row["conversation_id"] == .string(conversation) else { throw AppFailure.invalidData }
                if row["kind"] == .string("call") {
                    return MessageRecord(id: id, sender: "", kind: .callHistory, isOwn: nil, timestamp: ProxyGateway.integer(row["created_at"]))
                }
                guard let own = row["is_own"]?.bool else { throw AppFailure.invalidData }
                if row["deleted"] == .bool(true) { return MessageRecord(id: id, sender: "", kind: .deleted, isOwn: own, timestamp: ProxyGateway.integer(row["created_at"])) }
                let kind: MessageRecord.Kind
                // Reader's message_page supplies body_utf8 from authenticated message_content.
                // encrypted_body is transport/storage material and is never decoded here.
                if let text = row["body_utf8"]?.string, text.utf8.count <= 65_536 { kind = .text(text) }
                else { kind = .unsupported(AppDataStrings.text("copy.25c796d9c8f8")) }
                var receipt: String?
                if own, case .array(let values) = row["receipts"] {
                    receipt = values.compactMap { entry -> String? in
                        guard let device = entry["device_id"]?.string, let status = entry["state"]?.string, ["sent","delivered","read"].contains(status) else { return nil }
                        return AppDataStrings.format("receipt.deviceState", device, AppDataStrings.status(status))
                    }.joined(separator: " · ")
                }
                let attachments: [AttachmentRecord]
                if row["attachments"] != nil {
                    attachments = try ProxyGateway.rows(row, "attachments").map { item in
                        let object = try ProxyGateway.text(item, "object_id")
                        return AttachmentRecord(id: object, name: item["name"]?.string ?? object, mime: item["mime"]?.string)
                    }
                    guard Set(attachments.map(\.id)).count == attachments.count else { throw AppFailure.invalidData }
                } else { attachments = [] }
                return MessageRecord(id: id, sender: row["sender_id"]?.string ?? "", kind: kind, isOwn: own, timestamp: ProxyGateway.integer(row["created_at"]), receipt: receipt?.isEmpty == false ? receipt : nil, attachments: attachments)
            }
            guard Set(records.map(\.id)).count == records.count else { throw AppFailure.invalidData }; return .success(records)
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func send(account: String, conversation: String, text: String, operationID: String) async -> RepositoryResult<SendOutcome> {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 65_536 else { return .failure(.invalidInput) }
        return await sends.run(scope: account + "\u{0}" + conversation, arguments: text, operationID: operationID) { [gateway] in
        do {
            let body = try await gateway.call(.conversationSend, account: account, body: .object(["conversation_id": .string(conversation), "text": .string(text)]), operationID: operationID)
            guard body["conversation_id"] == .string(conversation), let state = body["delivery_state"]?.string.flatMap(SendOutcome.State.init(rawValue:)) else { throw AppFailure.outcomeUnknown }
            guard let message = body["message_id"]?.string, !message.isEmpty, message.utf8.count <= 65_536 else { throw AppFailure.outcomeUnknown }
            return .success(SendOutcome(messageID: message, state: state))
        } catch { return .failure(AppFailure.map(error)) }
        }
    }

    public func delete(account: String, conversation: String, message: String, operationID: String) async -> RepositoryResult<Void> {
        do { _ = try await gateway.call(.messageDelete, account: account, body: .object(["conversation_id": .string(conversation), "message_id": .string(message), "delete_scope": .string("own_devices")]), operationID: operationID); return .success(()) }
        catch { return .failure(AppFailure.map(error)) }
    }
    public func observe(account: String) async -> RepositoryObservation { await updates.observe(account: account) }
}
public struct UnavailableChatRepository: ChatRepository {
    public init() {}
    public func unavailable(_ capability: ChatCapability) -> AppFailure {
        switch capability { case .calls: .notAvailable(AppDataStrings.text("copy.8f3374ffa405")); case .details: .notAvailable(AppDataStrings.text("copy.98b57b0920ec")); case .revisions: .notAvailable(AppDataStrings.text("copy.90e302595fee"))
        case .attachmentTransfer: .notAvailable(AppDataStrings.text("copy.0e3b0c4afad6")) }
    }
    public func messages(account: String, conversation: String) async -> RepositoryResult<[MessageRecord]> { .failure(.sdkUnavailable) }
    public func send(account: String, conversation: String, text: String, operationID: String) async -> RepositoryResult<SendOutcome> { .failure(.sdkUnavailable) }
    public func delete(account: String, conversation: String, message: String, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func observe(account: String) async -> RepositoryObservation { RepositoryObservation(failure: .sdkUnavailable) }
}

public extension ChatRepository { func sendState(account: String, conversation: String) async -> PendingChatSend? { nil } }
