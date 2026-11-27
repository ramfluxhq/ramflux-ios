// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if RAMFLUX_CARD_GALLERY
import CRamflux
import Foundation

/// Realrun conformance binding of the standalone card runtime (`ramflux_card_*`, ABI 5) and of the bundled trust
/// package. Compiled only into test builds (`RAMFLUX_CARD_GALLERY`); the production path never reaches it.
///
/// Every call must run on the one thread that owns the runtime handles (`CardFixtureRuntime` in FeatureCards does
/// that). Callback bytes are borrowed only during the synchronous callback, so each call copies them out before it
/// returns. Status values keep the card namespace of `ramflux_card.h` (0 OK, 5 budget, 6 inactive, ...).
public enum CardFixtureNative {
    /// The answer of one standalone call: its status, the handle it produced, and the single callback JSON.
    public struct Reply: Sendable {
        public let status: Int32
        public let session: UInt64
        public let json: Data?
    }

    public static var abiVersion: UInt32 { ramflux_card_abi_version() }

    /// `ramflux_v2_card_trust_package`: the bundled trust package JSON (status 0 when the library carries one).
    public static func trustPackage() -> (status: Int32, json: Data?) {
        var out: UnsafeMutablePointer<RamfluxBuffer>?
        let status = ramflux_v2_card_trust_package(&out)
        guard let out else { return (status, nil) }
        return (status, try? NativeBuffers.take(out))
    }

    public static func open(spec: Data, trust: CardFixtureTrustMaterial, presentation: Data) -> Reply {
        let capture = CallbackCapture()
        var handle: UInt64 = 0
        let status: Int32 = withCardBytes(spec) { specBytes in
            withCardBytes(trust.bytecode) { bytecode in
                withCardBytes(trust.signature) { signature in
                    withCardBytes(trust.trustedKey) { trustedKey in
                        withCardBytes(trust.descriptor) { descriptor in
                            withCardBytes(trust.policy) { policy in
                                withCardBytes(presentation) { presentationBytes in
                                    var input = RamfluxCardOpen(spec: specBytes, bytecode: bytecode, signature: signature,
                                                                trusted_key: trustedKey, descriptor: descriptor, policy: policy,
                                                                presentation: presentationBytes)
                                    return ramflux_card_open(&input, collectCallback, capture.opaque, &handle)
                                }
                            }
                        }
                    }
                }
            }
        }
        return Reply(status: status, session: handle, json: capture.json)
    }

    public static func tree(_ session: UInt64) -> Reply {
        let capture = CallbackCapture()
        let status = ramflux_card_tree(session, collectCallback, capture.opaque)
        return Reply(status: status, session: session, json: capture.json)
    }

    public static func present(_ session: UInt64, presentation: Data) -> Reply {
        let capture = CallbackCapture()
        let status = withCardBytes(presentation) { ramflux_card_present(session, $0, collectCallback, capture.opaque) }
        return Reply(status: status, session: session, json: capture.json)
    }

    /// One host event: `{token, event}` as the runtime's HostEvent.
    public static func event(_ session: UInt64, input: Data) -> Reply {
        let capture = CallbackCapture()
        let status = withCardBytes(input) { ramflux_card_event(session, $0, collectCallback, capture.opaque) }
        return Reply(status: status, session: session, json: capture.json)
    }

    public static func suspend(_ session: UInt64) -> Reply {
        let capture = CallbackCapture()
        let status = ramflux_card_suspend(session, collectCallback, capture.opaque)
        return Reply(status: status, session: session, json: capture.json)
    }

    public static func resume(_ session: UInt64) -> Reply {
        let capture = CallbackCapture()
        let status = ramflux_card_resume(session, collectCallback, capture.opaque)
        return Reply(status: status, session: session, json: capture.json)
    }

    public static func dispose(_ session: UInt64) -> Int32 {
        ramflux_card_dispose(session)
    }

    /// Holds the bytes one synchronous callback delivers; it lives on the caller's stack for the call only.
    private final class CallbackCapture {
        var json: Data?
        var opaque: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }
    }

    private static let collectCallback: RamfluxCardCallback = { user, json, len in
        guard let user else { return }
        let capture = Unmanaged<CallbackCapture>.fromOpaque(user).takeUnretainedValue()
        if let json, len > 0 {
            capture.json = Data(bytes: json, count: len)
        } else {
            capture.json = Data()
        }
    }

    private static func withCardBytes<R>(_ data: Data, _ body: (RamfluxCardBytes) -> R) -> R {
        data.withUnsafeBytes { raw in
            body(RamfluxCardBytes(data: raw.baseAddress?.assumingMemoryBound(to: UInt8.self), len: raw.count))
        }
    }
}

/// The decoded key material and policy the standalone open call needs; the bytes are exactly what the trust package
/// carries (the descriptor is signed as its exact bytes).
public struct CardFixtureTrustMaterial: Sendable {
    public let bytecode: Data
    public let signature: Data
    public let trustedKey: Data
    public let descriptor: Data
    public let policy: Data

    public init(bytecode: Data, signature: Data, trustedKey: Data, descriptor: Data, policy: Data) {
        self.bytecode = bytecode; self.signature = signature; self.trustedKey = trustedKey
        self.descriptor = descriptor; self.policy = policy
    }
}
#endif
