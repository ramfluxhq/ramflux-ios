// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import CRamflux

struct NativeBuffers {
    static func take(_ pointer: UnsafeMutablePointer<RamfluxBuffer>?) throws -> Data {
        guard let pointer else { throw BridgeError.invalidResponse }
        defer { rf_buffer_wipe_free(pointer) }
        let buffer = pointer.pointee
        guard buffer.len <= CoreLimits.frameBytes, buffer.len == 0 || buffer.ptr != nil else {
            throw BridgeError.responseTooLarge
        }
        guard let bytes = buffer.ptr, buffer.len > 0 else { return Data() }
        return Data(bytes: bytes, count: buffer.len)
    }
}
