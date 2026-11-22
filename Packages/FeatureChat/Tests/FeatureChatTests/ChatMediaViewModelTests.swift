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
        try await settleMedia(model, fake) { model.state.mediaDraft != nil }
        #expect(await fake.mediaSends.isEmpty)
        model.send(.draftCaptionChanged("the report"))
        model.send(.sendMediaDraft)
        try await settleMedia(model, fake) { model.state.outbox.first?.state == .queued }
        #expect(await fake.captions == ["the report"])
        #expect(!FileManager.default.fileExists(atPath: picked.path))
        let first = await fake.mediaSends
        #expect(first.count == 1); #expect(first[0].1.first?.fileName == "report.pdf")
        #expect(first[0].1.first?.file.path.hasPrefix(fake.outboxDirectory.path) == true)
        #expect(try Data(contentsOf: try #require(first[0].1.first?.file)) == Data("report body".utf8))
        #expect(model.state.offline); #expect(model.state.outbox.first?.media.count == 1)
        // The queued media send is resumed with its original key when the chat appears again.
        await fake.setMediaSendResult(.success(SendOutcome(messageID: "media-event", state: .submitted)))
        model.send(.refresh)
        try await settleMedia(model, fake) { model.state.outbox.isEmpty }
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

    @Test func shareUsesATemporaryCopyUnderTheOriginalNameAndRemovesIt() async throws {
        let stored = try tinyPNG()
        defer { try? FileManager.default.removeItem(at: stored) }
        let fake = ChatFake(history: [photoMessage("mine", own: true)])
        await fake.setStored("mine#0", stored)
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        model.send(.appeared)
        try await settleMedia(model, fake) { model.state.media["mine#0"] == .ready(stored) }
        model.send(.shareMedia("mine#0"))
        try await settleMedia(model, fake) { model.state.shareFile != nil }
        #expect(model.state.shareFile?.lastPathComponent == "p.jpg")
        #expect(await fake.shared.map(\.0) == [stored])
        model.send(.shareFinished); await model.settle()
        try await settleMedia(model, fake) { true }
        for _ in 0..<100 where await fake.shareRemovals == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(model.state.shareFile == nil); #expect(await fake.shareRemovals == 1)
        model.send(.disappeared)
    }

    @Test func forwardAsksTheHostForATargetAndResendsTextAndMedia() async throws {
        var events: [ChatEvent] = []
        var message = photoMessage("m1")
        message = MessageRecord(id: "m1", sender: "peer", kind: .text("caption"), isOwn: false, timestamp: 1, attachments: message.attachments, authorAnchor: "peer-anchor", order: MessageOrder(milliseconds: 1_000))
        let fake = ChatFake(history: [message])
        await fake.setDetails(.success(ChatDetails(muted: false)))
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { events.append($0) })
        model.send(.appeared); await model.settle()
        model.send(.forwardRequested("m1"))
        #expect(events.last == .chooseForwardTarget(messageID: "m1"))
        model.send(.forwardTo(messageID: "m1", conversation: "g", isGroup: true))
        try await settleMedia(model, fake) { events.contains(.messageSubmitted("forwarded")) }
        let forwards = await fake.forwards
        #expect(forwards.count == 1); #expect(forwards.first?.0 == "caption"); #expect(forwards.first?.1.map(\.id) == ["m1#0"]); #expect(forwards.first?.2 == "g"); #expect(forwards.first?.3 == "g")
        model.send(.disappeared)
    }

    @Test func retryingAFailedEraseForEveryoneRevokesTheMediaAgain() async throws {
        let fake = ChatFake(history: [photoMessage("mine", own: true)])
        await fake.setDeleteResult(.failure(.offline))
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        model.send(.appeared); await model.settle()
        model.send(.requestDelete("mine", .everyone)); model.send(.confirmDelete); await model.settle()
        #expect(model.state.held != nil); #expect(await fake.revokes.isEmpty)
        await fake.setDeleteResult(.success(()))
        model.send(.retrySameSend); await model.settle()
        #expect(await fake.revokes == ["mine"]); #expect(model.state.held == nil)
        model.send(.disappeared)
    }

    @Test func animatedImagesAreSentWithoutMetadataBlocks() async throws {
        let fake = ChatFake()
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        model.send(.appeared); await model.settle()
        let header: [UInt8] = Array("GIF89a".utf8) + [1, 0, 1, 0, 0x80, 0, 0] + [0, 0, 0, 255, 255, 255]
        let comment: [UInt8] = [0x21, 0xFE, 4] + Array("here".utf8) + [0]
        let frame: [UInt8] = [0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, 2, 0x4C, 0x01, 0, 0x3B]
        let picked = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(header + comment + frame).write(to: picked)
        model.send(.attachPicked([PickedMedia(url: picked, kind: .photo, name: "anim.gif")]))
        try await settleMedia(model, fake) { model.state.mediaDraft != nil }
        model.send(.sendMediaDraft)
        try await settleMedia(model, fake) { false }
        let sent = try #require(await fake.mediaSends.first?.1.first)
        #expect(sent.mime == "image/gif"); #expect(try Data(contentsOf: sent.file) == Data(header + frame))
        model.send(.disappeared)
    }

    @Test func theSendPreviewRemovesItemsAndCancelErasesTheStagedFiles() async throws {
        let fake = ChatFake()
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        model.send(.appeared); await model.settle()
        var picked: [PickedMedia] = []
        for index in 0..<3 {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data("file \(index)".utf8).write(to: url); picked.append(PickedMedia(url: url, kind: .file, name: "f\(index).txt"))
        }
        model.send(.attachPicked(picked))
        try await settleMedia(model, fake) { model.state.mediaDraft != nil }
        let staged = try #require(model.state.mediaDraft).items
        #expect(staged.map(\.fileName) == ["f0.txt", "f1.txt", "f2.txt"])
        model.send(.removeDraftItem(1))
        #expect(model.state.mediaDraft?.items.map(\.fileName) == ["f0.txt", "f2.txt"]); #expect(!FileManager.default.fileExists(atPath: staged[1].file.path))
        model.send(.cancelMediaDraft)
        #expect(model.state.mediaDraft == nil)
        #expect(staged.allSatisfy { !FileManager.default.fileExists(atPath: $0.file.path) }); #expect(await fake.mediaSends.isEmpty)
        model.send(.disappeared)
    }

    @Test func albumsHaveStableBoxesByCountAndOpenTheWholeAlbum() async throws {
        #expect(MediaAlbumGrid.layout(2).aspect == 2); #expect(MediaAlbumGrid.layout(3).cells == 3); #expect(MediaAlbumGrid.layout(16).cells == 4); #expect(MediaAlbumGrid.layout(16).aspect == 1)
        let items = (0..<6).map { AttachmentRecord(id: "al#\($0)", name: "p.jpg", mime: "image/jpeg", messageID: "al", index: $0, size: 1_000, availableUntil: 4_000_000_000) }
        let album = MessageRecord(id: "al", sender: "peer", kind: .text(""), isOwn: true, timestamp: 1, attachments: items, order: MessageOrder(milliseconds: 1_000))
        let fake = ChatFake(history: [album])
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        model.send(.appeared)
        try await settleMedia(model, fake) { model.state.media.count == 6 && !model.state.media.values.contains(.downloading) }
        #expect(model.state.media.count == 6)
        model.send(.openAlbum("al")); #expect(model.state.album == "al")
        model.send(.closeAlbum); #expect(model.state.album == nil)
        model.send(.disappeared)
    }

    @Test func theGalleryPagesTheReadModelInBoundedStepsAndHidesStrangersMedia() async throws {
        // 50,000 rows, every tenth with a photo and every fiftieth with a file.
        let rows: [MessageRecord] = (0..<50_000).map { index in
            let id = "g\(index)"
            var items: [AttachmentRecord] = []
            if index % 10 == 0 { items.append(AttachmentRecord(id: id + "#0", name: "p.jpg", mime: "image/jpeg", messageID: id, index: 0, size: 1_000, availableUntil: 4_000_000_000)) }
            if index % 50 == 0 { items.append(AttachmentRecord(id: id + "#1", name: "f.pdf", mime: "application/pdf", messageID: id, index: 1, size: 1_000, availableUntil: 4_000_000_000)) }
            return MessageRecord(id: id, sender: "peer", kind: .text("row"), isOwn: false, timestamp: 1, attachments: items, authorAnchor: "peer-anchor", order: MessageOrder(milliseconds: Int64(50_000 - index)))
        }
        let fake = ChatFake(history: rows)
        await fake.setDetails(.success(ChatDetails(muted: false)))
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        model.send(.appeared); await model.settle()
        let before = await fake.pageRequests.count
        let clock = ContinuousClock()
        let started = clock.now
        model.send(.openGallery)
        try await settleMedia(model, fake) { model.state.gallery?.loading == false }
        let first = clock.now - started
        let gallery = try #require(model.state.gallery)
        #expect(gallery.media.count == 40); #expect(gallery.files.count == 8)
        #expect(await fake.pageRequests.count - before <= ChatViewModel.galleryPagesPerStep)
        #expect(gallery.media.allSatisfy { model.state.media[$0.id] == .blockedByPolicy })
        for _ in 0..<49 {
            model.send(.galleryMore)
            try await settleMedia(model, fake) { model.state.gallery?.loading == false }
        }
        let paged = try #require(model.state.gallery)
        #expect(paged.media.count + paged.files.count == ChatViewModel.galleryCapacity); #expect(paged.detached)
        print("GALLERY_SCALE first step \(first), after 50 steps media=\(paged.media.count) files=\(paged.files.count) detached=\(paged.detached) elapsed=\(clock.now - started)")
        model.send(.closeGallery); #expect(model.state.gallery == nil)
        model.send(.disappeared)
    }

    @Test func conversationAndAccountStorageAreClearedOnlyAfterConfirmation() async throws {
        let fake = ChatFake()
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        model.send(.appeared); await model.settle()
        model.send(.detailsRequested); await model.settle()
        #expect(model.state.details?.storage == 4_096)
        model.send(.clearMediaConfirmed); await model.settle()
        #expect(await fake.purgedConversations.isEmpty)
        model.send(.clearMediaRequested); model.send(.clearMediaConfirmed); await model.settle()
        #expect(await fake.purgedConversations == ["c"]); #expect(model.state.details?.storage == 0)
        model.send(.disappeared)

        let storage = MediaStorageViewModel(repository: ChatFake(), account: "a")
        storage.send(.appeared); await storage.settle()
        #expect(storage.state.usage == MediaUsage(originals: 4_096, outbox: 10))
        storage.send(.clearConfirmed); await storage.settle(); #expect(storage.state.usage?.originals == 4_096)
        storage.send(.clearRequested); storage.send(.clearConfirmed); await storage.settle()
        #expect(storage.state.usage == MediaUsage(originals: 0, outbox: 10))
    }
}
