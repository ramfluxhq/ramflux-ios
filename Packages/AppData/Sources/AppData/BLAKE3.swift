// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// The app's one BLAKE3 (unkeyed hash mode, 32-byte output, any input length), incremental.
/// Users: attachment digests (the SDK's `PlaintextDigester`, whose lowercase hex
/// `attachment.prepare.finish` requires as `plaintext_digest`), card surface hashes and the direct
/// conversation id (`DirectConversationID`). A port of the BLAKE3 reference implementation; verified
/// against the official test vectors and the reference crate's outputs in `BLAKE3Tests`.
struct BLAKE3 {
    private static let iv: [UInt32] = [0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19]
    private static let permutation = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8]
    private static let chunkStart: UInt32 = 1, chunkEnd: UInt32 = 2, parent: UInt32 = 4, root: UInt32 = 8
    private static let blockLength = 64, chunkLength = 1024

    private struct Output {
        let chaining: [UInt32]; let block: [UInt32]; let counter: UInt64; let length: UInt32; let flags: UInt32
        func chainingValue() -> [UInt32] { Array(BLAKE3.compress(chaining, block, counter, length, flags).prefix(8)) }
        func rootBytes() -> [UInt8] {
            let words = BLAKE3.compress(chaining, block, 0, length, flags | BLAKE3.root)
            return words.prefix(8).flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) } }
        }
    }
    private struct ChunkState {
        var chaining: [UInt32]; let counter: UInt64; var block = [UInt8](repeating: 0, count: 64); var blockLength = 0; var compressed = 0
        init(_ key: [UInt32], _ counter: UInt64) { chaining = key; self.counter = counter }
        var length: Int { BLAKE3.blockLength * compressed + blockLength }
        var startFlag: UInt32 { compressed == 0 ? BLAKE3.chunkStart : 0 }
        mutating func update(_ input: UnsafeRawBufferPointer) {
            var offset = 0
            while offset < input.count {
                if blockLength == BLAKE3.blockLength {
                    chaining = Array(BLAKE3.compress(chaining, BLAKE3.words(block), counter, UInt32(BLAKE3.blockLength), startFlag).prefix(8))
                    compressed += 1; block = [UInt8](repeating: 0, count: 64); blockLength = 0
                }
                let take = min(BLAKE3.blockLength - blockLength, input.count - offset)
                for index in 0..<take { block[blockLength + index] = input[offset + index] }
                blockLength += take; offset += take
            }
        }
        func output() -> Output { Output(chaining: chaining, block: BLAKE3.words(block), counter: counter, length: UInt32(blockLength), flags: startFlag | BLAKE3.chunkEnd) }
    }

    private var chunk = ChunkState(BLAKE3.iv, 0)
    private var stack: [[UInt32]] = []

    mutating func update(_ data: Data) { data.withUnsafeBytes { update($0) } }
    mutating func update(_ input: UnsafeRawBufferPointer) {
        var offset = 0
        while offset < input.count {
            if chunk.length == Self.chunkLength {
                var chaining = chunk.output().chainingValue()
                var total = chunk.counter + 1
                while total & 1 == 0 { chaining = Self.parentOutput(stack.removeLast(), chaining).chainingValue(); total >>= 1 }
                stack.append(chaining)
                chunk = ChunkState(Self.iv, chunk.counter + 1)
            }
            let take = min(Self.chunkLength - chunk.length, input.count - offset)
            chunk.update(UnsafeRawBufferPointer(rebasing: input[offset..<(offset + take)]))
            offset += take
        }
    }
    /// The 32-byte digest.
    func digest() -> [UInt8] {
        var output = chunk.output()
        for chaining in stack.reversed() { output = Self.parentOutput(chaining, output.chainingValue()) }
        return output.rootBytes()
    }
    /// The 32-byte digest as lowercase hex.
    func hex() -> String { digest().map { String(format: "%02x", $0) }.joined() }
    /// One-shot digest of `bytes`.
    static func hash(_ bytes: [UInt8]) -> [UInt8] {
        var hasher = BLAKE3(); bytes.withUnsafeBytes { hasher.update($0) }; return hasher.digest()
    }

    private static func parentOutput(_ left: [UInt32], _ right: [UInt32]) -> Output {
        Output(chaining: iv, block: left + right, counter: 0, length: UInt32(blockLength), flags: parent)
    }
    private static func words(_ bytes: [UInt8]) -> [UInt32] {
        // Sixteen little-endian words. Written as plain loops with typed locals: the
        // nested closure form exceeds the type checker's time limit on older toolchains.
        var result = [UInt32](repeating: 0, count: 16)
        for index in 0..<16 {
            var word: UInt32 = 0
            for byte in 0..<4 {
                let value = UInt32(bytes[index * 4 + byte])
                let shift = UInt32(8 * byte)
                word |= value << shift
            }
            result[index] = word
        }
        return result
    }
    private static func compress(_ chaining: [UInt32], _ block: [UInt32], _ counter: UInt64, _ length: UInt32, _ flags: UInt32) -> [UInt32] {
        var state = chaining + Array(iv.prefix(4)) + [UInt32(truncatingIfNeeded: counter), UInt32(truncatingIfNeeded: counter >> 32), length, flags]
        var message = block
        func g(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt32, _ y: UInt32) {
            state[a] = state[a] &+ state[b] &+ x; state[d] = (state[d] ^ state[a]).rotatedRight(16)
            state[c] = state[c] &+ state[d]; state[b] = (state[b] ^ state[c]).rotatedRight(12)
            state[a] = state[a] &+ state[b] &+ y; state[d] = (state[d] ^ state[a]).rotatedRight(8)
            state[c] = state[c] &+ state[d]; state[b] = (state[b] ^ state[c]).rotatedRight(7)
        }
        for round in 0..<7 {
            g(0, 4, 8, 12, message[0], message[1]); g(1, 5, 9, 13, message[2], message[3])
            g(2, 6, 10, 14, message[4], message[5]); g(3, 7, 11, 15, message[6], message[7])
            g(0, 5, 10, 15, message[8], message[9]); g(1, 6, 11, 12, message[10], message[11])
            g(2, 7, 8, 13, message[12], message[13]); g(3, 4, 9, 14, message[14], message[15])
            if round < 6 { message = permutation.map { message[$0] } }
        }
        for index in 0..<8 { state[index] ^= state[index + 8]; state[index + 8] ^= chaining[index] }
        return state
    }
}

private extension UInt32 {
    func rotatedRight(_ count: UInt32) -> UInt32 { (self >> count) | (self << (32 - count)) }
}
