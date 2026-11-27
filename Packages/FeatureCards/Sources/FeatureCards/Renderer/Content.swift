// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import RamfluxCore
import AppData
import RFDesign
import RFLocalization

/// An image node. The pixels come from the Image host slot of the node: the SDK resolved the card's attachment selector to
/// an object, and the host reads it through the object API (checked and decoded within the limits). Until they arrive the
/// box shows the photo icon; a slot with no object, a failed read or a refused decode shows "Image unavailable". A URL,
/// a path or a data URI in the tree is never loaded. The description is the accessible name; a tap opens the full view.
struct CardImageView: View {
    let node: CardNode
    let context: CardContext
    @Environment(\.rfTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.cardImageProvider) private var provider
    @State private var loaded: CardImageResult?
    @State private var fullScreen = false

    var body: some View {
        let variant = node.attrs["variant"]?.string ?? "mediumFeature"
        let description = RFUntrustedText(node.attrs["description"]?.string ?? "", kind: .identity).text
        let attachment = context.slot(for: node.key)?.fields["attachment"]
        let box = RoundedRectangle(cornerRadius: variant == "avatar" ? theme.radius_full : theme.radius_md)
        ZStack {
            box.fill(theme.surface)
            switch loaded {
            case .image(let image)?:
                CardPixels(image: image, fit: node.attrs["fit"]?.string ?? "fill")
            case .unavailable?:
                if variant == "icon" || variant == "avatar" {
                    Image(systemName: "photo").foregroundStyle(theme.control)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo").font(.system(size: 24)).foregroundStyle(theme.control)
                        Text(FeatureCardsStrings.text("cards.image.unavailable", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
                    }
                }
            case nil:
                Image(systemName: "photo").font(.system(size: variant == "icon" || variant == "avatar" ? 14 : 24)).foregroundStyle(theme.control)
            }
        }
        .modifier(CardImageGeometry(variant: variant))
        .clipShape(box)
        .contentShape(box)
        .onTapGesture { if case .image? = loaded { fullScreen = true } }
        .accessibilityLabel(Text(verbatim: description))
        .accessibilityAddTraits(isLoaded ? .isButton : .isImage)
        .accessibilityHint(isLoaded ? Text(FeatureCardsStrings.text("cards.image.view", locale: locale)) : Text(verbatim: ""))
        .task(id: identity(attachment)) {
            loaded = nil
            loaded = await provider.load(context.surfaceRef, attachment)
        }
        .sheet(isPresented: $fullScreen) {
            if case .image(let image)? = loaded {
                CardImageFullView(image: image, description: description, onClose: { fullScreen = false })
                    .presentationDetents([.large])
            }
        }
    }

    private var isLoaded: Bool { if case .image? = loaded { true } else { false } }

    /// The object and digest the slot names: a signed update that selects another object loads again.
    private func identity(_ attachment: JSONValue?) -> String {
        guard case .object(let selector) = CardImageSource.parse(attachment) else { return "unavailable" }
        return selector.objectID + "|" + selector.manifestDigest
    }
}

/// The decoded pixels in the node's box, placed by the `fit` attribute (object-fit: fill, contain, cover, none, scale-down).
private struct CardPixels: View {
    let image: CardImage
    let fit: String

    var body: some View {
        let picture = Image(decorative: image.cgImage, scale: 1)
        switch fit {
        case "contain": picture.resizable().scaledToFit()
        case "cover": picture.resizable().scaledToFill()
        case "none": picture
        case "scale-down": picture.resizable().scaledToFit().frame(maxWidth: CGFloat(image.cgImage.width), maxHeight: CGFloat(image.cgImage.height))
        default: picture.resizable()
        }
    }
}

/// The full-screen view of a card image (spec 4.15): on the page background, image fitted with contain, the description
/// below in the secondary colour, closed by the button or a swipe down.
private struct CardImageFullView: View {
    let image: CardImage
    let description: String
    let onClose: () -> Void
    @Environment(\.rfTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: theme.gap) {
            HStack {
                Spacer(minLength: 0)
                Button(action: onClose) { Image(systemName: "xmark").padding(theme.gap) }
                    .accessibilityLabel(Text(FeatureCardsStrings.text("cards.modal.close", locale: locale)))
                    .accessibilityIdentifier("card-image-close")
            }
            Image(decorative: image.cgImage, scale: 1).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            if !description.isEmpty { Text(verbatim: description).rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary).multilineTextAlignment(.center) }
        }
        .padding(theme.gap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
        .gesture(DragGesture(minimumDistance: 24).onEnded { if $0.translation.height > 80 { onClose() } })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card-image-full")
    }
}

