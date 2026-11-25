// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import PackageDescription
let package = Package(name: "FeatureDelivery", defaultLocalization: "en", platforms: [.iOS(.v18), .macOS(.v15)], products: [.library(name: "FeatureDelivery", targets: ["FeatureDelivery"])], dependencies: [.package(path: "../AppData"), .package(path: "../RFDesign"), .package(path: "../RFLocalization"), .package(path: "../Push")], targets: [.target(name: "FeatureDelivery", dependencies: ["AppData", "RFDesign", "RFLocalization", "Push"], exclude: ["Resources/Localizable.xcstrings"], resources: [.process("Resources/CompiledLocalizations")]), .testTarget(name: "FeatureDeliveryTests", dependencies: ["FeatureDelivery"])], swiftLanguageModes: [.v6])
