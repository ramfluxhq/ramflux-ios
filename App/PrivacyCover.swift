// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import UIKit
import SwiftUI
import FeatureAppShell
import RFDesign

/// App-wide privacy for the system's app-switcher snapshot. When the scene is about to become inactive, an
/// opaque cover is added over every normal-level window of the scene (so it also hides sheets), before the
/// system takes the snapshot; it is removed when the scene is active again. On every move to the background
/// the system is also told not to reuse the snapshot on the next launch. The cover is always on and is not
/// tied to the app lock.
@MainActor enum PrivacyCover {
    private static var covers: [ObjectIdentifier: (window: UIWindow, controller: UIHostingController<AnyView>)] = [:]
    /// The shell's own cover (privacy shield, app lock form): a window subview too, so no sheet renders above it.
    private static var stateCovers: [ObjectIdentifier: UIHostingController<AnyView>] = [:]
    private static var observers: [NSObjectProtocol] = []
    /// The cover stays up after the scene became active while the app lock may engage; it is released once the
    /// activation has read the lock (`releaseAppLockHold`). A window cover sits above the SwiftUI content, so it
    /// also hides the pushed screens that a shell-level shield would not reach.
    private static var heldForAppLock = false

    /// Registers the scene lifecycle observers once. `resigning` runs first when the scene will become
    /// inactive (the composition dismisses the banner there) and `activated` when it became active.
    /// `holdsForAppLock` says whether the cover must stay up on activation (lock on or unknown).
    static func install(appearance: @escaping @MainActor () -> String, resigning: @escaping @MainActor () -> Void,
                        activated: @escaping @MainActor () -> Void, holdsForAppLock: @escaping @MainActor () -> Bool) {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { resigning(); show(appearance: appearance()) }
            },
            center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    if holdsForAppLock() { heldForAppLock = true } else { hide() }
                    activated()
                }
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { show(appearance: appearance()); UIApplication.shared.ignoreSnapshotOnNextApplicationLaunch() }
            },
        ]
    }

    /// Lets go of the cover held for the app lock, once the activation has answered. Covers taken for a later
    /// inactive phase are not touched: `heldForAppLock` is cleared whenever the cover is shown again.
    static func releaseAppLockHold() {
        guard heldForAppLock else { return }
        heldForAppLock = false
        hide()
    }

    private static func show(appearance: String) {
        heldForAppLock = false
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where window.windowLevel == .normal && covers[ObjectIdentifier(window)] == nil {
                let controller = UIHostingController(rootView: AnyView(RFThemeScope(selection: appearance) { PrivacyCoverView() }))
                controller.view.frame = window.bounds
                controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                controller.view.backgroundColor = .systemBackground
                controller.view.isOpaque = true
                controller.view.accessibilityViewIsModal = true
                window.addSubview(controller.view)
                covers[ObjectIdentifier(window)] = (window, controller)
            }
        }
    }

    /// Shows or removes the state cover on every normal-level window of the scene, always as the topmost subview.
    static func setStateCover(visible: Bool, appearance: String, content: () -> AnyView) {
        guard visible else {
            for controller in stateCovers.values { controller.view.removeFromSuperview() }
            stateCovers = [:]
            return
        }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where window.windowLevel == .normal {
                if let existing = stateCovers[ObjectIdentifier(window)] { window.bringSubviewToFront(existing.view); continue }
                let controller = UIHostingController(rootView: AnyView(RFThemeScope(selection: appearance) { content() }))
                controller.view.frame = window.bounds
                controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                controller.view.backgroundColor = .systemBackground
                controller.view.isOpaque = true
                controller.view.accessibilityViewIsModal = true
                window.addSubview(controller.view)
                stateCovers[ObjectIdentifier(window)] = controller
            }
        }
    }

    private static func hide() {
        for entry in covers.values { entry.controller.view.removeFromSuperview() }
        covers = [:]
    }
}
