// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import UIKit

/// Reports whether the scene is being captured (screen recording, mirroring, AirPlay) by following the
/// scene's `sceneCaptureState` trait. It draws nothing and takes no touches.
struct CaptureStateProbe: UIViewRepresentable {
    @Binding var captured: Bool
    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = { value in if captured != value { captured = value } }
        return view
    }
    func updateUIView(_ view: ProbeView, context: Context) {
        view.onChange = { value in if captured != value { captured = value } }
        view.report()
    }

    final class ProbeView: UIView {
        var onChange: ((Bool) -> Void)?
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false; isAccessibilityElement = false
            registerForTraitChanges([UITraitSceneCaptureState.self]) { (view: ProbeView, _) in view.report() }
        }
        required init?(coder: NSCoder) { nil }
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        /// Deferred one turn: the report can arrive inside a SwiftUI update, where state may not change.
        func report() { let active = traitCollection.sceneCaptureState == .active; DispatchQueue.main.async { [weak self] in self?.onChange?(active) } }
    }
}
