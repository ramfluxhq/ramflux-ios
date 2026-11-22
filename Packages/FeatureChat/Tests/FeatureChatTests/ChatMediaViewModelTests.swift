// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import AppData
@testable import FeatureChat

private func photoMessage(_ id: String, own: Bool = false, size: Int64 = 100_000, until: Int64? = 4_000_000_000, mime: String = "image/jpeg") -> MessageRecord {
    let attachment = AttachmentRecord(id: id + "#0", name: "p.jpg", mime: mime, messageID: id, index: 0, size: size, availableUntil: until)
    return MessageRecord(id: id, sender: "peer", kind: .text(""), isOwn: own, timestamp: 1, attachments: [attachment], authorAnchor: own ? nil : "peer-anchor", order: MessageOrder(milliseconds: 1_000))
}

private func tinyPNG() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let context = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
}

@Suite(.timeLimit(.minutes(1))) @MainActor struct ChatMediaViewModelTests {
    private func settleMedia(_ model: ChatViewModel, _ fake: ChatFake, until: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !until() { try await Task.sleep(for: .milliseconds(5)) }
        await model.settle()
    }

    @Test func strangersMediaWaitsForATapAndContactsMediaDownloadsByPolicy() async throws {
        let fake = ChatFake(history: [photoMessage("m1")])
        await fake.setDetails(.success(ChatDetails(muted: false)))
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", network: { .wifi }, emit: { _ in })
        model.send(.appeared)
        try await settleMedia(model, fake) { model.state.media["m1#0"] == .blockedByPolicy }
        #expect(model.state.media["m1#0"] == .blockedByPolicy); #expect(await fake.downloads.isEmpty)
        model.send(.revealMedia("m1#0")); #expect(model.state.revealed.contains("m1#0")); #expect(await fake.downloads.isEmpty)
        model.send(.mediaTapped("m1#0"))
        try await settleMedia(model, fake) { if case .ready = model.state.media["m1#0"] { true } else { false } }
        #expect(await fake.downloads == ["m1#0"])
        model.send(.disappeared)

        let contact = ChatFake(history: [photoMessage("m2")])
        let other = ChatViewModel(repository: contact, account: "a", conversation: "c", network: { .wifi }, emit: { _ in })
        other.send(.appeared)
        try await settleMedia(other, contact) { if case .ready = other.state.media["m2#0"] { true } else { false } }
        #expect(await contact.downloads == ["m2#0"])
        other.send(.disappeared)
    }

    @Test func storedOriginalsShowAtOnceAndExpiredItemsAreNeverRequested() async throws {
        let stored = FileManager.default.temporaryDirectory.appendingPathComponent("stored")
        let fake = ChatFake(history: [photoMessage("old", until: 10), photoMessage("mine", own: true)])
        await fake.setStored("mine#0", stored)
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", network: { .constrained }, emit: { _ in })
        model.send(.appeared)
        try await settleMedia(model, fake) { model.state.media["mine#0"] == .ready(stored) }
        #expect(model.state.media["old#0"] == .expired); #expect(model.state.media["mine#0"] == .ready(stored))
        model.send(.mediaTapped("old#0")); await model.settle()
        #expect(await fake.downloads.isEmpty)
        model.send(.mediaTapped("mine#0"))
        #expect(model.state.preview?.attachmentID == "mine#0"); #expect(model.state.preview?.kind == .file)
        #expect(ChatViewModel.previewKind(stored) == .file)
        model.send(.closePreview); #expect(model.state.preview == nil)
        model.send(.disappeared)
    }

    @Test func failedDownloadsRetryOnTapOnlyWhenRetryable() async throws {
        let fake = ChatFake(history: [photoMessage("m", mime: "application/pdf")])
        await fake.setDownloadResult(.notAvailable)
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", network: { .wifi }, emit: { _ in })
        model.send(.appeared)
        try await settleMedia(model, fake) { model.state.media["m#0"] == .notAvailable }
        model.send(.mediaTapped("m#0")); await model.settle()
        #expect(await fake.downloads == ["m#0"])
        model.send(.disappeared)
    }

    @Test func eraseForEveryoneRevokesTheAttachmentGrants() async {
        let fake = ChatFake(history: [photoMessage("mine", own: true)])
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        model.send(.appeared); await model.settle()
        model.send(.requestDelete("mine", .everyone)); model.send(.confirmDelete); await model.settle()
        #expect(await fake.revokes == ["mine"])
        model.send(.disappeared)
    }

    @Test func savingAPhotoGoesThroughTheSharedPermissionFlow() async throws {
        var events: [ChatEvent] = []
        let stored = try tinyPNG()
        defer { try? FileManager.default.removeItem(at: stored) }
        let fake = ChatFake(history: [photoMessage("mine", own: true)])
        await fake.setStored("mine#0", stored)
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { events.append($0) })
        model.send(.appeared)
        try await settleMedia(model, fake) { model.state.media["mine#0"] == .ready(stored) }
        #expect(ChatViewModel.previewKind(stored) == .image)
        model.send(.saveToPhotos("mine#0"))
        #expect(events.contains(.requestPermission(.photoAdd)))
        model.send(.permissionResolved(.photoAdd, granted: false))
        #expect(model.state.photoSaved == false)
        model.send(.cameraRequested); #expect(events.last == .requestPermission(.camera))
        model.send(.permissionResolved(.camera, granted: true)); #expect(model.state.cameraActive)
        model.send(.disappeared)
    }

    @Test func pickedFilesAreStagedInTheOutboxSentAndRetriedWithTheSameKey() async throws {
        let fake = ChatFake()
        await fake.setMediaSendResult(.failure(.offline))
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        model.send(.appeared); await model.settle()
        let picked = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("report body".utf8).write(to: picked)
        model.send(.attachPicked([PickedMedia(url: picked, kind: .file, name: "re\u{202E}port.pdf")]))
        try await settleMedia(model, fake) { model.state.mediaSend?.failure != nil }
        #expect(!FileManager.default.fileExists(atPath: picked.path))
        let first = await fake.mediaSends
        #expect(first.count == 1); #expect(first[0].1.first?.fileName == "report.pdf")
        #expect(first[0].1.first?.file.path.hasPrefix(fake.outboxDirectory.path) == true)
        #expect(try Data(contentsOf: try #require(first[0].1.first?.file)) == Data("report body".utf8))
        #expect(model.state.mediaSend?.failure == .offline)
        await fake.setMediaSendResult(.success(SendOutcome(messageID: "media-event", state: .submitted)))
        model.send(.retryMediaSend)
        try await settleMedia(model, fake) { model.state.mediaSend == nil }
        let sends = await fake.mediaSends
        #expect(sends.count == 2); #expect(sends[0].0 == sends[1].0)
        model.send(.disappeared)
    }

    @Test func photosAreNormalisedBeforeUpload() async throws {
        let fake = ChatFake()
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        model.send(.appeared); await model.settle()
        let notPhoto = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("text".utf8).write(to: notPhoto)
        model.send(.attachPicked([PickedMedia(url: notPhoto, kind: .photo, name: "")]))
        try await settleMedia(model, fake) { model.state.failure != nil }
        #expect(model.state.failure == .invalidInput); #expect(await fake.mediaSends.isEmpty)
        model.send(.disappeared)
    }
}
