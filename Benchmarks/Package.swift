// swift-tools-version: 5.9
import PackageDescription

// Pure planning tests only; the UIKit renderer experiments remain in the Xcode app.
let package = Package(
    name: "ConfettiStudyMotion",
    platforms: [.macOS(.v13), .iOS(.v16)],
    dependencies: [.package(name: "PaperConfetti", path: "..")],
    targets: [
        .target(name: "StudyMotion", dependencies: [.product(name: "PaperConfetti", package: "PaperConfetti")], path: "Motion"),
        .testTarget(name: "StudyMotionTests", dependencies: ["StudyMotion"], path: "MotionTests")
    ]
)
