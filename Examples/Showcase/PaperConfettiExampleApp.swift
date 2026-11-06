import SwiftUI

@main
struct PaperConfettiExampleApp: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-uikit") {
                UIKitDemo()
            } else {
                ShowcaseView().preferredColorScheme(.dark)
            }
        }
    }
}
