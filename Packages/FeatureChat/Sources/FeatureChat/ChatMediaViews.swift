// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import AppData
import RFDesign
import RFLocalization
import RFMedia
#if os(iOS)
import PhotosUI
import QuickLook
import UIKit
#endif

/// One attachment in the timeline: an image box sized only from data in the message (so the row
/// never changes height when the download completes), or the Kit file card with its state.
struct MediaAttachmentView: View {
    let attachment: AttachmentRecord
    let state: MediaTransferState
    let revealed: Bool
    let isOwn: Bool
    let time: String?
    let onAction: (ChatAction) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    var body: some View {
        if attachment.kind == .image || attachment.kind == .animated {
            imageBox
        } else {
            Button { onAction(.mediaTapped(attachment.id)) } label: {
                KitBubble("", kind: .file, time: time, fileName: attachment.name, fileMeta: ChatMediaText.fileMeta(attachment, state: state, locale: locale), fileIcon: ChatAttachmentText.icon(attachment), tag: attachment.id)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(ChatMediaText.accessibility(attachment, state: state, locale: locale)))
        }
    }
    private var imageBox: some View {
        Color.clear
            .aspectRatio(attachment.aspectRatio ?? 4.0 / 3.0, contentMode: .fit)
            .frame(maxWidth: ChatMediaText.boxWidth)
            .overlay { content.background(theme.surface) }
            .overlay { status }
            .clipShape(RoundedRectangle(cornerRadius: theme.radius_bubble))
            .contentShape(Rectangle())
            .onTapGesture { onAction(.mediaTapped(attachment.id)) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(ChatMediaText.accessibility(attachment, state: state, locale: locale)))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onAction(.mediaTapped(attachment.id)) }
    }
    @ViewBuilder private var content: some View {
        if case .ready(let url) = state {
            PipelineImage(source: .file(url), maxPixel: ChatMediaText.bubblePixels)
        } else if let thumbnail = attachment.thumbnail, state != .blockedByPolicy || revealed, state != .removed {
            PipelineImage(source: .data(thumbnail.data, attachment.id), maxPixel: ChatMediaText.bubblePixels).blur(radius: 6)
        } else {
            theme.surface
        }
    }
    @ViewBuilder private var status: some View {
        switch state {
        case .ready: EmptyView()
        case .downloading:
            ProgressView().padding(theme.gap).background(theme.scrim, in: Circle())
                .onTapGesture { onAction(.cancelMedia(attachment.id)) }
        case .idle, .failed:
            VStack(spacing: theme.gap / 2) {
                KitIcon(name: state == .idle ? "download" : "refresh-cw", size: KitMetrics.iconInfo, tint: theme.text)
                Text(ChatMediaText.stateLine(attachment, state: state, locale: locale)).rfFont(.caption).multilineTextAlignment(.center)
            }.padding(theme.gap).background(theme.overlay, in: RoundedRectangle(cornerRadius: theme.radius_md))
        case .blockedByPolicy:
            VStack(spacing: theme.gap / 2) {
                Text(FeatureChatStrings.text("chat.media.untrusted", locale: locale)).rfFont(.caption).multilineTextAlignment(.center)
                HStack(spacing: theme.gap) {
                    if attachment.thumbnail != nil && !revealed { Button(FeatureChatStrings.text("chat.media.show", locale: locale)) { onAction(.revealMedia(attachment.id)) } }
                    Button(FeatureChatStrings.text("chat.media.download", locale: locale)) { onAction(.mediaTapped(attachment.id)) }
                }.rfFont(.caption)
            }.padding(theme.gap).background(theme.overlay, in: RoundedRectangle(cornerRadius: theme.radius_md))
        case .expired, .removed, .notAvailable:
            Text(ChatMediaText.stateLine(attachment, state: state, locale: locale)).rfFont(.caption).multilineTextAlignment(.center)
                .padding(theme.gap).background(theme.overlay, in: RoundedRectangle(cornerRadius: theme.radius_md))
        }
    }
}

/// An image decoded by the shared pipeline: downsampled off the main thread, cancelled when the
/// view goes away.
struct PipelineImage: View {
    enum Source: Equatable { case file(URL), data(Data, String) }
    let source: Source
    let maxPixel: Int
    @State private var image: CGImage?
    var body: some View {
        Group {
            if let image { Image(decorative: image, scale: 1).resizable().scaledToFill() } else { Color.clear }
        }
        .task(id: source) {
            switch source {
            case .file(let url): image = await ImagePipeline.shared.image(file: url, maxPixel: maxPixel)
            case .data(let data, let id): image = await ImagePipeline.shared.image(data: data, id: id, maxPixel: maxPixel)
            }
        }
    }
}

