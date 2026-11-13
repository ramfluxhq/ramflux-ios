// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import PackageDescription
let package = Package(name: "FeatureSettings", defaultLocalization: "en", platforms: [.iOS(.v18), .macOS(.v15)], products: [.library(name: "FeatureSettings", targets: ["FeatureSettings"])], dependencies: [.package(path: "../AppData"), .package(path: "../RFDesign")], targets: [.target(name: "FeatureSettings", dependencies: ["AppData", "RFDesign"], resources: [.process("Resources")]), .testTarget(name: "FeatureSettingsTests", dependencies: ["FeatureSettings", "AppData"])], swiftLanguageModes: [.v6])
