import Foundation

// On-device grouping only. A named space wins, then a keyword shared by two or more
// captures (preferring a word that also matches the chosen intent). Nothing is uploaded.
enum BrainKind: String, Equatable, Sendable {
    case root, topic, capture
}

struct BrainNode: Identifiable, Equatable, Sendable {
    var id: String
    var kind: BrainKind
    var title: String
    var subtitle: String
    var captureID: String?
    var intent: SaveIntent?
    var moment: Bool
    var count: Int
    var accessibilityText: String {
        switch kind {
        case .root: return "המוח, \(subtitle)"
        case .topic: return "נושא \(title), \(subtitle)"
        case .capture: return "\(title), \(subtitle)"
        }
    }
}

struct BrainLink: Identifiable, Equatable, Sendable {
    var id: String
    var fromID: String
    var toID: String
    var label: String
}

struct BrainGraph: Equatable, Sendable {
    static let rootID = "brain-root"
    static let openTopicID = "topic:open"
    var nodes: [String: BrainNode]
    var childIDs: [String: [String]]
    var links: [BrainLink]
    var momentIDs: [String]

    func node(_ id: String) -> BrainNode? { nodes[id] }

    func relatedTopicIDs(of topicID: String) -> [String] {
        links.compactMap { link in
            if link.fromID == topicID { return link.toID }
            if link.toID == topicID { return link.fromID }
            return nil
        }
    }
}

enum BrainText {
    static let tokenLimit = 12
    private static let stopwords: Set<String> = [
        "את", "של", "על", "עם", "זה", "לא", "יש", "מה", "אם", "או", "גם", "כל", "כי", "אך", "רק", "עוד",
        "כדי", "בין", "אל", "מן", "הוא", "היא", "הם", "הן", "אני", "אתה", "אתם", "אתן", "אנחנו",
        "לי", "לו", "לה", "להם", "לנו", "אותי", "אותו", "אותה", "היה", "היתה", "היו", "להיות",
        "בלי", "אחרי", "לפני", "תוך", "כבר", "שם", "פה", "כאן", "כך", "כזה", "איזה", "אשר", "מי",
        "כמו", "יותר", "פחות", "מאוד", "אין", "בתוך", "ואז", "אז", "כן", "זהו", "זאת", "אלה", "אלו", "אבל",
        "כללי", "the", "and", "for", "with", "from", "this", "that", "you", "are", "was", "were",
        "not", "but", "can", "your", "have", "has", "had", "its", "into", "about", "http", "https", "www", "com"
    ]

    static func tokens(title: String, text: String) -> [String] {
        let clipped = text.count > 2000 ? String(text.prefix(2000)) : text
        var seen: Set<String> = []
        var result: [String] = []
        for source in [title, clipped] {
            for raw in chunks(source) {
                let token = normalize(raw)
                guard keep(token), seen.insert(token).inserted else { continue }
                result.append(token)
                if result.count == tokenLimit { return result }
            }
        }
        return result
    }

    static func bestToken(in tokens: [String], intent: SaveIntent, documentFrequency: [String: Int], intentFrequency: [String: Int]) -> String? {
        var best: String?
        var bestScore = -1
        var bestIntent = -1
        var bestIndex = Int.max
        for (index, token) in tokens.enumerated() {
            let score = documentFrequency[token] ?? 0
            guard score >= 2 else { continue }
            let intentScore = intent == .remember ? 0 : (intentFrequency[token] ?? 0)
            let better = best == nil
                || intentScore > bestIntent
                || (intentScore == bestIntent && score > bestScore)
                || (intentScore == bestIntent && score == bestScore && index < bestIndex)
            if better {
                best = token
                bestScore = score
                bestIntent = intentScore
                bestIndex = index
            }
        }
        return best
    }

