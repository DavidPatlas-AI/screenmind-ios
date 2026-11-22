import SwiftUI
import UIKit

// Launch arguments used only by ScreenMindUITests. A normal launch ignores them.
enum UITestLaunch {
    static var colorScheme: ColorScheme? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestDark") { return .dark }
        #endif
        return nil
    }

    static func prepare(_ vault: Vault) throws {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let seed = arguments.contains("-UITestSeed")
        guard seed || arguments.contains("-UITestReset") else { return }
        wipe(vault)
        if seed { try seedLibrary(vault) }
        #endif
    }

    struct DynamicType: ViewModifier {
        func body(content: Content) -> some View {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-UITestLargeText") {
                content.dynamicTypeSize(.accessibility2)
            } else {
                content
            }
            #else
            content
            #endif
        }
    }

    #if DEBUG
    private static func wipe(_ vault: Vault) {
        let manager = FileManager.default
        for name in ["Records", "Originals"] {
            let directory = vault.root.appendingPathComponent(name, isDirectory: true)
            guard let urls = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            for url in urls { try? manager.removeItem(at: url) }
        }
    }

    private struct Sample {
        var title: String
        var text: String
        var collection = "כללי"
        var intent: SaveIntent = .remember
        var task: String?
        var due: Date?
        var reviewed = true
    }

    private static func seedLibrary(_ vault: Vault) throws {
        let yesterday = Date().addingTimeInterval(-86_400)
        let later = Date().addingTimeInterval(86_400 * 5)
        var samples = [
            Sample(title: "שולחן אלון", text: "מידות של הרהיט", collection: "הבית"),
            Sample(title: "פסטה סדנה", text: "מתכון פסטה", intent: .act, task: "להתקשר", due: yesterday),
            Sample(title: "ספק פסטה", text: "מחיר פסטה", intent: .act, task: "להשוות", due: later),
            Sample(title: "ספק אחר", text: "טלפון של הספק"),
            Sample(title: "ספק נוסף", text: "כתובת של הספק"),
            Sample(title: "ממתין לסקירה", text: "טיוטה יחידה", reviewed: false)
        ]
        for name in ["מנורה", "כורסה", "שטיח", "וילון", "מדף", "כרית", "שידה"] {
            samples.append(Sample(title: name, text: "פריט \(name)", collection: "הבית"))
        }
        for name in ["רוטב", "ניוקי", "לזניה", "רביולי"] {
            samples.append(Sample(title: "פסטה \(name)", text: "מתכון \(name) ופסטה"))
        }
        for name in ["חשבונית", "דרכון", "מצפן", "מזוודה", "פתק"] {
            samples.append(Sample(title: name, text: name))
        }
        for (index, sample) in samples.enumerated() {
            let saved = try vault.save(data: png(index: index), name: "seed-\(index).png", photoIdentifier: nil, source: "uitest")
            try vault.update(saved.id) { capture in
                capture.title = sample.title
                capture.text = sample.text
                capture.collection = sample.collection
                capture.intent = sample.intent
                capture.taskTitle = sample.task
                capture.taskDueAt = sample.due
                capture.reviewedAt = sample.reviewed ? Date(timeIntervalSince1970: 1_700_000_000) : nil
                capture.textStatus = "complete"
                capture.createdAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
            }
        }
    }

    private static func png(index: Int) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        return renderer.pngData { context in
            let tone = CGFloat(index % 12) / 12
            UIColor(red: 0.2 + tone * 0.5, green: 0.34, blue: 0.28, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: CGFloat(index + 1)))
        }
    }
    #endif
}
