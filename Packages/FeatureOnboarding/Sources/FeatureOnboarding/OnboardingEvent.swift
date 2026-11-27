// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
public enum OnboardingEvent: Equatable, Sendable { case completed(AccountRecord), accountCreated(AccountRecord), dismissed, presentRecovery(UUID, RecoveryDisplay), revokeRecovery
    /// Recover on a new install from a backup archive (the backup screen without an account).
    case restoreBackup
    /// Remove a known account from this device's registry (the SDK refused to unlock it).
    case forgetAccount(String)
    /// The recovery of the locked account in the lock cover ended with a refusal that changes what the lock screen shows
    /// (the code wait after an accepted phrase, a wrong code, exhausted checks). The host closes the recovery and reads the
    /// app-lock state again.
    case lockRecoveryEnded(AppFailure)
}
