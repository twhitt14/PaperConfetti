import SwiftUI

@main
struct BenchmarkApp: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                // Existing gesture tests use a deliberately extended flight, never for timing.
                ShowcaseView().preferredColorScheme(.dark)
            } else if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--study=") })
                        || ProcessInfo.processInfo.arguments.contains("--visual-review")
                        || !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--run-id=") || $0 == "--smoke" || $0 == "--runner-hold" }) {
                StudyView().preferredColorScheme(.dark)
            } else {
                BenchmarkView().preferredColorScheme(.dark)
            }
        }
    }
}
