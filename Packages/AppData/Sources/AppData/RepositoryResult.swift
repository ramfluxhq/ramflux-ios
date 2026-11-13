// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public enum RepositoryResult<Value: Sendable>: Sendable {
    case success(Value)
    case failure(AppFailure)
}
extension RepositoryResult: Equatable where Value: Equatable {}
public enum UnavailableReason: String, Sendable, Equatable {
    case nativeCoreMissing, featureNotInstalled, custodyProviderPending
    public var message: String {
        switch self {
        case .nativeCoreMissing: "Account services are unavailable in this build. Saved data has not been changed."
        case .featureNotInstalled: "This feature module is not installed yet."
        case .custodyProviderPending: "Account setup requires the phone's protected key provider."
        }
    }
}
