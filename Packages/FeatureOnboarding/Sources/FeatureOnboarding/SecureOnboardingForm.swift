// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import UIKit
import SwiftUI
import CoreText
import AppData
import RFDesign

public struct SecureOnboardingForm: View {
    public let steps: [RFSecureEntryStep]
    public let accountCode: SensitiveSubmission.AccountCodeRule?
    public let enabled: Bool
    public let mismatchMessage: String?
    public let submit: (SensitiveSubmission) -> Void
    public init(steps: [RFSecureEntryStep], accountCode: SensitiveSubmission.AccountCodeRule?, enabled: Bool, mismatchMessage: String? = nil, submit: @escaping (SensitiveSubmission) -> Void) {
        self.steps = steps; self.accountCode = accountCode; self.enabled = enabled; self.mismatchMessage = mismatchMessage; self.submit = submit
    }
    public init(fields: [RFSecureEntryField], submitLabel: String, helper: String? = nil, accountCode: SensitiveSubmission.AccountCodeRule?, enabled: Bool, submit: @escaping (SensitiveSubmission) -> Void) {
        self.init(steps: [RFSecureEntryStep(fields: fields, helper: helper, actionLabel: submitLabel)], accountCode: accountCode, enabled: enabled, submit: submit)
    }
    public var body: some View {
        RFSecureEntryForm(steps: steps, enabled: enabled, mismatchMessage: mismatchMessage) { submit(SensitiveSubmission(values: $0, accountCode: accountCode)) }
    }
}
#endif
