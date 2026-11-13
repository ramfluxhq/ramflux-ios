// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
public enum ViewLoadState<Value: Sendable>: Sendable {
    case idle, loading, loaded(Value), failed(AppFailure)
}
extension ViewLoadState: Equatable where Value: Equatable {}
