// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import PackageDescription
let package = Package(name: "RFDesign", defaultLocalization: "en", platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "RFDesign", targets: ["RFDesign"])], dependencies: [.package(path: "../RFLocalization")], targets: [
        .target(name: "RFDesign", dependencies: ["RFLocalization"], path: ".", exclude: ["Resources/Localizable.xcstrings", "Resources/KitIcons", "kit-masters.json", "Tests"], sources: ["Generated", "Sources"], resources: [.copy("Resources/Fonts"), .copy("Resources/Themes"), .process("Resources/CompiledLocalizations")]),
        .testTarget(name: "RFDesignTests", dependencies: ["RFDesign"]),
    ], swiftLanguageModes: [.v6])