private struct CardImageGeometry: ViewModifier {
    let variant: String
    func body(content: Content) -> some View {
        switch variant {
        case "icon": content.frame(width: 24, height: 24)
        case "avatar": content.frame(width: 40, height: 40)
        case "smallFeature": content.frame(width: 96, height: 96)
        case "header": content.frame(maxWidth: .infinity).aspectRatio(2, contentMode: .fit).frame(maxHeight: 240)
        case "largeFeature": content.frame(maxWidth: .infinity).aspectRatio(4.0 / 3.0, contentMode: .fit).frame(maxHeight: 420)
        default: content.frame(maxWidth: .infinity).aspectRatio(16.0 / 9.0, contentMode: .fit).frame(maxHeight: 280)
        }
    }
}

/// The task status as the runtime reports it. The status is untrusted and only shapes the chip, the glyphs and the progress.
struct CardTaskView: View {
    let node: CardNode
    @Environment(\.rfTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        let status = node.attrs["status"]?.string ?? "pending"
        let steps = (node.attrs["steps"]?.array ?? []).map { (status: $0["status"]?.string ?? "pending", text: $0["text"]?.string ?? "") }
        let completed = steps.filter { $0.status == "completed" }.count
        let progress = node.attrs["progress"]?.cardInt
        let owner = RFUntrustedText(node.attrs["owner"]?.string ?? "", kind: .identity).text
        let title = RFUntrustedText(node.attrs["title"]?.string ?? "", kind: .identity).text
        VStack(alignment: .leading, spacing: 8) {
            CardChip(text: FeatureCardsStrings.text("cards.task.status.\(status)", locale: locale), tone: taskTone(status))
            Text(owner.isEmpty ? title : "\(owner) · \(title)").rfFont(.size(theme.size_subheading), weight: .semibold).foregroundStyle(theme.text)
            if let requester = node.attrs["requester"]?.string, !requester.isEmpty {
                Text(RFUntrustedText(requester, kind: .messageBody).text).rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary)
            }
            if let progress {
                HStack(spacing: 8) {
                    ProgressView(value: Double(min(max(progress, 0), 100)), total: 100).tint(theme.primary)
                    Text("\(progress) %").rfFont(.caption).foregroundStyle(theme.secondary)
                }
            } else if status == "running" {
                ProgressView().progressViewStyle(.linear).tint(theme.primary)
            }
            if steps.count <= 3 {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in CardStepRow(status: step.status, text: step.text) }
            } else {
                DisclosureGroup(FeatureCardsStrings.format("cards.task.steps", completed, steps.count, locale: locale)) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in CardStepRow(status: step.status, text: step.text) }
                }
                .rfFont(.size(theme.size_secondary))
            }
            if status == "refused" {
                Text(FeatureCardsStrings.text("cards.task.refusedNote", locale: locale)).rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func taskTone(_ status: String) -> CardChipTone {
        switch status {
        case "completed": .success
        case "refused": .danger
        default: .neutral
        }
    }
}

private struct CardStepRow: View {
    let status: String
    let text: String
    @Environment(\.rfTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            glyph.frame(width: 14, height: 14)
            Text(RFUntrustedText(text, kind: .identity).text)
                .rfFont(.size(theme.size_secondary), weight: status == "running" ? .semibold : .regular)
                .foregroundStyle(status == "running" ? theme.text : theme.secondary)
        }
        .frame(minHeight: 28, alignment: .leading)
    }

    @ViewBuilder private var glyph: some View {
        switch status {
        case "running": ProgressView().controlSize(.small)
        case "completed": Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.success)
        case "refused": Image(systemName: "xmark.circle.fill").foregroundStyle(theme.danger)
        case "delivered": Image(systemName: "circle.fill").foregroundStyle(theme.secondary).scaleEffect(0.5)
        case "cancelled": Image(systemName: "slash.circle").foregroundStyle(theme.control)
        default: Image(systemName: "circle").foregroundStyle(theme.control)
        }
    }
}

