// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import Foundation
import ImageIO
@testable import RFMedia

@Suite struct GIFSanitizerTests {
    /// A 1x1 two-frame GIF with a global palette, looping, a comment, an XMP packet and junk
    /// after the trailer.
    static func sample() -> (input: Data, expected: Data) {
        let header: [UInt8] = Array("GIF89a".utf8) + [1, 0, 1, 0, 0x80, 0, 0] + [0, 0, 0, 255, 255, 255]
        let loop: [UInt8] = [0x21, 0xFF, 11] + Array("NETSCAPE2.0".utf8) + [3, 1, 0, 0, 0]
        let comment: [UInt8] = [0x21, 0xFE, 5] + Array("hello".utf8) + [0]
        let xmp: [UInt8] = [0x21, 0xFF, 11] + Array("XMP DataXMP".utf8) + [4] + Array("gps!".utf8) + [0]
        let control: [UInt8] = [0x21, 0xF9, 4, 0x04, 10, 0, 0, 0]
        let frame: [UInt8] = [0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, 2, 0x4C, 0x01, 0]
        let input = header + loop + comment + control + frame + xmp + control + frame + [0x3B] + Array("trailing".utf8)
        let expected = header + loop + control + frame + control + frame + [0x3B]
        return (Data(input), Data(expected))
    }

    @Test func dropsCommentsApplicationMetadataAndTrailingBytesButKeepsFramesExactly() throws {
        let sample = Self.sample()
        let stripped = try #require(GIFSanitizer.strip(sample.input))
        #expect(stripped == sample.expected)
        #expect(stripped.range(of: Data("gps!".utf8)) == nil); #expect(stripped.range(of: Data("hello".utf8)) == nil)
        let source = try #require(CGImageSourceCreateWithData(stripped as CFData, nil))
        #expect(CGImageSourceGetCount(source) == 2)
        #expect(GIFSanitizer.strip(sample.expected) == sample.expected)
    }

    @Test func refusesTruncatedOrForeignFiles() {
        let sample = Self.sample()
        #expect(GIFSanitizer.strip(sample.input.prefix(40)) == nil)
        #expect(GIFSanitizer.strip(Data("not a gif at all".utf8)) == nil)
    }
}

@Suite struct AutoplaySlotsTests {
    @Test func atMostTwoAnimationsPlayAndSlotsReturnWhenRowsDisappear() {
        let slots = AutoplaySlots(capacity: 2)
        #expect(slots.acquire("a")); #expect(slots.acquire("b")); #expect(!slots.acquire("c")); #expect(slots.acquire("a"))
        slots.release("a")
        #expect(slots.acquire("c")); #expect(slots.active == 2)
    }

    @Test func policyRefusesReduceMotionLowPowerConstrainedAndStillImages() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try GIFSanitizerTests.sample().expected.write(to: file)
        #expect(AutoplaySlots.allowed(file: file, reduceMotion: false, lowPower: false, constrained: false))
        #expect(!AutoplaySlots.allowed(file: file, reduceMotion: true, lowPower: false, constrained: false))
        #expect(!AutoplaySlots.allowed(file: file, reduceMotion: false, lowPower: true, constrained: false))
        #expect(!AutoplaySlots.allowed(file: file, reduceMotion: false, lowPower: false, constrained: true))
    }
}
