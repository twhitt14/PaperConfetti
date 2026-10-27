import SwiftUI

@main
struct BenchmarkApp: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                // Existing gesture tests use a deliberately extended flight, never for timing.
                ShowcaseView().preferredColorScheme(.dark)
            } else {
                BenchmarkView().preferredColorScheme(.dark)
            }
        }
    }
}
