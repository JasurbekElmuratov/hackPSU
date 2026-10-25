// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SyllabusParser",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "SyllabusParser", targets: ["SyllabusParser"])],
    targets: [
        .executableTarget(name: "SyllabusParser", path: "Sources/SyllabusParser", resources: [.process("Resources")]),
        .testTarget(name: "SyllabusParserTests", dependencies: ["SyllabusParser"], path: "Tests/SyllabusParserTests")
    ]
)