/// The in-flight or failed attachment send, drawn under the timeline.
struct MediaSendRow: View {
    let pending: MediaSendState
    let onAction: (ChatAction) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    var body: some View {
        HStack(spacing: theme.gap) {
            if let failure = pending.failure {
                KitIcon(name: "circle-alert", size: KitMetrics.iconInfo, tint: theme.danger)
                Text(ChatMediaText.sendFailure(failure, locale: locale)).rfFont(.caption).frame(maxWidth: .infinity, alignment: .leading)
                if failure.canRetry || failure == .offline { Button(FeatureChatStrings.text("chat.outbox.retry", locale: locale)) { onAction(.retryMediaSend) }.rfFont(.caption) }
                Button(FeatureChatStrings.text("chat.outbox.discard", locale: locale), role: .destructive) { onAction(.discardMediaSend) }.rfFont(.caption)
            } else {
                ProgressView()
                Text(FeatureChatStrings.text("chat.media.sending", locale: locale)).rfFont(.caption).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, KitMetrics.gutter).padding(.vertical, theme.gap / 2)
    }
}

/// Full-screen viewer: pinch and double-tap zoom, drag down to dismiss, close, share and save.
struct MediaViewer: View {
    let preview: MediaPreview
    let saved: Bool?
    let onAction: (ChatAction) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var settled: CGFloat = 1
    @State private var drag: CGSize = .zero
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PipelineImage(source: .file(preview.file), maxPixel: ChatMediaText.viewerPixels)
                .scaledToFit()
                .scaleEffect(scale)
                .offset(y: drag.height)
                .gesture(MagnifyGesture().onChanged { scale = max(1, min(5, settled * $0.magnification)) }.onEnded { _ in settled = scale })
                .simultaneousGesture(DragGesture().onChanged { if scale <= 1 { drag = $0.translation } }.onEnded { value in
                    if scale <= 1, value.translation.height > 120 { onAction(.closePreview) } else { withAnimation(reduceMotion ? nil : .default) { drag = .zero } }
                })
                .onTapGesture(count: 2) { withAnimation(reduceMotion ? nil : .default) { scale = scale > 1 ? 1 : 2.5; settled = scale } }
                .accessibilityLabel(Text(FeatureChatStrings.text("chat.media.photo", locale: locale)))
            VStack {
                HStack {
                    Button(FeatureChatStrings.text("chat.details.close", locale: locale)) { onAction(.closePreview) }
                    Spacer()
                    ShareLink(item: preview.file) { Label(FeatureChatStrings.text("chat.media.share", locale: locale), systemImage: "square.and.arrow.up") }
                    Button { onAction(.saveToPhotos(preview.attachmentID)) } label: { Label(FeatureChatStrings.text("chat.media.save", locale: locale), systemImage: "square.and.arrow.down") }
                }
                .labelStyle(.iconOnly).foregroundStyle(.white).padding(KitMetrics.gutter)
                Spacer()
                if let saved {
                    Text(FeatureChatStrings.text(saved ? "chat.media.saved" : "chat.media.saveFailed", locale: locale)).rfFont(.caption).foregroundStyle(.white).padding(KitMetrics.gutter)
                }
            }
        }
    }
}

/// The attachment sheet (MOB-B17 is not designed yet): the system photo picker (no library
/// permission), the system file picker and the camera (through the shared permission flow).
struct AttachSheet: View {
    let onAction: (ChatAction) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @State private var importing = false
    #if os(iOS)
    @State private var selection: [PhotosPickerItem] = []
    #endif
    var body: some View {
        RFPage { VStack(alignment: .leading, spacing: theme.gap) {
            Text(FeatureChatStrings.text("chat.attach.title", locale: locale)).rfFont(.page)
            #if os(iOS)
            PhotosPicker(selection: $selection, maxSelectionCount: 16, matching: .images, preferredItemEncoding: .current) {
                KitRow(FeatureChatStrings.text("chat.attach.photos", locale: locale), icon: "images", trailing: .none).allowsHitTesting(false)
            }
            .onChange(of: selection) { _, items in
                guard !items.isEmpty else { return }
                Task { @MainActor in
                    var picked: [PickedMedia] = []
                    for item in items { if let file = try? await item.loadTransferable(type: PickedFile.self) { picked.append(PickedMedia(url: file.url, kind: .photo, name: "")) } }
                    selection = []
                    onAction(.attachPicked(picked))
                }
            }
            KitRow(FeatureChatStrings.text("chat.attach.camera", locale: locale), action: { onAction(.cameraRequested) }, icon: "camera", trailing: .none)
            #endif
            KitRow(FeatureChatStrings.text("chat.attach.file", locale: locale), action: { importing = true }, icon: "paperclip", trailing: .none)
            Button(FeatureChatStrings.text("chat.composer.cancel", locale: locale)) { onAction(.closeAttach) }
        }.padding(theme.gap) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            onAction(.attachPicked(urls.prefix(16).compactMap(PickedFile.copy)))
        }
    }
}

