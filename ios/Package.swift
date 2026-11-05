// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "FrameNovaCore", platforms: [.macOS(.v13), .iOS(.v16)], targets: [
    .target(name: "FrameNovaCore", path: "FrameNova/Core"),
    .testTarget(name: "FrameNovaCoreTests", dependencies: ["FrameNovaCore"], path: "Tests/FrameNovaCoreTests")
])
