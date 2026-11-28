// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import PackageDescription
let package = Package(name: "FeatureMlsGroups", defaultLocalization: "en", platforms: [.iOS(.v18), .macOS(.v15)], products: [.library(name: "FeatureMlsGroups", targets: ["FeatureMlsGroups"])], dependencies: [.package(path: "../AppData"), .package(path: "../RFDesign"), .package(path: "../RFLocalization"), .package(path: "../FeatureChat")], targets: [.target(name: "FeatureMlsGroups", dependencies: ["AppData", "RFDesign", "RFLocalization", "FeatureChat"], exclude: ["Resources/Localizable.xcstrings"], resources: [.process("Resources/CompiledLocalizations")], swiftSettings: [.define("RAMFLUX_MLS_GALLERY", .when(configuration: .debug))]), .testTarget(name: "FeatureMlsGroupsTests", dependencies: ["FeatureMlsGroups", "AppData", "FeatureChat"], swiftSettings: [.define("RAMFLUX_MLS_GALLERY", .when(configuration: .debug))])], swiftLanguageModes: [.v6])