/// A line or bar chart with its legend, x labels (at most four) and a complete table alternative.
struct CardChartView: View {
    let node: CardNode
    let context: CardContext
    @Environment(\.rfTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        let series = (node.attrs["series"]?.array ?? []).map { row in
            CardSeries(label: row["label"]?.string ?? "",
                       points: (row["points"]?.array ?? []).map { (label: $0["label"]?.string ?? "", value: $0["value"]?.cardDouble ?? 0) })
        }
        let scale = max(node.attrs["scale"]?.cardDouble ?? 1, 1)
        let unit = node.attrs["unit"]?.string ?? ""
        let bars = node.attrs["kind"]?.string == "bar"
        let count = series.map { $0.points.count }.max() ?? 0
        let table = context.local.tableMode.contains(node.key)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(RFUntrustedText(unit, kind: .identity).text).rfFont(.caption).foregroundStyle(theme.secondary)
                Spacer(minLength: 0)
                Button {
                    if table { context.local.tableMode.remove(node.key) } else { context.local.tableMode.insert(node.key) }
                } label: {
                    Image(systemName: table ? "chart.xyaxis.line" : "tablecells").foregroundStyle(theme.secondary).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(FeatureCardsStrings.text(table ? "cards.chart.chart" : "cards.chart.table", locale: locale)))
            }
            if count == 0 {
                Text(FeatureCardsStrings.text("cards.chart.empty", locale: locale)).rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 96)
            } else if table {
                CardChartTable(series: series, scale: scale)
            } else {
                HStack(spacing: 16) {
                    ForEach(Array(series.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 7) {
                            Circle().fill(index == 0 ? theme.chart_1 : theme.chart_2).frame(width: 8, height: 8)
                            Text(RFUntrustedText(item.label, kind: .identity).text).rfFont(.caption).foregroundStyle(theme.secondary)
                            if let last = item.points.last {
                                Text(last.value / scale, format: .number.locale(context.formatLocale)).rfFont(.caption).foregroundStyle(theme.text)
                            }
                        }
                    }
                }
                Canvas { gc, size in
                    let values = series.flatMap { $0.points.map { $0.value / scale } }
                    let high = max(values.max() ?? 1, 0), low = min(values.min() ?? 0, 0)
                    let span = high - low > 0 ? high - low : 1
                    for line in 0...3 {
                        let y = size.height * CGFloat(line) / 3
                        var grid = Path(); grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                        gc.stroke(grid, with: .color(theme.line), lineWidth: 1)
                    }
                    let pitch = count > 0 ? size.width / CGFloat(count) : size.width
                    for (index, item) in series.enumerated() {
                        let color = index == 0 ? theme.chart_1 : theme.chart_2
                        let points = item.points.enumerated().map { position, point in
                            CGPoint(x: (CGFloat(position) + 0.5) * pitch, y: size.height * CGFloat(1 - (point.value / scale - low) / span))
                        }
                        if bars {
                            let width: CGFloat = 11
                            for (position, point) in points.enumerated() {
                                let x = (CGFloat(position) + 0.5) * pitch - width / 2 + CGFloat(index) * (width + 2) - (CGFloat(series.count) - 1) * (width + 2) / 2
                                let base = size.height * CGFloat(1 - (0 - low) / span)
                                gc.fill(Path(CGRect(x: x, y: min(point.y, base), width: width, height: abs(base - point.y))), with: .color(color))
                            }
                        } else if let first = points.first {
                            var path = Path(); path.move(to: first)
                            for point in points.dropFirst() { path.addLine(to: point) }
                            let dash: [CGFloat] = index == 0 ? [] : [4, 3]
                            gc.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: dash))
                            if let last = points.last {
                                let dot = index == 0 ? Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6))
                                    : Path(CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6))
                                gc.fill(dot, with: .color(color))
                            }
                        }
                    }
                }
                .frame(height: 140)
                let labels = series.first?.points.map(\.label) ?? []
                HStack {
                    ForEach(Array(xLabels(labels).enumerated()), id: \.offset) { _, label in
                        Text(RFUntrustedText(label, kind: .identity).text).rfFont(.caption).foregroundStyle(theme.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// First, last and evenly spaced labels, at most four.
    private func xLabels(_ labels: [String]) -> [String] {
        guard labels.count > 4 else { return labels }
        return [0, labels.count / 3, 2 * labels.count / 3, labels.count - 1].map { labels[$0] }
    }
}

private struct CardSeries {
    let label: String
    let points: [(label: String, value: Double)]
}

/// The chart's table alternative: one row per point, one column per series, numbers end-aligned.
private struct CardChartTable: View {
    let series: [CardSeries]
    let scale: Double
    @Environment(\.rfTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        let rows = series.map { $0.points.count }.max() ?? 0
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(series.enumerated()), id: \.offset) { _, item in
                    Text(RFUntrustedText(item.label, kind: .identity).text).rfFont(.size(theme.size_meta), weight: .semibold)
                        .foregroundStyle(theme.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(minHeight: 28)
            Rectangle().fill(theme.line).frame(height: 1)
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 8) {
                    Text(RFUntrustedText(series.first?.points[safe: row]?.label ?? "", kind: .identity).text).rfFont(.size(theme.size_meta))
                        .foregroundStyle(theme.text).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(series.enumerated()), id: \.offset) { _, item in
                        Text((item.points[safe: row]?.value ?? 0) / scale, format: .number.locale(locale))
                            .rfFont(.size(theme.size_meta)).foregroundStyle(theme.text).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(minHeight: 28)
                Rectangle().fill(theme.line_soft).frame(height: 1)
            }
        }
    }
}

/// A table of up to four columns and up to 16 rows. More than eight rows show eight and a count.
struct CardTableView: View {
    let node: CardNode
    @Environment(\.rfTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        let columns = (node.attrs["columns"]?.array ?? []).map { $0["label"]?.string ?? "" }
        let rows = (node.attrs["rows"]?.array ?? []).map { ($0["cells"]?.array ?? []) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, label in
                    Text(RFUntrustedText(label, kind: .identity).text).rfFont(.size(theme.size_meta), weight: .semibold)
                        .foregroundStyle(theme.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minHeight: 28)
            Rectangle().fill(theme.line).frame(height: 1)
            if rows.isEmpty {
                Text(FeatureCardsStrings.text("cards.table.empty", locale: locale)).rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            ForEach(Array(rows.prefix(8).enumerated()), id: \.offset) { _, cells in
                HStack(spacing: 8) {
                    ForEach(Array(columns.indices), id: \.self) { column in
                        cell(cells[safe: column] ?? .null)
                    }
                }
                .frame(minHeight: 28)
                Rectangle().fill(theme.line_soft).frame(height: 1)
            }
            if rows.count > 8 {
                Text(FeatureCardsStrings.format("cards.table.showing", 8, rows.count, locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder private func cell(_ value: JSONValue) -> some View {
        switch value {
        case .bool(let flag):
            Text(FeatureCardsStrings.text(flag ? "cards.table.yes" : "cards.table.no", locale: locale)).rfFont(.size(theme.size_meta))
                .foregroundStyle(flag ? theme.text : theme.control).frame(maxWidth: .infinity, alignment: .trailing)
        case .unsigned, .number:
            Text(value.cardDouble ?? 0, format: .number.locale(locale)).rfFont(.size(theme.size_meta)).foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .string(let text):
            Text(RFUntrustedText(text, kind: .messageBody).text).rfFont(.size(theme.size_meta)).foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Text("").frame(maxWidth: .infinity)
        }
    }
}

extension Array {
    /// The element at an index, or nil when out of range.
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
