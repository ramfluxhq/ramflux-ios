// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
public enum AppFailure: Error, Sendable, Equatable {
    case sdkUnavailable, unsupported, offline, locked, busy, upgradeRequired, invalidData, invalidInput, resyncRequired
    case unavailableResource(String), notAvailable(String), outcomeUnknown, failed
    public var title: String { title(locale: .current) }
    public func title(locale: Locale) -> String {
        switch self {
        case .sdkUnavailable: AppDataStrings.text("copy.5562fbd3e629", locale: locale)
        case .unsupported, .notAvailable, .unavailableResource: AppDataStrings.text("copy.787406ddea2a", locale: locale)
        case .offline: AppDataStrings.text("copy.e40966162b11", locale: locale)
        case .locked: AppDataStrings.text("copy.68d02ee6497e", locale: locale)
        case .busy: AppDataStrings.text("copy.9dcdd3257d89", locale: locale)
        case .upgradeRequired: AppDataStrings.text("copy.5856eb3d60b0", locale: locale)
        case .resyncRequired: AppDataStrings.text("copy.9503c0e50707", locale: locale)
        case .invalidData: AppDataStrings.text("copy.536ec5ca4da6", locale: locale)
        case .invalidInput: AppDataStrings.text("copy.29ea6afd1a52", locale: locale)
        case .outcomeUnknown: AppDataStrings.text("copy.b5e82d852d43", locale: locale)
        case .failed: AppDataStrings.text("copy.ab827e3fe17d", locale: locale)
        }
    }
    public var message: String { message(locale: .current) }
    public func message(locale: Locale) -> String {
        switch self {
        case .sdkUnavailable: AppDataStrings.text("copy.c3654c6a066c", locale: locale)
        case .unsupported: AppDataStrings.text("copy.a18c44969ead", locale: locale)
        case .offline: AppDataStrings.text("copy.c294a0b00e74", locale: locale)
        case .locked: AppDataStrings.text("copy.70de3acff368", locale: locale)
        case .busy: AppDataStrings.text("copy.dafb5d4bae01", locale: locale)
        case .upgradeRequired: AppDataStrings.text("copy.f92268007794", locale: locale)
        case .resyncRequired: AppDataStrings.text("copy.dcaee1a8b499", locale: locale)
        case .invalidData: AppDataStrings.text("copy.7fe3baa7c52d", locale: locale)
        case .invalidInput: AppDataStrings.text("copy.84f9c932bfcd", locale: locale)
        case .unavailableResource(let key): AppDataStrings.text(key, locale: locale)
        case .notAvailable(let message): message
        case .outcomeUnknown: AppDataStrings.text("copy.1b6fe0889add", locale: locale)
        case .failed: AppDataStrings.text("copy.4f3713e485e9", locale: locale)
        }
    }
    public var canRetry: Bool { self != .outcomeUnknown && self != .sdkUnavailable && self != .unsupported }
    public static func map(_ error: any Error) -> Self {
        if let failure = error as? Self { return failure }
        if let failure = error as? CoreFailure {
            if failure.effect == .unknown, failure.operationID != nil { return .outcomeUnknown }
            switch failure.code {
            case .unsupportedVersion, .schemaResetRequired: return .upgradeRequired
            case .authenticationFailed, .deviceRevoked, .permissionDenied, .custodyForkFenced: return .locked
            case .accountBusy, .rateLimited: return .busy
            case .transportUnavailable, .timeout, .closed: return .offline
            case .invalidArgument, .invalidCanonicalJSON: return .invalidInput
            default: return .failed
            }
        }
        if (error as? BridgeError) == .resyncRequired { return .resyncRequired }
        if error is UnavailableCapability { return .unsupported }
        return .failed
    }
}
