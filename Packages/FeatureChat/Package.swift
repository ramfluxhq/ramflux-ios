// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import PackageDescription
let package = Package(name: "FeatureChat", platforms: [.iOS(.v18), .macOS(.v15)], products: [.library(name: "FeatureChat", targets: ["FeatureChat"])], dependencies: [.package(path: "../AppData"), .package(path: "../RFDesign")], targets: [.target(name: "FeatureChat", dependencies: ["AppData", "RFDesign"]), .testTarget(name: "FeatureChatTests", dependencies: ["FeatureChat", "AppData"])], swiftLanguageModes: [.v6])
