// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "QingTie",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "QingTie", targets: ["QingTie"])],
  dependencies: [],
  targets: [
    .target(name: "QingTieCore"),
    .executableTarget(name: "QingTie", dependencies: ["QingTieCore"], path: "Sources/QingTieApp")
  ],
  swiftLanguageVersions: [.v5]
)
