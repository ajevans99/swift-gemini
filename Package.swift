// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "swift-gemini",
  defaultLocalization: "en",
  platforms: [
    .iOS(.v17),
    .macOS(.v13),
    .tvOS(.v17),
    .watchOS(.v10),
  ],
  products: [
    .library(
      name: "SwiftGemini",
      targets: ["SwiftGemini"]
    )
  ],
  dependencies: [],
  targets: [
    .target(
      name: "SwiftGemini"
    ),
    .testTarget(
      name: "SwiftGeminiTests",
      dependencies: ["SwiftGemini"]
    ),
  ]
)
