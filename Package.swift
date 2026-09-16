// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WritersGuild",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "WritersGuild", targets: ["WritersGuild"]), .library(name: "GuildCore", targets: ["GuildCore"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "GuildCore"),
        .target(name: "GuildPersistence", dependencies: ["GuildCore", "CSQLite"]),
        .target(name: "GuildAI", dependencies: ["GuildCore"]),
        .target(name: "EditorHost", dependencies: ["GuildCore"], resources: [.copy("Resources/Editor")]),
        .executableTarget(name: "WritersGuild", dependencies: ["GuildCore", "GuildPersistence", "GuildAI", "EditorHost"]),
        .testTarget(name: "GuildCoreTests", dependencies: ["GuildCore"]),
        .testTarget(name: "GuildPersistenceTests", dependencies: ["GuildPersistence", "GuildCore"]),
        .testTarget(name: "GuildAITests", dependencies: ["GuildAI", "GuildCore"]),
        .testTarget(name: "EditorHostTests", dependencies: ["EditorHost", "GuildCore"])
    ]
)
