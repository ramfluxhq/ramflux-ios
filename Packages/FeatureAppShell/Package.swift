// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import PackageDescription
let package = Package(name: "FeatureAppShell", defaultLocalization: "en", platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "FeatureAppShell", targets: ["FeatureAppShell"])],
    dependencies: [.package(path: "../AppData"), .package(path: "../RFDesign")], targets: [
        .target(name: "FeatureAppShell", dependencies: ["AppData", "RFDesign"], resources: [.process("Resources")]),
        .testTarget(name: "FeatureAppShellTests", dependencies: ["FeatureAppShell", "AppData"]),
    ], swiftLanguageModes: [.v6])