    private static func chunks(_ source: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for character in source {
            if isWord(character) {
                current.append(character)
            } else if !current.isEmpty {
                chunks.append(current)
                current = ""
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func isWord(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            CharacterSet.letters.contains(scalar) || CharacterSet.nonBaseCharacters.contains(scalar)
        }
    }

    private static func normalize(_ raw: String) -> String {
        let stripped = raw.unicodeScalars.filter { !CharacterSet.nonBaseCharacters.contains($0) }
        return String(String.UnicodeScalarView(stripped)).lowercased()
    }

    private static func keep(_ token: String) -> Bool {
        guard !stopwords.contains(token) else { return false }
        let hebrew = token.unicodeScalars.contains { $0.value >= 0x05D0 && $0.value <= 0x05EA }
        if hebrew { return token.count >= 2 }
        return token.count >= 3
    }
}

extension BrainGraph {
    static func build(from captures: [Capture], now: Date = Date(), calendar: Calendar = .current) -> BrainGraph {
        let active = captures.filter { !$0.isArchived }
        var tokensByID: [String: [String]] = [:]
        for capture in active {
            tokensByID[capture.id] = BrainText.tokens(title: capture.title, text: capture.text)
        }
        var members: [String: [Capture]] = [:]
        var titles: [String: String] = [:]
        for capture in active {
            let key = topicKey(for: capture)
            members[key, default: []].append(capture)
            if titles[key] == nil { titles[key] = topicTitle(for: key, capture: capture) }
        }

        var nodes: [String: BrainNode] = [:]
        var childIDs: [String: [String]] = [:]
        let topicKeys = members.keys.sorted { lhs, rhs in
            let leftCount = members[lhs]?.count ?? 0
            let rightCount = members[rhs]?.count ?? 0
            if leftCount != rightCount { return leftCount > rightCount }
            let leftTitle = titles[lhs] ?? lhs
            let rightTitle = titles[rhs] ?? rhs
            if leftTitle != rightTitle { return leftTitle < rightTitle }
            return lhs < rhs
        }
        for key in topicKeys {
            let captures = (members[key] ?? []).sorted(by: captureOrder(now: now, calendar: calendar))
            let topicID = topicID(for: key)
            let captureNodes = captures.map { captureNode($0, now: now, calendar: calendar) }
            for node in captureNodes { nodes[node.id] = node }
            childIDs[topicID] = captureNodes.map(\.id)
            let intent = dominantIntent(captures)
            let subtitle = [countLabel(captures.count), intent?.title].compactMap { $0 }.joined(separator: " · ")
            nodes[topicID] = BrainNode(
                id: topicID, kind: .topic, title: titles[key] ?? "נושא", subtitle: subtitle,
                captureID: nil, intent: intent, moment: false, count: captures.count
            )
        }

        let rootChildren = topicKeys.map { topicID(for: $0) }
        childIDs[rootID] = rootChildren
        nodes[rootID] = BrainNode(
            id: rootID, kind: .root, title: "המוח", subtitle: countLabel(active.count),
            captureID: nil, intent: nil, moment: false, count: active.count
        )
        let links = connect(topicKeys: topicKeys, members: members, tokensByID: tokensByID)
        let moments = active.filter { isMoment($0, now: now, calendar: calendar) }.sorted { lhs, rhs in
            let left = lhs.taskDueAt ?? .distantFuture
            let right = rhs.taskDueAt ?? .distantFuture
            if left != right { return left < right }
            return lhs.id < rhs.id
        }
        return BrainGraph(nodes: nodes, childIDs: childIDs, links: links, momentIDs: moments.map(\.id))
    }

    static func isMoment(_ capture: Capture, now: Date, calendar: Calendar) -> Bool {
        guard !capture.isArchived, capture.reviewedAt != nil, capture.hasTask, capture.taskCompletedAt == nil,
              let due = capture.taskDueAt else { return false }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return due < tomorrow
    }

    static func countLabel(_ count: Int) -> String {
        count == 1 ? "מקור אחד" : "\(count) מקורות"
    }

    private static func topicKey(for capture: Capture) -> String {
        let collection = capture.collection.trimmingCharacters(in: .whitespacesAndNewlines)
        if !collection.isEmpty && collection != "כללי" { return "space:\(collection)" }
        if let topic = capture.smartTopic { return "smart:\(topic.rawValue)" }
        return "open"
    }

    private static func topicID(for key: String) -> String {
        key == "open" ? openTopicID : "topic:\(key)"
    }

    private static func topicTitle(for key: String, capture: Capture) -> String {
        if key == "open" { return "רעיונות פתוחים" }
        if key.hasPrefix("space:") { return String(key.dropFirst("space:".count)) }
        if key.hasPrefix("smart:"), let topic = SmartTopic(rawValue: String(key.dropFirst("smart:".count))) { return topic.label }
        return capture.collection
    }

    private static func captureOrder(now: Date, calendar: Calendar) -> (Capture, Capture) -> Bool {
        { lhs, rhs in
            let leftMoment = isMoment(lhs, now: now, calendar: calendar)
            let rightMoment = isMoment(rhs, now: now, calendar: calendar)
            if leftMoment != rightMoment { return leftMoment && !rightMoment }
            if lhs.sourceDate != rhs.sourceDate { return lhs.sourceDate > rhs.sourceDate }
            return lhs.id < rhs.id
        }
    }

    private static func captureNode(_ capture: Capture, now: Date, calendar: Calendar) -> BrainNode {
        let moment = isMoment(capture, now: now, calendar: calendar)
        let title = capture.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "צילום" : capture.displayTitle
        let subtitle = moment ? "הגיע הרגע · \(capture.intent.title)" : capture.intent.title
        return BrainNode(
            id: "item:\(capture.id)", kind: .capture, title: title, subtitle: subtitle,
            captureID: capture.id, intent: capture.intent, moment: moment, count: 1
        )
    }

    private static func dominantIntent(_ captures: [Capture]) -> SaveIntent? {
        var counts: [SaveIntent: Int] = [:]
        for capture in captures { counts[capture.intent, default: 0] += 1 }
        guard let best = counts.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key.rawValue > rhs.key.rawValue
        }), best.value * 2 >= captures.count else { return nil }
        return best.key
    }

