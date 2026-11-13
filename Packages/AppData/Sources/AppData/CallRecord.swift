// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public struct CallRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let conversationID: String
    public let peerID: String
    public let direction: CallDirection
    public let phase: CallPhase
    public let endReason: String?
    public let failureReason: CallFailureReason?
    public let peerReason: CallFailureReason?
    public let sequence: UInt64
    public let mediaGeneration: UInt64
    public let createdAt: Int64
    public let answeredAt: Int64?
    public let endedAt: Int64?
    public var canDecline: Bool { direction == .incoming && phase == .incomingRinging }
    public var canHangup: Bool { [.outgoingRinging, .incomingRinging, .connecting, .active].contains(phase) }
    public init(id: String, conversationID: String, peerID: String, direction: CallDirection, phase: CallPhase, endReason: String? = nil, failureReason: CallFailureReason? = nil, peerReason: CallFailureReason? = nil, sequence: UInt64, mediaGeneration: UInt64 = 0, createdAt: Int64, answeredAt: Int64? = nil, endedAt: Int64? = nil) {
        self.id = id; self.conversationID = conversationID; self.peerID = peerID; self.direction = direction; self.phase = phase; self.endReason = endReason; self.failureReason = failureReason; self.peerReason = peerReason; self.sequence = sequence; self.mediaGeneration = mediaGeneration; self.createdAt = createdAt; self.answeredAt = answeredAt; self.endedAt = endedAt
    }
}
