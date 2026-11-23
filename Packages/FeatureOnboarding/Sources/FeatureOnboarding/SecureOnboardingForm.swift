// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import UIKit
import SwiftUI
import CoreText
import AppData
import RFDesign

public struct SecureOnboardingForm: View {
    public let fields: [RFSecureEntryField]
    public let accountCode: SensitiveSubmission.AccountCodeRule?
    public let enabled: Bool
    public let submit: (SensitiveSubmission) -> Void
    public var body: some View { RFSecureEntryForm(fields: fields, enabled: enabled) { submit(SensitiveSubmission(values: $0, accountCode: accountCode)) } }
}
#endif
