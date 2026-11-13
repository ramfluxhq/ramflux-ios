// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import PackageDescription
let package = Package(name: "FeatureContacts", defaultLocalization: "en", platforms: [.iOS(.v18), .macOS(.v15)], products: [.library(name: "FeatureContacts", targets: ["FeatureContacts"])], dependencies: [.package(path: "../AppData"), .package(path: "../RFDesign")], targets: [.target(name: "FeatureContacts", dependencies: ["AppData", "RFDesign"], resources: [.process("Resources")]), .testTarget(name: "FeatureContactsTests", dependencies: ["FeatureContacts", "AppData"])], swiftLanguageModes: [.v6])
