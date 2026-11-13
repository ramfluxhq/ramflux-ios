// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

public struct OperationID: Hashable, Codable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) throws {
        guard !rawValue.isEmpty, rawValue.utf8.count <= 256 else { throw BridgeError.invalidInput }
        self.rawValue = rawValue
    }
    public static func fresh() -> Self { Self(rawValue: UUID().uuidString) }
    private init(rawValue: String) { self.rawValue = rawValue }
}

public struct CoreRequest: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "CoreRequest(method: \(method))" }
    public var debugDescription: String { description }
    public let method: String
    public let sdkAPI: String
    public let accountID: String?
    public let operationID: OperationID?
    public let body: JSONValue
    public let deadlineUnixMilliseconds: UInt64
    func envelope() -> JSONValue {
        var fields: [String: JSONValue] = ["method": .string(method), "sdk_api": .string(sdkAPI),
            "body": body, "deadline_ms": .number(Double(deadlineUnixMilliseconds))]
        if let accountID { fields["account_id"] = .string(accountID) }
        if let operationID { fields["operation_id"] = .string(operationID.rawValue) }
        return .object(fields)
    }
    public init(method: String, sdkAPI: String, accountID: String? = nil,
                operationID: OperationID? = nil, body: JSONValue = .object([:]),
                deadlineUnixMilliseconds: UInt64) throws {
        guard !method.isEmpty, method.utf8.count < 128, !sdkAPI.isEmpty, sdkAPI.utf8.count < 128,
              accountID == nil || (accountID?.utf8.count ?? 0) <= 256,
              deadlineUnixMilliseconds > 0, deadlineUnixMilliseconds <= 9_007_199_254_740_991, case .object = body else { throw BridgeError.invalidInput }
        self.method = method; self.sdkAPI = sdkAPI; self.accountID = accountID
        self.operationID = operationID; self.body = body
        self.deadlineUnixMilliseconds = deadlineUnixMilliseconds
    }
}

public struct SubscriptionFilter: Sendable {
    public let accountID: String?
    public let body: JSONValue
    public let capacity: Int
    public init(accountID: String? = nil, topics: [String], afterSequence: String? = nil,
                capacity: Int = CoreLimits.eventBuffer, attendedFrontend: Bool = false) throws {
        guard (1...CoreLimits.eventBuffer).contains(capacity), topics.count <= 64,
              topics.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }),
              afterSequence == nil || afterSequence?.allSatisfy(\.isNumber) == true else {
            throw BridgeError.invalidInput
        }
        self.accountID = accountID; self.capacity = capacity
        var body: [String: JSONValue] = ["topics": .array(topics.map(JSONValue.string))]
        if attendedFrontend { body["attended_frontend"] = .bool(true) }
        if let afterSequence { guard let sequence = UInt64(afterSequence) else { throw BridgeError.invalidInput }
            body["since_seq"] = .unsigned(sequence) }
        self.body = .object(body)
    }
}
