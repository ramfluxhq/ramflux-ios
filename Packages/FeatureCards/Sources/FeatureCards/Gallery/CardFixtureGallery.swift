// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if RAMFLUX_CARD_GALLERY
import AppData
import Foundation
import Observation
import RamfluxCore
import SwiftUI

/// The realrun card gallery: every fixture id, the five scenarios and the Run conformance control. Test builds only;
/// the Settings > About row that opens it is compiled under the same condition.
@MainActor
@Observable
public final class CardFixtureGalleryModel {
    public static let scenarioNames = ["approval", "chart", "form", "complete_form", "task"]
    public static let reportName = "card-conformance.json"

    public private(set) var rows: [CardFixtureRow] = []
    public private(set) var records: [CardConformanceRecord] = []
    public private(set) var running = false
    public private(set) var message: String?

    public let runtime = CardFixtureRuntime()
    public let drawing = CardRendererDrawing()

    public init() {}

    /// The copied fixtures, bundled into Debug builds by the app's post-build step (`card-fixtures/`).
    public var root: URL? { Bundle.main.url(forResource: "card-fixtures", withExtension: nil) }

    public func load() {
        guard let root else {
            message = "card-fixtures is not bundled in this build"
            return
        }
        do {
            rows = try CardConformance.rows(root: root)
        } catch {
            message = "fixtures unreadable: \(error)"
        }
    }

    public var passCount: Int { records.filter(\.pass).count }
    public var failCount: Int { records.count - passCount }

    /// Runs checks A-C for every row, keeps the records, prints one JSON line per record and writes the report file.
    public func runConformance() async {
        guard let root, !running else { return }
        running = true
        defer { running = false }
        let conformance = CardConformance(runtime: runtime, root: root, drawing: drawing)
        do {
            records = try await conformance.run()
            let lines = try records.map { record -> String in
                let data = try JSONEncoder.sortedCompact.encode(record.json)
                return String(decoding: data, as: UTF8.self)
            }
            for line in lines { print(line) }
            let report = FileManager.default.temporaryDirectory.appendingPathComponent(Self.reportName)
            try (lines.joined(separator: "\n") + "\n").write(to: report, atomically: true, encoding: .utf8)
            message = "\(passCount) pass, \(failCount) fail; report at \(report.path)"
        } catch {
            message = "conformance did not run: \(error)"
        }
    }
}

/// The gallery list: fixtures and scenarios, then the conformance control and its counts.
public struct CardFixtureGalleryView: View {
    @State private var model = CardFixtureGalleryModel()

    public init() {}

    public var body: some View {
        List {
            Section {
                Button("Run conformance") { Task { await model.runConformance() } }
                    .disabled(model.running || model.rows.isEmpty)
                    .accessibilityIdentifier("card-gallery-run")
                if let message = model.message {
                    Text(message).font(.footnote).accessibilityIdentifier("card-gallery-message")
                }
            }
            Section("Fixtures") {
                ForEach(model.rows, id: \.id) { row in
                    NavigationLink {
                        CardFixtureDetailView(model: model, title: row.id, fixture: row.fixture, scenario: false)
                    } label: {
                        Text(row.id).font(.system(.body, design: .monospaced))
                    }
                }
            }
            Section("Scenarios") {
                ForEach(CardFixtureGalleryModel.scenarioNames, id: \.self) { name in
                    NavigationLink {
                        CardFixtureDetailView(model: model, title: name, fixture: "\(name).json", scenario: true)
                    } label: {
                        Text(name)
                    }
                }
            }
            if !model.records.isEmpty {
                Section("Results") {
                    ForEach(Array(model.records.enumerated()), id: \.offset) { _, record in
                        Text("\(record.id) \(record.check) \(record.pass ? "PASS" : "FAIL")")
                            .font(.system(.footnote, design: .monospaced))
                    }
                }
            }
        }
        .navigationTitle("Card gallery")
        .task { model.load() }
    }
}

/// One fixture or scenario: the session stays open while the view is shown, its tree is drawn by the renderer and every
/// event goes to the standalone runtime. Leaving the view disposes the session.
struct CardFixtureDetailView: View {
    let model: CardFixtureGalleryModel
    let title: String
    let fixture: String
    let scenario: Bool
    @State private var status: String = "opening"
    @State private var session: UInt64?
    @State private var tree: CardTree?
    @State private var busy = false

    var body: some View {
        Group {
            if let tree {
                model.drawing.view(for: tree) { key, event in send(key, event, to: tree) }
            } else {
                Text(status).font(.footnote).padding()
            }
        }
        .navigationTitle(title)
        .task { await open() }
        .onDisappear { close() }
    }

    private func open() async {
        guard let root = model.root else { status = "card-fixtures is not bundled"; return }
        let base = scenario ? root.appendingPathComponent("fixtures") : root.appendingPathComponent("host-fixtures")
        guard let input = try? Data(contentsOf: base.appendingPathComponent(fixture)) else {
            status = "fixture unreadable: \(fixture)"
            return
        }
        do {
            let call = try await model.runtime.open(spec: input, locale: "en", dark: false)
            guard call.ok, let payload = call.payload, let batch = try? CardMutationBatch.decode(payload),
                  let opened = try? CardTree().applying(batch) else {
                status = "refused or not a batch (status \(call.status))"
                if call.ok { _ = await model.runtime.dispose(call.session) }
                return
            }
            if Task.isCancelled {
                _ = await model.runtime.dispose(call.session)
                return
            }
            session = call.session
            tree = opened
        } catch {
            status = "open failed: \(error)"
        }
    }

    /// One event on the held tree: `{token, event}` to the runtime, then the returned batch applies to the held tree.
    private func send(_ key: String, _ event: CardHostEvent, to held: CardTree) {
        guard !busy, let session, let token = held.token(for: key) else { return }
        busy = true
        let input: JSONValue = .object(["token": token.json, "event": event.json])
        Task {
            let reply = await model.runtime.event(session, input: input)
            busy = false
            guard reply.ok, let answer = reply.payload else { return }
            if let batchJSON = answer["batch"], let batch = try? CardMutationBatch.decode(batchJSON),
               let next = try? held.applying(batch) {
                tree = next
            }
        }
    }

    private func close() {
        guard let session else { return }
        self.session = nil
        Task { _ = await model.runtime.dispose(session) }
    }
}
#endif
