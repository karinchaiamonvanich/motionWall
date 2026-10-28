// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "wallpaperengine-mac",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WPEParser", targets: ["WPEParser"]),
        .library(name: "WPERenderer", targets: ["WPERenderer"]),
        .library(name: "WPELibrary", targets: ["WPELibrary"]),
        .executable(name: "wpe-inspect", targets: ["wpe-inspect"]),
        .executable(name: "wallpaper-mac", targets: ["WPEApp"]),
    ],
    targets: [
        .target(name: "WPEParser"),
        .target(name: "WPERenderer", dependencies: ["WPEParser"]),
        .target(name: "WPELibrary", dependencies: ["WPEParser"]),
        .executableTarget(
            name: "wpe-inspect",
            dependencies: ["WPEParser"]
        ),
        .executableTarget(
            name: "WPEApp",
            dependencies: ["WPEParser", "WPERenderer", "WPELibrary"]
        ),
        .testTarget(
            name: "WPEParserTests",
            dependencies: ["WPEParser"]
        ),
        .testTarget(
            name: "WPERendererTests",
            dependencies: ["WPERenderer", "WPELibrary"]
        ),
    ]
)
