// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import PackageDescription
import Foundation
let native: [SwiftSetting] = ProcessInfo.processInfo.environment["RAMFLUX_CORE_XCFRAMEWORK"] == nil ? [] : [.define("RF_NATIVE_SDK")]
// The MLS gallery fixtures (Gallery/) are compiled only in Debug, like the card gallery.
let mlsGallery: [SwiftSetting] = [.define("RAMFLUX_MLS_GALLERY", .when(configuration: .debug))]
let package = Package(name: "AppData", defaultLocalization: "en", platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "AppData", targets: ["AppData"])],
    dependencies: [.package(name: "RamfluxCoreBridge", path: "../.."), .package(path: "../RFLocalization"), .package(path: "../Push")], targets: [
        .target(name: "AppData", dependencies: [.product(name: "RamfluxCore", package: "RamfluxCoreBridge"), "RFLocalization", "Push"], exclude: ["Resources/Localizable.xcstrings"], resources: [.process("Resources/CompiledLocalizations")], swiftSettings: native + mlsGallery),
        .testTarget(name: "AppDataTests", dependencies: ["AppData"], swiftSettings: native + mlsGallery),
    ], swiftLanguageModes: [.v6])
