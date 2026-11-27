// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import PackageDescription
let package = Package(name: "FeatureCards", defaultLocalization: "en", platforms: [.iOS(.v18), .macOS(.v15)], products: [.library(name: "FeatureCards", targets: ["FeatureCards"])], dependencies: [.package(path: "../AppData"), .package(path: "../RFDesign"), .package(path: "../RFLocalization"), .package(name: "RamfluxCoreBridge", path: "../..")], targets: [.target(name: "FeatureCards", dependencies: ["AppData", "RFDesign", "RFLocalization", .product(name: "RamfluxCore", package: "RamfluxCoreBridge")], exclude: ["Resources/Localizable.xcstrings"], resources: [.process("Resources/CompiledLocalizations")], swiftSettings: [.define("RAMFLUX_CARD_GALLERY", .when(configuration: .debug))]), .testTarget(name: "FeatureCardsTests", dependencies: ["FeatureCards", "AppData"])], swiftLanguageModes: [.v6])
