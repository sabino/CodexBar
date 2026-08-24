// swift-tools-version: 5.10

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "swift-cross-ui",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .macCatalyst(.v13),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "SwiftCrossUI", targets: ["SwiftCrossUI"]),
        .library(name: "AppKitBackend", targets: ["AppKitBackend"]),
        .library(name: "GtkBackend", targets: ["GtkBackend"]),
        .library(name: "WinUIBackend", targets: ["WinUIBackend"]),
        .library(name: "Gtk", targets: ["Gtk"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            "601.0.0"..<"604.0.0"),
        .package(
            url: "https://github.com/stackotter/swift-macro-toolkit",
            .upToNextMinor(from: "0.9.0")),
        .package(
            url: "https://github.com/stackotter/swift-image-formats",
            .upToNextMinor(from: "0.5.0")),
        .package(
            url: "https://github.com/moreSwift/swift-winui",
            .upToNextMinor(from: "0.2.1")),
        .package(
            url: "https://github.com/swhitty/swift-mutex",
            .upToNextMinor(from: "0.0.6")),
        .package(
            url: "https://github.com/apple/swift-log.git",
            from: "1.6.4"),
    ],
    targets: [
        .target(
            name: "SwiftCrossUI",
            dependencies: [
                "SwiftCrossUIMacrosPlugin",
                "SwiftCrossUIMetadataSupport",
                .product(name: "ImageFormats", package: "swift-image-formats"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Mutex", package: "swift-mutex"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ],
            exclude: [
                "Builders/ViewBuilder.swift.gyb",
                "Builders/SceneBuilder.swift.gyb",
                "Builders/TableRowBuilder.swift.gyb",
                "Views/TupleView.swift.gyb",
                "Views/TupleViewChildren.swift.gyb",
                "Views/TableRowContent.swift.gyb",
                "Scenes/TupleScene.swift.gyb",
            ],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]),
        .target(name: "SwiftCrossUIMetadataSupport"),
        .macro(
            name: "SwiftCrossUIMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "MacroToolkit", package: "swift-macro-toolkit"),
            ]),
        .target(name: "AppKitBackend", dependencies: ["SwiftCrossUI"]),
        .systemLibrary(
            name: "CGtk",
            pkgConfig: "gtk4",
            providers: [
                .brew(["gtk4"]),
                .apt(["libgtk-4-dev", "clang"]),
            ]),
        .target(
            name: "Gtk",
            dependencies: ["CGtk", "GtkCHelpers"],
            exclude: ["LICENSE.md"]),
        .target(name: "GtkCHelpers", dependencies: ["CGtk"]),
        .target(
            name: "GtkBackend",
            dependencies: ["SwiftCrossUI", "Gtk", "CGtk"]),
        .target(name: "WinUIInterop"),
        .target(
            name: "WinUIBackend",
            dependencies: [
                "SwiftCrossUI",
                "WinUIInterop",
                .product(name: "WinUI", package: "swift-winui"),
                .product(name: "UWP", package: "swift-winui"),
                .product(name: "CWinRT", package: "swift-winui"),
                .product(name: "WinAppSDK", package: "swift-winui"),
                .product(name: "WindowsFoundation", package: "swift-winui"),
                .product(name: "Mutex", package: "swift-mutex"),
            ]),
    ])
