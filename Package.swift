// swift-tools-version: 6.2
import PackageDescription

let strictConcurrency: [SwiftSetting] = [
  .unsafeFlags([
    "-Xfrontend",
    "-strict-concurrency=complete",
    "-Xfrontend",
    "-warn-concurrency",
  ]),
]

let package = Package(
  name: "wuhu-workspace-engine",
  platforms: [
    .macOS(.v14),
    .iOS(.v16),
  ],
  products: [
    .library(name: "WorkspaceContracts", targets: ["WorkspaceContracts"]),
    .library(name: "WorkspaceEngine", targets: ["WorkspaceEngine"]),
    .library(name: "WorkspaceScanner", targets: ["WorkspaceScanner"]),
  ],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
    .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
  ],
  targets: [
    .target(
      name: "WorkspaceContracts",
      swiftSettings: strictConcurrency
    ),
    .target(
      name: "WorkspaceEngine",
      dependencies: [
        "WorkspaceContracts",
        .product(name: "GRDB", package: "GRDB.swift"),
      ],
      swiftSettings: strictConcurrency
    ),
    .target(
      name: "WorkspaceScanner",
      dependencies: [
        "WorkspaceContracts",
        "WorkspaceEngine",
        .product(name: "Yams", package: "Yams"),
      ],
      swiftSettings: strictConcurrency
    ),
    .testTarget(
      name: "WorkspaceEngineTests",
      dependencies: [
        "WorkspaceEngine",
        "WorkspaceContracts",
      ],
      swiftSettings: strictConcurrency
    ),
    .testTarget(
      name: "WorkspaceScannerTests",
      dependencies: [
        "WorkspaceScanner",
        "WorkspaceEngine",
        "WorkspaceContracts",
      ],
      resources: [
        .copy("Fixtures"),
      ],
      swiftSettings: strictConcurrency
    ),
  ]
)
