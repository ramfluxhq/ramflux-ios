// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import PackageDescription
// Extension-safe: shared by the app and the notification service extension. No UIKit.
let package = Package(name: "Push", defaultLocalization: "en", platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "Push", targets: ["Push"])],
    dependencies: [.package(name: "RamfluxCoreBridge", path: "../.."), .package(path: "../RFLocalization")], targets: [
        .target(name: "Push", dependencies: [.product(name: "RamfluxCore", package: "RamfluxCoreBridge"), "RFLocalization"],
                exclude: ["Resources/Localizable.xcstrings"], resources: [.process("Resources/CompiledLocalizations")]),
        .testTarget(name: "PushTests", dependencies: ["Push"]),
    ], swiftLanguageModes: [.v6])
