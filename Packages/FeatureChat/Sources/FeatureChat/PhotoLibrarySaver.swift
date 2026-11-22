// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
#if canImport(Photos) && os(iOS)
import Photos
#endif

/// Saves one image to Photos with add-only access, after the shared permission flow granted it.
/// The app never asks for read access to the library.
enum PhotoLibrarySaver {
    static func save(_ url: URL) async -> Bool {
        #if canImport(Photos) && os(iOS)
        guard PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized else { return false }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .photo, fileURL: url, options: options)
            }, completionHandler: { success, _ in continuation.resume(returning: success) })
        }
        #else
        return false
        #endif
    }
}
