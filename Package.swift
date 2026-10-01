// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tamanotchi",
    platforms: [.macOS(.v14)],
    targets: [
        // Själva appen som bor i notchen
        .executableTarget(
            name: "Tamanotchi",
            path: "Sources/Tamanotchi"
        ),
        // Liten CLI som Claude Code-hooks kör; skickar händelser till appen via Unix-socket
        .executableTarget(
            name: "tamanotchi-hook",
            path: "Sources/TamanotchiHook"
        ),
    ]
)
