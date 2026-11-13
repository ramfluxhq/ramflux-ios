// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import PackageDescription
let package = Package(name: "FeatureOnboarding", platforms: [.iOS(.v18), .macOS(.v15)],
 products: [.library(name: "FeatureOnboarding", targets: ["FeatureOnboarding"])], dependencies: [.package(path: "../AppData"), .package(path: "../RFDesign")],
 targets: [.target(name: "FeatureOnboarding", dependencies: ["AppData", "RFDesign"]), .testTarget(name: "FeatureOnboardingTests", dependencies: ["FeatureOnboarding", "AppData"])], swiftLanguageModes: [.v6])
