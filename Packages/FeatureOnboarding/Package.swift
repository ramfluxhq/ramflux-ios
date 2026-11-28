// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import PackageDescription
let package = Package(name: "FeatureOnboarding", defaultLocalization: "en", platforms: [.iOS(.v18), .macOS(.v15)],
 products: [.library(name: "FeatureOnboarding", targets: ["FeatureOnboarding"])], dependencies: [.package(path: "../AppData"), .package(path: "../RFDesign"), .package(path: "../RFLocalization"), .package(name: "RamfluxCoreBridge", path: "../..")],
 targets: [.target(name: "FeatureOnboarding", dependencies: ["AppData", "RFDesign", "RFLocalization"], exclude: ["Resources/Localizable.xcstrings"], resources: [.process("Resources/CompiledLocalizations")]), .testTarget(name: "FeatureOnboardingTests", dependencies: ["FeatureOnboarding", "AppData", .product(name: "RamfluxCore", package: "RamfluxCoreBridge")])], swiftLanguageModes: [.v6])
