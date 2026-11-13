// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import PackageDescription
let package = Package(name: "RFDesign", defaultLocalization: "en", platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "RFDesign", targets: ["RFDesign"])], targets: [
        .target(name: "RFDesign", path: ".", exclude: ["Generated/.ramflux-design-manifest.json", "Resources/Localizable.xcstrings"], sources: ["Generated", "Sources"], resources: [.copy("Resources/Fonts"), .copy("Resources/Themes"), .process("Resources/CompiledLocalizations")]),
        .testTarget(name: "RFDesignTests", dependencies: ["RFDesign"]),
    ], swiftLanguageModes: [.v6])
