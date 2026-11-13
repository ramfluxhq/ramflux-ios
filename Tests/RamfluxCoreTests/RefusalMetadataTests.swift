// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import CRamflux
@testable import RamfluxCore
struct RefusalMetadataTests {
    private func reason(_ frame: String) -> String? {
        var data = Array(frame.utf8)
        return data.withUnsafeMutableBufferPointer { bytes in
            var buffer = RamfluxBuffer(ptr: bytes.baseAddress, len: bytes.count)
            return rf_completion_refusal_reason(&buffer).map { String(cString: $0) }
        }
    }
    @Test func borrowedScannerReadsOnlyAllowlistedErrorPath() {
        #expect(reason(#"{"code":16,"response":{"error":{"message":"secret input","details":{"reason_code":"vault_locked"},"reason_code":"vault_permission"}}}"#) == "vault_permission")
        #expect(reason(#"{"code":0,"response":{"error":{"reason_code":"vault_permission"},"body":{"phrase":"not an error"}}}"#) == nil)
        #expect(reason(#"{"code":16,"reason_code":"vault_permission","response":{"error":{"reason_code":"peer-controlled message"}}}"#) == nil)
        #expect(reason(#"{"code":16,"response":{"error":{"reason_code":"vault_locked","reason_code":"vault_permission"}}}"#) == nil)
        #expect(reason(#"{"code":16,"response":{"error":{"reason_code":"vault_permission"}}"#) == nil)
    }
}