/// A picked item copied at once into the app's temporary directory: picker and security-scoped
/// URLs are not durable. The chat moves it into the protected outbox and deletes this copy.
struct PickedFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.copyItem(at: received.file, to: target)
            return PickedFile(url: target)
        }
    }
    static func copy(_ url: URL) -> PickedMedia? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard (try? FileManager.default.copyItem(at: url, to: target)) != nil else { return nil }
        return PickedMedia(url: target, kind: .file, name: url.lastPathComponent)
    }
}

#if os(iOS)
/// Quick Look for a stored file, inside the app.
struct QuickLookPreview: UIViewControllerRepresentable {
    let file: URL
    func makeCoordinator() -> Source { Source(file: file) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController(); controller.dataSource = context.coordinator; return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    final class Source: NSObject, QLPreviewControllerDataSource {
        let file: URL
        init(file: URL) { self.file = file }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { file as NSURL }
    }
}

/// The system camera, shown only after the shared camera permission flow granted access.
struct CameraCapture: UIViewControllerRepresentable {
    let onAction: (ChatAction) -> Void
    func makeCoordinator() -> Delegate { Delegate(onAction: onAction) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) { picker.sourceType = .camera }
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Delegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onAction: (ChatAction) -> Void
        init(onAction: @escaping (ChatAction) -> Void) { self.onAction = onAction }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 1), (try? data.write(to: target)) != nil {
                onAction(.attachPicked([PickedMedia(url: target, kind: .photo, name: "")]))
            } else { onAction(.attachPicked([])) }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onAction(.permissionResolved(.camera, granted: false)) }
    }
}
#endif

/// Display text for media states, sizes and accessibility.
enum ChatMediaText {
    static let boxWidth: CGFloat = 240
    static let bubblePixels = 720
    static let viewerPixels = 2_560
    static func size(_ attachment: AttachmentRecord, locale: Locale) -> String? {
        attachment.size.map { $0.formatted(.byteCount(style: .file).locale(locale)) }
    }
    static func stateLine(_ attachment: AttachmentRecord, state: MediaTransferState, locale: Locale) -> String {
        switch state {
        case .idle: size(attachment, locale: locale).map { RFSentence.compose(FeatureChatStrings.text("chat.media.tapToDownload", locale: locale), [.localized($0)], locale: locale) } ?? FeatureChatStrings.text("chat.media.download", locale: locale)
        case .downloading: FeatureChatStrings.text("chat.media.downloading", locale: locale)
        case .failed: FeatureChatStrings.text("chat.media.failed", locale: locale)
        case .expired: FeatureChatStrings.text("chat.media.expired", locale: locale)
        case .removed: FeatureChatStrings.text("chat.media.removed", locale: locale)
        case .notAvailable: FeatureChatStrings.text("chat.media.notAvailable", locale: locale)
        case .blockedByPolicy: FeatureChatStrings.text("chat.media.untrusted", locale: locale)
        case .ready: FeatureChatStrings.text("chat.media.open", locale: locale)
        }
    }
    static func fileMeta(_ attachment: AttachmentRecord, state: MediaTransferState, locale: Locale) -> String {
        switch state {
        case .ready, .idle: ChatAttachmentText.meta(attachment, locale: locale)
        default: RFSentence.compose(FeatureChatStrings.text("chat.attachment.typeSize", locale: locale), [.identifier(ChatAttachmentText.typeLabel(attachment)), .localized(stateLine(attachment, state: state, locale: locale))], locale: locale)
        }
    }
    static func accessibility(_ attachment: AttachmentRecord, state: MediaTransferState, locale: Locale) -> String {
        let kind = attachment.kind == .file ? RFUntrustedText.clean(attachment.name) : FeatureChatStrings.text("chat.media.photo", locale: locale)
        return RFSentence.compose(FeatureChatStrings.text("chat.media.accessibility", locale: locale), [.localized(kind), .localized(stateLine(attachment, state: state, locale: locale))], locale: locale)
    }
    static func sendFailure(_ failure: AppFailure, locale: Locale) -> String {
        switch failure {
        case .typedRefusal("peer_upgrade_required"): FeatureChatStrings.text("chat.media.peerUpgrade", locale: locale)
        case .typedRefusal("recipient_limit"): FeatureChatStrings.text("chat.media.recipientLimit", locale: locale)
        case .typedRefusal("file_too_large"): FeatureChatStrings.text("chat.media.tooLarge", locale: locale)
        case .typedRefusal("disk_full"), .typedRefusal("quota_exceeded"): FeatureChatStrings.text("chat.media.storageFull", locale: locale)
        case .offline: FeatureChatStrings.text("chat.offline.banner", locale: locale)
        default: failure.message(locale: locale)
        }
    }
}
