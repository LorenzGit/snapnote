// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SnapNote",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SnapNote", targets: ["SnapNote"])],
    targets: [
        .executableTarget(name: "SnapNote"),
        .testTarget(name: "SnapNoteTests", dependencies: ["SnapNote"])
    ]
)
