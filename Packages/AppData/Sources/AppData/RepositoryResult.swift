// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
public enum RepositoryResult<Value: Sendable>: Sendable {
    case success(Value)
    case failure(AppFailure)
}
extension RepositoryResult: Equatable where Value: Equatable {}
public extension RepositoryResult {
    /// Transforms a success value; a failure passes through.
    func map<Other: Sendable>(_ transform: (Value) -> Other) -> RepositoryResult<Other> {
        switch self { case .success(let value): .success(transform(value)); case .failure(let failure): .failure(failure) }
    }
}
public enum UnavailableReason: String, Sendable, Equatable {
    case nativeCoreMissing, featureNotInstalled, custodyProviderPending
    public var message: String { message(locale: .current) }
    public func message(locale: Locale) -> String {
        switch self {
        case .nativeCoreMissing: AppDataStrings.text("session.unavailable.nativeCore", locale: locale)
        case .featureNotInstalled: AppDataStrings.text("session.unavailable.featureNotInstalled", locale: locale)
        case .custodyProviderPending: AppDataStrings.text("session.unavailable.custodyProvider", locale: locale)
        }
    }
}
