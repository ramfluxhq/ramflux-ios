// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization

/// Timeline autoplay of animated images (media design 4.2): only while the row is visible, at
/// most two at once, never with Reduce Motion, Low Power Mode or a constrained network, and only
/// under the frame budget. Video never plays in the timeline. A row asks for a slot when it
/// appears and returns it when it disappears; a row without a slot shows its first frame.
public final class AutoplaySlots: Sendable {
    public static let timeline = AutoplaySlots(capacity: 2)
    public let capacity: Int
    private let holders = Mutex<[String]>([])
    public init(capacity: Int) { self.capacity = capacity }

    /// True when `id` holds a slot (already or newly granted).
    public func acquire(_ id: String) -> Bool {
        holders.withLock { list in
            if list.contains(id) { return true }
            guard list.count < capacity else { return false }
            list.append(id); return true
        }
    }
    public func release(_ id: String) { holders.withLock { $0.removeAll { $0 == id } } }
    public var active: Int { holders.withLock { $0.count } }

    /// The policy part that does not depend on slots: reads the header off the caller's thread.
    public static func allowed(file: URL, reduceMotion: Bool, lowPower: Bool, constrained: Bool) -> Bool {
        !constrained && AnimatedImage.shouldAnimate(file: file, reduceMotion: reduceMotion, lowPower: lowPower)
    }
}