    private static func connect(topicKeys: [String], members: [String: [Capture]], tokensByID: [String: [String]]) -> [BrainLink] {
        var words: [String: [String: Int]] = [:]
        for key in topicKeys {
            var counts: [String: Int] = [:]
            for capture in members[key] ?? [] {
                for token in Set(tokensByID[capture.id] ?? []) { counts[token, default: 0] += 1 }
            }
            words[key] = counts
        }
        struct Candidate {
            var left: String
            var right: String
            var label: String
            var score: Int
        }
        var candidates: [Candidate] = []
        for index in topicKeys.indices {
            for other in topicKeys.index(after: index)..<topicKeys.endIndex {
                let leftKey = topicKeys[index]
                let rightKey = topicKeys[other]
                guard let shared = sharedWord(words[leftKey] ?? [:], words[rightKey] ?? [:]) else { continue }
                candidates.append(Candidate(left: topicID(for: leftKey), right: topicID(for: rightKey), label: shared.word, score: shared.score))
            }
        }
        candidates.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.label != rhs.label { return lhs.label < rhs.label }
            if lhs.left != rhs.left { return lhs.left < rhs.left }
            return lhs.right < rhs.right
        }
        var degree: [String: Int] = [:]
        var links: [BrainLink] = []
        for candidate in candidates {
            if degree[candidate.left, default: 0] >= 3 || degree[candidate.right, default: 0] >= 3 { continue }
            degree[candidate.left, default: 0] += 1
            degree[candidate.right, default: 0] += 1
            let fromID = min(candidate.left, candidate.right)
            let toID = max(candidate.left, candidate.right)
            links.append(BrainLink(id: "\(fromID)|\(toID)", fromID: fromID, toID: toID, label: candidate.label))
        }
        return links
    }

    private static func sharedWord(_ left: [String: Int], _ right: [String: Int]) -> (word: String, score: Int)? {
        var best: (word: String, score: Int)?
        for (word, leftCount) in left {
            let score = min(leftCount, right[word] ?? 0)
            guard score > 0 else { continue }
            if best == nil || score > best!.score || (score == best!.score && word < best!.word) {
                best = (word, score)
            }
        }
        return best
    }
}

struct BrainPoint: Equatable, Sendable {
    var x: Double
    var y: Double
}

struct BrainPlacement: Identifiable, Equatable, Sendable {
    var id: String
    var center: BrainPoint
    var width: Double
    var height: Double
    func contains(_ point: BrainPoint) -> Bool {
        abs(point.x - center.x) <= width / 2 && abs(point.y - center.y) <= height / 2
    }
}

struct BrainCaption: Equatable, Sendable {
    var text: String
    var y: Double
}

struct BrainEdge: Equatable, Sendable {
    var fromID: String
    var toID: String
    var label: String
    var semantic: Bool
}

struct BrainScene: Equatable, Sendable {
    var focusID: String
    var placements: [BrainPlacement]
    var edges: [BrainEdge]
    var captions: [BrainCaption]
    var contentWidth: Double
    var contentHeight: Double

