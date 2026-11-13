// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public enum ChatCapability: Sendable { case revisions, attachmentTransfer }
public struct SendOutcome: Equatable, Sendable {
    public enum State: String, Sendable { case submitted, failed }
    public let messageID: String
    public let state: State
    public init(messageID: String, state: State) { self.messageID = messageID; self.state = state }
}
public protocol ChatRepository: Sendable {
    func unavailable(_ capability: ChatCapability) -> AppFailure
    func messages(account: String, conversation: String) async -> RepositoryResult<[MessageRecord]>
    func send(account: String, conversation: String, text: String, operationID: String) async -> RepositoryResult<SendOutcome>
    func delete(account: String, conversation: String, message: String, operationID: String) async -> RepositoryResult<Void>
    func observe(account: String) async -> RepositoryObservation
}
public struct NativeChatRepository: ChatRepository {
    private let gateway: ProxyGateway
    private let updates: NativeUpdateSource
    public init(client: RamfluxClient, updates: NativeUpdateSource) { gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.updates = updates }
    public func unavailable(_ capability: ChatCapability) -> AppFailure {
        switch capability { case .revisions: .notAvailable("Editing, reactions and replies require the updated message service.")
        case .attachmentTransfer: .notAvailable("Attachment transfer requires the phone file-storage integration. No file has been downloaded.") }
    }
    public func messages(account: String, conversation: String) async -> RepositoryResult<[MessageRecord]> {
        do {
            let body = try await gateway.call(.messageList, account: account, body: .object(["conversation_id": .string(conversation)]))
            let records = try ProxyGateway.rows(body, "messages").map { row -> MessageRecord in
                let id = try ProxyGateway.text(row, "message_id")
                guard row["conversation_id"] == .string(conversation), let own = row["is_own"]?.bool else { throw AppFailure.invalidData }
                if row["deleted"] == .bool(true) { return MessageRecord(id: id, sender: "", kind: .deleted, isOwn: own, timestamp: ProxyGateway.integer(row["created_at"])) }
                let kind: MessageRecord.Kind
                // Reader's message_page supplies body_utf8 from authenticated message_content.
                // encrypted_body is transport/storage material and is never decoded here.
                if let text = row["body_utf8"]?.string, text.utf8.count <= 65_536 { kind = .text(text) }
                else { kind = .unsupported("This message has no displayable text projection.") }
                var receipt: String?
                if own, case .array(let values) = row["receipts"] {
                    receipt = values.compactMap { entry -> String? in
                        guard let device = entry["device_id"]?.string, let status = entry["state"]?.string, ["sent","delivered","read"].contains(status) else { return nil }
                        return device + ": " + status
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
        do {
            let body = try await gateway.call(.conversationSend, account: account, body: .object(["conversation_id": .string(conversation), "text": .string(text)]), operationID: operationID)
            guard body["conversation_id"] == .string(conversation), let state = body["delivery_state"]?.string.flatMap(SendOutcome.State.init(rawValue:)) else { throw AppFailure.outcomeUnknown }
            return .success(SendOutcome(messageID: try ProxyGateway.text(body, "message_id"), state: state))
        } catch { return .failure(AppFailure.map(error)) }
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
        switch capability { case .revisions: .notAvailable("Editing, reactions and replies require the updated message service.")
        case .attachmentTransfer: .notAvailable("Attachment transfer requires the phone file-storage integration. No file has been downloaded.") }
    }
    public func messages(account: String, conversation: String) async -> RepositoryResult<[MessageRecord]> { .failure(.sdkUnavailable) }
    public func send(account: String, conversation: String, text: String, operationID: String) async -> RepositoryResult<SendOutcome> { .failure(.sdkUnavailable) }
    public func delete(account: String, conversation: String, message: String, operationID: String) async -> RepositoryResult<Void> { .failure(.sdkUnavailable) }
    public func observe(account: String) async -> RepositoryObservation { RepositoryObservation(failure: .sdkUnavailable) }
}
