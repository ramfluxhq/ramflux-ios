// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Keeps an active upload or download running when the app moves to the background, to the
/// extent iOS allows with the SDK in this process (media design 5.10):
/// - The transfer is wrapped in a background task assertion. iOS grants a short, unspecified
///   amount of time (about 30 seconds in practice) and then suspends the app.
/// - A background URL session cannot be used: encryption, upload and import run inside the SDK
///   over its gateway session, which lives only in the app process.
/// - When the time expires the assertion ends. The SDK work is suspended with the process; the
///   send stays in the sealed outbox and resumes with the same operation id when the app is
///   active again (an import restarts, because the SDK keeps import handles in memory only).
/// - Continued processing tasks need system UI per user-started task and are not used yet.
public protocol MediaBackgroundAssertion: Sendable {
    func begin(_ name: String) async -> any MediaBackgroundToken
}
public protocol MediaBackgroundToken: Sendable { func end() async }

enum MediaBackgroundTransfer {
    /// Runs `work` under an assertion that ends when the work finishes or iOS revokes it.
    static func run<T: Sendable>(_ assertion: any MediaBackgroundAssertion, name: String, _ work: () async -> T) async -> T {
        let token = await assertion.begin(name)
        let result = await work()
        await token.end()
        return result
    }
}

struct NoBackgroundAssertion: MediaBackgroundAssertion {
    private struct Token: MediaBackgroundToken { func end() async {} }
    func begin(_ name: String) async -> any MediaBackgroundToken { Token() }
}

#if canImport(UIKit) && !os(watchOS)
/// `UIApplication.beginBackgroundTask` around one transfer. The expiration handler ends the
/// task at once, as iOS requires.
struct ApplicationBackgroundAssertion: MediaBackgroundAssertion {
    @MainActor private final class Assertion: MediaBackgroundToken {
        var identifier: UIBackgroundTaskIdentifier = .invalid
        nonisolated func end() async { await MainActor.run { finish() } }
        func finish() {
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier); identifier = .invalid
        }
    }
    func begin(_ name: String) async -> any MediaBackgroundToken {
        await MainActor.run {
            let task = Assertion()
            task.identifier = UIApplication.shared.beginBackgroundTask(withName: name) { task.finish() }
            return task
        }
    }
}
#endif

extension MediaBackgroundTransfer {
    static var system: any MediaBackgroundAssertion {
        #if canImport(UIKit) && !os(watchOS)
        ApplicationBackgroundAssertion()
        #else
        NoBackgroundAssertion()
        #endif
    }
}
