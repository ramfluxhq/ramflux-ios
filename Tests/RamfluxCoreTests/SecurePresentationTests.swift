// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import RamfluxCore
struct SecurePresentationTests {
    @Test func phraseFrameNeverNeedsJSONOrStringDecodingAndEraseRemovesPresentation() throws {
        let frame = try Array("{\"code\":0,\"response\":{\"body\":{\"phrase\":\"alpha bravo charlie\"}}}".utf8).withUnsafeBytes { try SecretBytes(copying: $0) }
        let display = try SecureDisplayBytes(phraseFrame: frame)
        #expect(frame.isErased)
        var count = 0; display.withBytes { count = $0.count }; #expect(count == 19)
        display.erase(); display.withBytes { _ in Issue.record("Erased display must not render") }
    }
    @Test func escapedDuplicateAndOversizedSecretFieldsRefuse() throws {
        for json in ["{\"phrase\":\"alpha\\nword\"}", "{\"phrase\":\"alpha\",\"phrase\":\"bravo\"}", "{\"phrase\":\"" + String(repeating: "a", count: 513) + "\"}"] {
            let frame = try Array(json.utf8).withUnsafeBytes { try SecretBytes(copying: $0) }
            #expect(throws: BridgeError.invalidResponse) { try SecureDisplayBytes(phraseFrame: frame) }
            #expect(frame.isErased)
        }
    }
    @Test func connectionLocalCeremoniesNeverRequireOperationKeys() {
        for operation in [SDKOperation.accountCreateBegin, .accountCreateShowOnce, .accountCreateHiddenChallenge, .accountCreateConfirm, .accountCreateCancel, .accountRecoverBegin, .accountRecoverConfirm, .accountRecoverCancel] { #expect(!operation.requiresOperationID) }
    }
}
