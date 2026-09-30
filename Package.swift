// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Notchi",
    platforms: [.macOS(.v14)],
    targets: [
        // Själva appen som bor i notchen
        .executableTarget(
            name: "Notchi",
            path: "Sources/Notchi"
        ),
        // Liten CLI som Claude Code-hooks kör; skickar händelser till appen via Unix-socket
        .executableTarget(
            name: "notchi-hook",
            path: "Sources/NotchiHook"
        ),
    ]
)
