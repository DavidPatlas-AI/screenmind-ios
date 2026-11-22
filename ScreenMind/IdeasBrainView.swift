import SwiftUI

struct IdeasBrainView: View {
    @EnvironmentObject private var library: NativeLibrary
    let open: (Capture) -> Void
    var onScan: () -> Void = {}
    @State private var focusID = BrainGraph.rootID

    var body: some View {
        GeometryReader { proxy in
            let graph = BrainGraph.build(from: library.captures)
            let width = max(proxy.size.width - 36, 240)
            let scene = BrainLayout.scene(graph: graph, focusID: focusID, viewportWidth: width)
            let focus = graph.node(scene.focusID)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(focus)
                    if !graph.momentIDs.isEmpty { moments(graph) }
                    if library.active.isEmpty {
                        empty
                    } else {
                        canvas(graph: graph, scene: scene)
                            .id(scene.focusID)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: library.captures) { _, captures in
                if BrainGraph.build(from: captures).nodes[focusID] == nil { focusID = BrainGraph.rootID }
            }
        }
        .background(NativeTheme.canvas)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: focusID)
        .sensoryFeedback(.selection, trigger: focusID)
    }

    private func header(_ focus: BrainNode?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(focus?.kind == .topic ? (focus?.title ?? "המוח") : "למה זה נשמר").font(.title2.bold())
            Text(focus?.kind == .topic
                 ? "הקש על מקור כדי לפתוח אותו. נושא מחובר נפתח באותו מקום."
                 : "נושאים לפי המרחב שבחרת, הכוונה, ומילים שחזרו בטקסט. הכול במכשיר.")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if focusID != BrainGraph.rootID {
                Button { self.focus(BrainGraph.rootID) } label: { Label("כל המוח", systemImage: "brain.head.profile") }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func moments(_ graph: BrainGraph) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("הגיע הרגע").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(graph.momentIDs.prefix(12)), id: \.self) { captureID in
                        if let capture = library.capture(captureID) {
                            Button { open(capture) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(capture.taskTitle ?? capture.title).lineLimit(1).font(.subheadline.weight(.medium))
                                    Text(capture.title).lineLimit(1).font(.caption).foregroundStyle(.secondary)
                                }.padding(.horizontal, 12).padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                            .accessibilityLabel("הגיע הרגע, \(capture.taskTitle ?? capture.title)")
                        }
                    }
                }.padding(.vertical, 2)
            }
            if graph.momentIDs.count > 12 {
                Text("ועוד \(graph.momentIDs.count - 12) בלשונית הצעד הבא").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("המוח מתמלא מצילומים.", systemImage: "brain.head.profile")
            } description: {
                Text("אחרי סריקה או שמירה, צילומים מתקבצים לנושאים לפי המרחב, הכוונה ומילות המפתח. הכול נשאר במכשיר.")
            }
            Button(action: onScan) {
                Label("סרוק צילומי מסך", systemImage: "photo.badge.magnifyingglass")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .disabled(library.busy)
        }
    }

    private func canvas(graph: BrainGraph, scene: BrainScene) -> some View {
        BrainCanvas(graph: graph, scene: scene)
            .frame(width: scene.contentWidth, height: max(scene.contentHeight, 280))
            .overlay {
                ZStack {
                    ForEach(scene.placements) { placement in
                        if let node = graph.node(placement.id) {
                            Button { activate(node) } label: { Color.white.opacity(0.001) }
                                .frame(width: placement.width, height: placement.height)
                                .position(x: placement.center.x, y: placement.center.y)
                                .accessibilityLabel(node.accessibilityText)
                        }
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .environment(\.layoutDirection, .leftToRight)
    }

    private func activate(_ node: BrainNode) {
        switch node.kind {
        case .root:
            focus(BrainGraph.rootID)
        case .topic:
            focus(node.id)
        case .capture:
            if let id = node.captureID, let capture = library.capture(id) { open(capture) }
        }
    }

    private func focus(_ id: String) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { focusID = id }
    }

}

private struct BrainCanvas: View {
    let graph: BrainGraph
    let scene: BrainScene

    var body: some View {
        Canvas { context, _ in
            for edge in scene.edges {
                guard let start = placement(edge.fromID), let end = placement(edge.toID) else { continue }
                let upper = start.center.y <= end.center.y ? start : end
                let lower = start.center.y <= end.center.y ? end : start
                var path = Path()
                let from = CGPoint(x: upper.center.x, y: upper.center.y + upper.height / 2)
                let to = CGPoint(x: lower.center.x, y: lower.center.y - lower.height / 2)
                let midY = (from.y + to.y) / 2
                path.move(to: from)
                path.addCurve(to: to, control1: CGPoint(x: from.x, y: midY), control2: CGPoint(x: to.x, y: midY))
                let color = edge.semantic ? NativeTheme.accent.opacity(0.7) : Color.secondary.opacity(0.35)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: edge.semantic ? 2 : 1.25, lineCap: .round))
            }
            for caption in scene.captions {
                let rect = CGRect(x: 0, y: caption.y, width: scene.contentWidth, height: 20)
                context.draw(Text(caption.text).font(.caption.weight(.semibold)).foregroundStyle(.secondary), in: rect)
            }
            for item in scene.placements {
                guard let node = graph.node(item.id) else { continue }
                let rect = CGRect(x: item.center.x - item.width / 2, y: item.center.y - item.height / 2, width: item.width, height: item.height)
                let path = Path(roundedRect: rect, cornerRadius: 18)
                context.fill(path, with: .color(fill(for: node)))
                let highlighted = node.id == scene.focusID || node.kind == .root
                context.stroke(path, with: .color(highlighted ? NativeTheme.accent : Color.primary.opacity(0.08)), lineWidth: highlighted ? 2 : 1)
                let titleRect = rect.insetBy(dx: 12, dy: 12).divided(atDistance: 24, from: .minYEdge).slice
                let subtitleRect = CGRect(x: rect.minX + 12, y: rect.minY + 38, width: rect.width - 24, height: 22)
                context.draw(Text(node.title).font(.subheadline.bold()).foregroundStyle(.primary), in: titleRect)
                context.draw(Text(node.subtitle).font(.caption).foregroundStyle(.secondary), in: subtitleRect)
            }
            let semantic = scene.edges.filter { $0.semantic && !$0.label.isEmpty }
            if semantic.count <= 8 {
                for edge in semantic {
                    guard let start = placement(edge.fromID), let end = placement(edge.toID) else { continue }
                    let upper = start.center.y <= end.center.y ? start : end
                    let lower = start.center.y <= end.center.y ? end : start
                    let midY = (upper.center.y + upper.height / 2 + lower.center.y - lower.height / 2) / 2
                    context.draw(
                        Text(edge.label).font(.caption2).foregroundStyle(.secondary),
                        at: CGPoint(x: (upper.center.x + lower.center.x) / 2, y: midY)
                    )
                }
            }
        }
    }

    private func placement(_ id: String) -> BrainPlacement? { scene.placements.first { $0.id == id } }

    private func fill(for node: BrainNode) -> Color {
        if node.moment { return Color.orange.opacity(0.18) }
        if node.id == scene.focusID || node.kind == .root { return NativeTheme.accent.opacity(0.16) }
        if node.kind == .topic { return NativeTheme.surface }
        switch node.intent {
        case .act: return Color.orange.opacity(0.12)
        case .inspiration: return Color.purple.opacity(0.12)
        case .evidence: return Color.teal.opacity(0.12)
        default: return NativeTheme.surface
        }
    }
}
