// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import PackageDescription
let package = Package(name: "FeaturePermissions", defaultLocalization: "en", platforms: [.iOS(.v18), .macOS(.v15)], products: [.library(name: "FeaturePermissions", targets: ["FeaturePermissions"])], dependencies: [.package(path: "../AppData"), .package(path: "../RFDesign")], targets: [.target(name: "FeaturePermissions", dependencies: ["AppData", "RFDesign"], exclude: ["Resources/Localizable.xcstrings"], resources: [.process("Resources/CompiledLocalizations")]), .testTarget(name: "FeaturePermissionsTests", dependencies: ["FeaturePermissions", "AppData"])], swiftLanguageModes: [.v6])
