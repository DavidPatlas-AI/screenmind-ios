import SwiftUI

struct IdeasBrainView: View {
    @EnvironmentObject private var library: NativeLibrary
    let open: (Capture) -> Void
    var onScan: () -> Void = {}
    var onScanAll: () -> Void = {}
    @State private var focusID = BrainGraph.rootID
    @State private var spatial = false

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
                        NavigationLink {
                            MemoryEvolutionView(open: open)
                        } label: {
                            Label("מה השתנה בתיעוד?", systemImage: "clock.arrow.circlepath")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(NativeTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                        Picker("תצוגת המוח", selection: $spatial) {
                            Text("מפה").tag(false)
                            Text("מרחב תלת־ממדי").tag(true)
                        }.pickerStyle(.segmented)
                        if spatial {
                            SpatialBrainView(graph: graph, focusID: scene.focusID, activate: activate)
                                .id(scene.focusID)
                        } else {
                            canvas(graph: graph, scene: scene)
                                .id(scene.focusID)
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
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
            Text(focus?.kind == .topic ? (focus?.title ?? "המוח") : "מפת הידע").font(.title2.bold())
            Text(focus?.kind == .topic
                 ? "הקש על מקור כדי לפתוח אותו. נושא מחובר נפתח באותו מקום."
                 : "נושאים מוצעים אוטומטית. הקש על נושא כדי לגלות את המקורות שלו.")
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
                            .accessibilityLabel(Text(verbatim: "הגיע הרגע, " + (capture.taskTitle ?? capture.title)))
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
                Text("אחרי הסריקה, הצילומים מופיעים בנושאים אוטומטיים. הכול נשאר במכשיר.")
            }
            Button(action: onScanAll) {
                Label("סרוק את כל צילומי המסך", systemImage: "photo.stack")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(library.busy)
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


private struct SpatialBrainView: View {
    let graph: BrainGraph
    let focusID: String
    let activate: (BrainNode) -> Void
    @State private var yaw = 0.3
    @State private var pitch = 0.15
    @State private var zoom = 1.0
    @GestureState private var drag = CGSize.zero
    @GestureState private var pinch = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let ids = SpatialBrainLayout.visibleIDs(graph: graph, focusID: focusID)
        let points = SpatialBrainLayout.project(ids: ids, yaw: yaw + Double(drag.width)/110,
                                               pitch: pitch + Double(drag.height)/130, zoom: zoom * pinch)
        VStack(alignment: .leading, spacing: 12) {
            Text("גרור לסיבוב, צבוט לשינוי מרחק. הקש על נקודה או על מקור ברשימה.")
                .font(.caption).foregroundStyle(.secondary)
            GeometryReader { proxy in
                let size = proxy.size
                let radius = min(size.width, size.height) * 0.26
                let locations = Dictionary(uniqueKeysWithValues: points.map { p in
                    (p.id, CGPoint(x: size.width/2 + p.x*radius, y: size.height/2 + p.y*radius))
                })
                ZStack {
                    RoundedRectangle(cornerRadius: 24).fill(NativeTheme.surface)
                    Canvas { context, _ in
                        guard let center = locations[focusID] else { return }
                        for point in points where point.id != focusID {
                            guard let end = locations[point.id] else { continue }
                            var path = Path()
                            path.move(to: center); path.addLine(to: end)
                            context.stroke(path, with: .color(NativeTheme.accent.opacity(0.24)), lineWidth: 1)
                        }
                        for link in graph.links {
                            guard let a = locations[link.fromID], let b = locations[link.toID] else { continue }
                            var path = Path()
                            path.move(to: a); path.addLine(to: b)
                            context.stroke(path, with: .color(NativeTheme.accent.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        }
                    }.accessibilityHidden(true)
                    ForEach(points) { point in
                        if let node = graph.node(point.id), let position = locations[point.id] {
                            let central = node.id == focusID
                            let diameter = central ? 66.0 : max(22, min(46, 31*point.scale))
                            Button { activate(node) } label: {
                                Circle()
                                    .fill(central ? NativeTheme.accent : NativeTheme.accent.opacity(point.depth < 0 ? 0.45 : 0.85))
                                    .overlay {
                                        if central {
                                            Image(systemName: "brain.head.profile").font(.title2).foregroundStyle(.white)
                                        } else {
                                            Image(systemName: node.kind == .topic ? "folder.fill" : "doc.text")
                                                .font(.system(size: 12)).foregroundStyle(.white)
                                        }
                                    }
                                    .frame(width: diameter, height: diameter)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .position(position)
                                .accessibilityLabel(node.accessibilityText)
                        }
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 12)
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        yaw = (yaw + Double(value.translation.width)/110).truncatingRemainder(dividingBy: 2 * .pi)
                        pitch = max(-1.25, min(1.25, pitch + Double(value.translation.height)/130))
                    })
                .simultaneousGesture(MagnificationGesture()
                    .updating($pinch) { value, state, _ in state = Double(value) }
                    .onEnded { value in zoom = max(0.7, min(1.25, zoom * Double(value))) })
                .clipped()
            }.frame(height: 310)
            HStack {
                Button("סובב") { yaw = (yaw + .pi/4).truncatingRemainder(dividingBy: 2 * .pi) }
                Spacer()
                Button("אפס תצוגה") {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        yaw = 0.3; pitch = 0.15; zoom = 1
                    }
                }
            }.buttonStyle(.bordered)
            Text("המקורות והנושאים המוצגים").font(.headline)
            ForEach(ids.filter { $0 != focusID }, id: \.self) { id in
                if let node = graph.node(id) {
                    Button { activate(node) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(node.title).font(.subheadline.bold()).foregroundStyle(.primary)
                                Text(node.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.backward").font(.caption)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            }
            Text("מוצגים עד 15 פריטים סביב המוקד. כל שאר המקורות זמינים במפה הרגילה ובספרייה. קווים מקווקווים מסמנים קשר המבוסס על מילים משותפות, לא עובדה מאומתת.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
