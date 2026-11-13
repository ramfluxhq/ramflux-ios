// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData
/// The host owns this presentation capability; replayable State contains only its opaque ID.
@Observable @MainActor public final class SecureRecoverySlot {
    private var id: UUID?
    @ObservationIgnored private var display: RecoveryDisplay?
    public init() {}
    public func install(id: UUID, display: RecoveryDisplay) { revoke(); self.id = id; self.display = display }
    public func revoke() { display?.erase(); display = nil; id = nil }
    public func presentation(for id: UUID) -> RecoveryDisplay? { self.id == id ? display : nil }
    deinit { display?.erase() }
}
