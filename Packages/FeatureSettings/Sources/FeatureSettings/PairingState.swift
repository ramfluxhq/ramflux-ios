// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import CoreGraphics
import AppData

/// The rendered invitation QR code. It is the only remaining copy of the invitation token once the
/// erasable buffer is erased, so it is dropped as soon as the other device has joined, the ceremony ends or
/// the screen goes away. Identity-equal; never persisted or logged.
public final class PairingCodeImage: @unchecked Sendable, Equatable, CustomStringConvertible {
    public let image: CGImage
    public let operation: PairingOperation
    public let expiresAt: Date
    init(image: CGImage, operation: PairingOperation, expiresAt: Date) { self.image = image; self.operation = operation; self.expiresAt = expiresAt }
    public static func == (lhs: PairingCodeImage, rhs: PairingCodeImage) -> Bool { lhs === rhs }
    public var description: String { "PairingCodeImage" }
}

/// Linking another device from this phone as the primary (boards MOB-G24, MOB-P02/P02S, states after MOB-P04/P05).
public struct PairingState: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        /// Name the new device and create the invitation.
        case name
        /// The invitation QR code is on screen; the other device has not joined yet.
        case invitation(PairingCodeImage)
        /// Compare the seven symbols with the other device.
        case compare(PairingProgress)
        /// Waiting for the other device or the node (after a comparison, or while the change is installed).
        case waiting(PairingProgress)
        /// Review the joining device's facts and approve or decline.
        case review(PairingProgress)
        /// The ceremony ended: completed, cancelled, expired or rejected.
        case finished(PairingProgress)
        /// The ceremony can no longer be followed (for example it was retired or not found).
        case stopped(AppFailure)
    }
    public let account: String?
    public var step: Step = .name
    public var deviceName = ""
    public var busy = false
    public var failure: AppFailure?
    /// The host confirmation for approving the reviewed device is open.
    public var confirmingApproval = false
    /// The app is not active: the invitation is covered (app switcher snapshots and screen sharing).
    public var covered = false
    public init(account: String?) { self.account = account }
    /// The ceremony being followed, if any.
    public var operation: PairingOperation? {
        switch step {
        case .invitation(let code): code.operation
        case .compare(let progress), .waiting(let progress), .review(let progress): progress.operation
        case .name, .finished, .stopped: nil
        }
    }
}

public enum PairingAction: Equatable, Sendable, CustomStringConvertible {
    case appeared, disappeared, covered(Bool)
    case setName(String), begin
    case symbolsMatch(Bool)
    case requestApprove, confirmApprove, cancelApprove, decline
    case cancel, restart, done
    public var description: String { "PairingAction" }
}
