// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
public enum RepositoryResult<Value: Sendable>: Sendable {
    case success(Value)
    case failure(AppFailure)
}
extension RepositoryResult: Equatable where Value: Equatable {}
public enum UnavailableReason: String, Sendable, Equatable {
    case nativeCoreMissing, featureNotInstalled, custodyProviderPending
    public var message: String { message(locale: .current) }
    public func message(locale: Locale) -> String {
        switch self {
        case .nativeCoreMissing: AppDataStrings.text("copy.7cca3d86d331", locale: locale)
        case .featureNotInstalled: AppDataStrings.text("copy.6d135fefd8df", locale: locale)
        case .custodyProviderPending: AppDataStrings.text("copy.11cc2995d69e", locale: locale)
        }
    }
}
