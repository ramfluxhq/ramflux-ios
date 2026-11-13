// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if os(iOS)
import UIKit
import SwiftUI
import CoreText
import AppData
import RFDesign

public struct SecureOnboardingForm: View {
    @Environment(\.locale) private var locale
    public let labels: [(String, String)]
    public let enabled: Bool
    public let submit: (SensitiveSubmission) -> Void
    public var body: some View { RFSecretFields(labels: labels, enabled: enabled) { submit(SensitiveSubmission(values: $0)) } }
}
#endif
