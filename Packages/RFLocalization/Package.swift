// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import PackageDescription
let package = Package(name: "RFLocalization", platforms: [.iOS(.v18), .macOS(.v15)], products: [.library(name: "RFLocalization", targets: ["RFLocalization"])], targets: [.target(name: "RFLocalization"), .testTarget(name: "RFLocalizationTests", dependencies: ["RFLocalization"], resources: [.copy("Fixtures")])], swiftLanguageModes: [.v6])
