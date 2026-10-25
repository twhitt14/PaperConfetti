// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PaperConfetti",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "PaperConfetti", targets: ["PaperConfetti"])],
    targets: [
        .target(name: "PaperConfetti", resources: [.copy("Resources/ThirdPartyNotices.txt")]),
        .testTarget(name: "PaperConfettiTests", dependencies: ["PaperConfetti"])
    ]
)
