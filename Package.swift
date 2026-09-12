// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RayNote",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "RayNote", targets: ["RayNote"])],
    targets: [
        .executableTarget(name: "RayNote"),
        .testTarget(name: "RayNoteTests", dependencies: ["RayNote"])
    ],
    swiftLanguageModes: [.v5]
)
