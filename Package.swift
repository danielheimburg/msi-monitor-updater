// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MSIUpdater",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MSIUpdater", targets: ["MSIUpdater"])],
    targets: [.executableTarget(name: "MSIUpdater")]
)
