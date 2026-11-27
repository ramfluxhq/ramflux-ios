// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import UIKit
import SwiftUI
import FeatureAppShell
import RFDesign

/// App-wide privacy for the system's app-switcher snapshot. When the scene is about to become inactive, an
/// opaque cover is shown over the scene, before the system takes the snapshot; it is removed when the scene is
/// active again. On every move to the background the system is also told not to reuse the snapshot on the next
/// launch. The cover is always on and is not tied to the app lock.
///
/// Both covers are their own `UIWindow`s at a level above alerts, so a presentation made later (an alert, a
/// sheet in the app's windows) cannot draw above them. The privacy cover is the topmost, for the snapshot.
@MainActor enum PrivacyCover {
    /// One cover window and the hosting controller that draws it.
    private struct CoverWindow {
        let window: UIWindow
        let controller: UIHostingController<AnyView>
    }
    private static var covers: [ObjectIdentifier: CoverWindow] = [:]
    /// The shell's own cover (failure and retry, app lock form). Above the alerts, below the privacy cover.
    private static var stateCovers: [ObjectIdentifier: CoverWindow] = [:]
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
            center.addObserver(forName: UIScene.didDisconnectNotification, object: nil, queue: .main) { note in
                let id = (note.object as? UIScene).map(ObjectIdentifier.init)
                MainActor.assumeIsolated { if let id { forget(id) } }
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
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) where covers[ObjectIdentifier(scene)] == nil {
            let content = AnyView(RFThemeScope(selection: appearance) { PrivacyCoverView() })
            covers[ObjectIdentifier(scene)] = makeCover(in: scene, level: .alert + 2, content: content)
        }
    }

    /// Shows or removes the state cover of every connected scene. Editing ends in the app's windows when the cover
    /// rises, so no text field keeps the keyboard active under it. The state cover is made key while it is up: a
    /// text field (the app lock's code field) takes first responder only in a key window. The privacy cover is
    /// never key. When the state cover goes, the scene's first normal window becomes key again.
    static func setStateCover(visible: Bool, appearance: String, content: () -> AnyView) {
        guard visible else {
            guard !stateCovers.isEmpty else { return }
            dismiss(&stateCovers)
            for scene in windowScenes() { scene.windows.first { $0.windowLevel == .normal }?.makeKey() }
            return
        }
        for scene in windowScenes() {
            for window in scene.windows where window.windowLevel == .normal { window.endEditing(true) }
            let cover: CoverWindow
            if let existing = stateCovers[ObjectIdentifier(scene)] {
                existing.window.isHidden = false
                cover = existing
            } else {
                let wrapped = AnyView(RFThemeScope(selection: appearance) { content() })
                cover = makeCover(in: scene, level: .alert + 1, content: wrapped)
                stateCovers[ObjectIdentifier(scene)] = cover
            }
            cover.window.makeKey()
        }
    }

    private static func windowScenes() -> [UIWindowScene] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    }

    /// Drops the covers of a scene that disconnected, so no window or controller outlives its scene.
    private static func forget(_ id: ObjectIdentifier) {
        covers.removeValue(forKey: id)?.window.rootViewController = nil
        stateCovers.removeValue(forKey: id)?.window.rootViewController = nil
    }

    /// Creates a cover window above alerts with the content as its only view; accessibility treats it as modal.
    private static func makeCover(in scene: UIWindowScene, level: UIWindow.Level, content: AnyView) -> CoverWindow {
        let controller = UIHostingController(rootView: AnyView(CoverScenePhaseBridge(scene: scene) { content }))
        controller.view.backgroundColor = .systemBackground
        controller.view.isOpaque = true
        controller.view.accessibilityViewIsModal = true
        let window = UIWindow(windowScene: scene)
        window.windowLevel = level
        window.backgroundColor = .systemBackground
        window.rootViewController = controller
        window.isHidden = false
        return CoverWindow(window: window, controller: controller)
    }

    private static func dismiss(_ entries: inout [ObjectIdentifier: CoverWindow]) {
        for entry in entries.values {
            entry.window.isHidden = true
            entry.window.rootViewController = nil
        }
        entries = [:]
    }

    private static func hide() { dismiss(&covers) }
}

/// A cover is hosted in its own `UIWindow`, outside the SwiftUI app scene, so its views do not receive the
/// scene's phase from SwiftUI (they read the default, never `.active`, and every view that is enabled only
/// while the scene is active, such as a confirmation, stayed disabled). This view follows the activation state
/// of the window scene that holds the cover and injects it as `scenePhase`.
private struct CoverScenePhaseBridge<Content: View>: View {
    let scene: UIWindowScene
    @ViewBuilder let content: () -> Content
    @State private var phase: ScenePhase

    init(scene: UIWindowScene, @ViewBuilder content: @escaping () -> Content) {
        self.scene = scene
        self.content = content
        _phase = State(initialValue: Self.phase(of: scene.activationState))
    }

    var body: some View {
        content()
            .environment(\.scenePhase, phase)
            .onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { note in
                if (note.object as? UIScene) === scene { phase = .active }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScene.willDeactivateNotification)) { note in
                if (note.object as? UIScene) === scene { phase = .inactive }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScene.didEnterBackgroundNotification)) { note in
                if (note.object as? UIScene) === scene { phase = .background }
            }
    }

    private static func phase(of state: UIScene.ActivationState) -> ScenePhase {
        switch state {
        case .foregroundActive: .active
        case .foregroundInactive: .inactive
        default: .background
        }
    }
}