    func hit(_ point: BrainPoint) -> String? {
        placements.reversed().first { $0.contains(point) }?.id
    }
}

enum BrainLayout {
    static let margin = 16.0
    static let gapX = 12.0
    static let gapY = 36.0
    static let nodeHeight = 74.0

    static func scene(graph: BrainGraph, focusID: String, viewportWidth: Double) -> BrainScene {
        let width = max(viewportWidth, 240)
        let focus = graph.nodes[focusID]?.kind == .topic ? focusID : BrainGraph.rootID
        let columns = width >= 700 ? 3 : 2
        let nodeWidth = (width - margin * 2 - gapX * Double(columns - 1)) / Double(columns)
        let heroWidth = min(width - margin * 2, max(nodeWidth, 220))
        var placements: [BrainPlacement] = []
        var captions: [BrainCaption] = []
        var top = margin
        placements.append(centered(id: focus, top: top, width: heroWidth, viewportWidth: width))
        top += nodeHeight + 16
        let children = graph.childIDs[focus] ?? []
        if !children.isEmpty {
            captions.append(BrainCaption(text: focus == BrainGraph.rootID ? "הנושאים" : "בתוך הנושא", y: top))
            top += 24
            placements.append(contentsOf: grid(ids: children, top: &top, columns: columns, nodeWidth: nodeWidth, viewportWidth: width))
        }
        let related = focus == BrainGraph.rootID ? [] : graph.relatedTopicIDs(of: focus).sorted {
            (graph.nodes[$0]?.title ?? $0) < (graph.nodes[$1]?.title ?? $1)
        }
        if !related.isEmpty {
            top += 8
            let labels = Array(Set(graph.links.compactMap { link -> String? in
                guard link.fromID == focus || link.toID == focus else { return nil }
                return link.label.isEmpty ? nil : link.label
            })).sorted()
            let caption = labels.isEmpty ? "מתחבר אל" : "מתחבר אל · " + labels.joined(separator: " · ")
            captions.append(BrainCaption(text: caption, y: top))
            top += 24
            placements.append(contentsOf: grid(ids: related, top: &top, columns: columns, nodeWidth: nodeWidth, viewportWidth: width))
        }
        top += margin
        let edges = edges(graph: graph, focus: focus, children: children, columns: columns)
        return BrainScene(focusID: focus, placements: placements, edges: edges, captions: captions, contentWidth: width, contentHeight: top)
    }

    private static func centered(id: String, top: Double, width: Double, viewportWidth: Double) -> BrainPlacement {
        BrainPlacement(id: id, center: BrainPoint(x: viewportWidth / 2, y: top + nodeHeight / 2), width: width, height: nodeHeight)
    }

    private static func grid(ids: [String], top: inout Double, columns: Int, nodeWidth: Double, viewportWidth: Double) -> [BrainPlacement] {
        var placed: [BrainPlacement] = []
        var index = 0
        while index < ids.count {
            let count = min(columns, ids.count - index)
            let rowWidth = Double(count) * nodeWidth + Double(max(0, count - 1)) * gapX
            let rowStart = (viewportWidth - rowWidth) / 2
            for column in 0..<count {
                let visualColumn = (count - 1) - column
                let origin = rowStart + Double(visualColumn) * (nodeWidth + gapX)
                placed.append(BrainPlacement(
                    id: ids[index + column],
                    center: BrainPoint(x: origin + nodeWidth / 2, y: top + nodeHeight / 2),
                    width: nodeWidth,
                    height: nodeHeight
                ))
            }
            top += nodeHeight + gapY
            index += count
        }
        if !placed.isEmpty { top -= gapY }
        return placed
    }

    private static func edges(graph: BrainGraph, focus: String, children: [String], columns: Int) -> [BrainEdge] {
        // Stems reach the first row only, so a topic with hundreds of captures does not draw a line through every node.
        let structural = children.prefix(columns).map {
            BrainEdge(fromID: focus, toID: $0, label: "", semantic: false)
        }
        guard focus == BrainGraph.rootID else { return structural }
        let semantic = graph.links.map {
            BrainEdge(fromID: $0.fromID, toID: $0.toID, label: $0.label, semantic: true)
        }
        return structural + semantic
    }
}
