// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
public enum OnboardingEvent: Equatable, Sendable { case completed(AccountRecord), dismissed, presentRecovery(UUID, RecoveryDisplay), revokeRecovery }
