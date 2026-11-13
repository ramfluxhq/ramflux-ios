// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
#if os(iOS)
import AVFAudio
#endif
public struct NativeMicrophoneRepository: MicrophoneRepository {
    public init() {}
    public func status() async -> MicrophoneStatus {
        #if os(iOS)
        return await MainActor.run {
            switch AVAudioApplication.shared.recordPermission {
            case .undetermined: .undetermined
            case .denied: .denied
            case .granted: .granted
            @unknown default: .unavailable
            }
        }
        #else
        return .unavailable
        #endif
    }
}
