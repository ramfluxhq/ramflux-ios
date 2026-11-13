// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import PackageDescription
import Foundation
let native: [SwiftSetting] = ProcessInfo.processInfo.environment["RAMFLUX_CORE_XCFRAMEWORK"] == nil ? [] : [.define("RF_NATIVE_SDK")]
let package = Package(name: "RFCore", platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "RFCore", targets: ["RFCore"])],
    dependencies: [.package(name: "RamfluxCoreBridge", path: "../..")], targets: [
        .target(name: "RFCore", dependencies: [.product(name: "RamfluxCore", package: "RamfluxCoreBridge")], swiftSettings: native),
        .testTarget(name: "RFCoreTests", dependencies: ["RFCore"]),
    ], swiftLanguageModes: [.v6])
