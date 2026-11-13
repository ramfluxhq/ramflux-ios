// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain

/// Shared SDK capabilities which have no published implementation/contract in this binding.
/// These errors are local refusals; no request, operation key, or fixture result is fabricated.
public enum UnavailableCapability: Error, Sendable, Equatable {
    case localSearch, agentConfiguration, strangerReporting, strangerBatchActions
    case messageEditing, messageReactions, messageReplies
}
public protocol SearchProxy: Sendable {
    func search(query: String, context: RequestContext) async throws -> JSONValue
}
public protocol AgentConfigurationProxy: Sendable {
    func createAgent(configuration: JSONValue, context: RequestContext) async throws -> JSONValue
    func configureAgent(agentID: String, configuration: JSONValue, context: RequestContext) async throws -> JSONValue
}
public protocol StrangerReportingProxy: Sendable {
    func reportStranger(conversationID: String, report: JSONValue, context: RequestContext) async throws
    func batchStrangerAction(conversationIDs: [String], action: JSONValue, context: RequestContext) async throws
}
public protocol MessageRevisionProxy: Sendable {
    func editMessage(messageID: String, content: JSONValue, context: RequestContext) async throws -> JSONValue
    func reactToMessage(messageID: String, reaction: JSONValue, context: RequestContext) async throws -> JSONValue
    func replyToMessage(messageID: String, content: JSONValue, context: RequestContext) async throws -> JSONValue
}
public struct UnavailableFeatures: SearchProxy, AgentConfigurationProxy, StrangerReportingProxy, MessageRevisionProxy {
    public init() {}
    public func search(query: String, context: RequestContext) async throws -> JSONValue { throw UnavailableCapability.localSearch }
    public func createAgent(configuration: JSONValue, context: RequestContext) async throws -> JSONValue { throw UnavailableCapability.agentConfiguration }
    public func configureAgent(agentID: String, configuration: JSONValue, context: RequestContext) async throws -> JSONValue { throw UnavailableCapability.agentConfiguration }
    public func reportStranger(conversationID: String, report: JSONValue, context: RequestContext) async throws { throw UnavailableCapability.strangerReporting }
    public func batchStrangerAction(conversationIDs: [String], action: JSONValue, context: RequestContext) async throws { throw UnavailableCapability.strangerBatchActions }
    public func editMessage(messageID: String, content: JSONValue, context: RequestContext) async throws -> JSONValue { throw UnavailableCapability.messageEditing }
    public func reactToMessage(messageID: String, reaction: JSONValue, context: RequestContext) async throws -> JSONValue { throw UnavailableCapability.messageReactions }
    public func replyToMessage(messageID: String, content: JSONValue, context: RequestContext) async throws -> JSONValue { throw UnavailableCapability.messageReplies }
}
