// swift-tools-version:6.0
import PackageDescription

let sherpaLib = Context.packageDirectory + "/Vendor/sherpa-onnx/lib"

let package = Package(
    name: "Lasa",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CSherpaOnnx", path: "Sources/CSherpaOnnx"),
        .target(name: "LasaCore", path: "Sources/LasaCore"),
        .executableTarget(
            name: "Lasa",
            dependencies: ["CSherpaOnnx", "LasaCore"],
            path: "Sources/Lasa",
            linkerSettings: [
                .unsafeFlags([
                    "-L", sherpaLib, "-lsherpa-onnx-c-api",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", sherpaLib,
                ])
            ]
        ),
        .testTarget(name: "LasaCoreTests", dependencies: ["LasaCore"], path: "Tests/LasaCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
