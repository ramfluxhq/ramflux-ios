// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import PackageDescription
let package = Package(name: "RFMedia", platforms: [.iOS(.v18), .macOS(.v15)], products: [.library(name: "RFMedia", targets: ["RFMedia"])], targets: [.target(name: "RFMedia"), .testTarget(name: "RFMediaTests", dependencies: ["RFMedia"])], swiftLanguageModes: [.v6])
