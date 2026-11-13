// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import PackageDescription
import Foundation

// The source package can be compiled without Rust. Applications must supply the matching
// binary artifact; tests without it link only the isolated ABI fixture target.
let artifact = ProcessInfo.processInfo.environment["RAMFLUX_CORE_XCFRAMEWORK"]
var targets: [Target] = [
    .target(name: "CRamflux", publicHeadersPath: "include"),
    .target(name: "RamfluxCore", dependencies: ["CRamflux"] + (artifact == nil ? [] : ["RamfluxSDKBinary"]),
            linkerSettings: [.linkedFramework("Security"), .linkedFramework("SystemConfiguration"),
                             .linkedFramework("CoreFoundation"), .linkedLibrary("resolv"), .linkedLibrary("z"), .linkedLibrary("iconv"), .linkedLibrary("c++")]),
]
if let artifact {
    targets.append(.binaryTarget(name: "RamfluxSDKBinary", path: artifact))
} else {
    targets.append(.target(name: "CABIFixture", path: "Tests/CABIFixture", publicHeadersPath: "include"))
    targets.append(.testTarget(name: "RamfluxCoreTests", dependencies: ["RamfluxCore", "CABIFixture"]))
}
let package = Package(name: "RamfluxCore", platforms: [.macOS(.v15), .iOS(.v18)],
                      products: [.library(name: "RamfluxCore", type: .static, targets: ["RamfluxCore"])],
                      targets: targets, swiftLanguageModes: [.v6])
