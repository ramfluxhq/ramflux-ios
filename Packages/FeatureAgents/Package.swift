// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import PackageDescription
let package = Package(name: "FeatureAgents", defaultLocalization: "en", platforms: [.iOS(.v18), .macOS(.v15)], products: [.library(name: "FeatureAgents", targets: ["FeatureAgents"])], dependencies: [.package(path: "../AppData"), .package(path: "../RFDesign")], targets: [.target(name: "FeatureAgents", dependencies: ["AppData", "RFDesign"], exclude: ["Resources/Localizable.xcstrings"], resources: [.process("Resources/CompiledLocalizations")]), .testTarget(name: "FeatureAgentsTests", dependencies: ["FeatureAgents", "AppData"])], swiftLanguageModes: [.v6])
