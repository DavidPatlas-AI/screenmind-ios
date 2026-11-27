import SwiftUI
import UIKit
@main struct ScreenMindApp: App {
    @StateObject private var library = NativeLibrary()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            NativeHome().environmentObject(library)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he"))
                .tint(NativeTheme.accent)
                .preferredColorScheme(UITestLaunch.colorScheme)
                .modifier(UITestLaunch.DynamicType())
                .task { await library.start() }
                .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await library.start() } } }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
                    Task { await library.captureForegroundScreenshot() }
                }
        }
    }
}
enum NativeTheme {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.76, green: 0.72, blue: 1.0, alpha: 1) : UIColor(red: 0.318, green: 0.275, blue: 0.718, alpha: 1)
    })
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}
struct CaptureSelection: Identifiable {
    let ids: Set<String>
    let id = UUID()
}
