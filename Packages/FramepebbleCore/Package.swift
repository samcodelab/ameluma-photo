// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "FramepebbleCore", platforms: [.macOS(.v15), .iOS(.v18)], products: [.library(name: "FramepebbleCore", targets: ["FramepebbleCore"])], targets: [.target(name: "FramepebbleCore"), .testTarget(name: "FramepebbleCoreTests", dependencies: ["FramepebbleCore"])])
