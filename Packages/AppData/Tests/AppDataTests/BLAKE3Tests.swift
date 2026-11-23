// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import Foundation
@testable import AppData

/// BLAKE3 vectors for inputs of byte i % 251, produced by the official C implementation, and
/// one-shot vectors produced by the reference `blake3` 1.8.7 crate (formerly the direct conversation id's
/// single-chunk tests).
@Suite struct BLAKE3Tests {
    static let vectors: [(Int, String)] = [
        (0, "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"),
        (1, "2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213"),
        (63, "e9bc37a594daad83be9470df7f7b3798297c3d834ce80ba85d6e207627b7db7b"),
        (64, "4eed7141ea4a5cd4b788606bd23f46e212af9cacebacdc7d1f4c6dc7f2511b98"),
        (65, "de1e5fa0be70df6d2be8fffd0e99ceaa8eb6e8c93a63f2d8d1c30ecb6b263dee"),
        (1023, "10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11"),
        (1024, "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7"),
        (1025, "d00278ae47eb27b34faecf67b4fe263f82d5412916c1ffd97c8cb7fb814b8444"),
        (2048, "e776b6028c7cd22a4d0ba182a8bf62205d2ef576467e838ed6f2529b85fba24a"),
        (2049, "5f4d72f40d7a5f82b15ca2b2e44b1de3c2ef86c426c95c1af0b6879522563030"),
        (3072, "b98cb0ff3623be03326b373de6b9095218513e64f1ee2edd2525c7ad1e5cffd2"),
        (3073, "7124b49501012f81cc7f11ca069ec9226cecb8a2c850cfe644e327d22d3e1cd3"),
        (4096, "015094013f57a5277b59d8475c0501042c0b642e531b0a1c8f58d2163229e969"),
        (4097, "9b4052b38f1c5fc8b1f9ff7ac7b27cd242487b3d890d15c96a1c25b8aa0fb995"),
        (8192, "aae792484c8efe4f19e2ca7d371d8c467ffb10748d8a5a1ae579948f718a2a63"),
        (8193, "bab6c09cb8ce8cf459261398d2e7aef35700bf488116ceb94a36d0f5f1b7bc3b"),
        (31744, "62b6960e1a44bcc1eb1a611a8d6235b6b4b78f32e7abc4fb4c6cdcce94895c47"),
        (102400, "bc3e3d41a1146b069abffad3c0d44860cf664390afce4d9661f7902e7943e085"),
        (524288, "b467afa334cd7dedd76e3a9a4b0e8a5ed278713f2f4e220a682aa30c7fcd140b"),
        (1048577, "2f053cd7472cf0cd2f9adaf45c1180255b91b9a865404a63671a0ee5f792ed33"),
    ]
    @Test(arguments: [1, 7, 64, 1000, 524_288]) func vectorsMatchForEveryUpdateSize(_ step: Int) {
        for (length, expected) in Self.vectors {
            let input = Data((0..<length).map { UInt8($0 % 251) })
            var digest = BLAKE3()
            var offset = 0
            while offset < input.count { let end = min(input.count, offset + step); digest.update(input[offset..<end]); offset = end }
            #expect(digest.hex() == expected, "length \(length) step \(step)")
        }
    }
    private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
    @Test func oneShotHashMatchesTheReferenceCrate() {
        #expect(hex(BLAKE3.hash([])) == "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262")
        #expect(hex(BLAKE3.hash(Array("abc".utf8))) == "6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85")
        #expect(hex(BLAKE3.hash([UInt8](repeating: 1, count: 64))) == "29c04cc4ce7b05d941850b358b7dfd7e6285cc54e63e2e239804c1781c3d2497")
        #expect(hex(BLAKE3.hash([UInt8](repeating: 7, count: 131))) == "b50716c931c8f7291ac3d5f6839b90ea1a60be115adbb61e473e2a1b542b8fd5")
        #expect(hex(BLAKE3.hash([UInt8](repeating: 2, count: 1024))) == "fa8af17567c147993830cdd42cea9d8a8f157c9b98b4e7ef5677f417a5d8ae61")
        let long = (0..<1025).map { UInt8($0 % 251) }
        #expect(hex(BLAKE3.hash(long)) == "d00278ae47eb27b34faecf67b4fe263f82d5412916c1ffd97c8cb7fb814b8444")
    }
}
