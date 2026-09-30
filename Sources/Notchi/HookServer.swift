import Foundation
import Darwin

/// En händelse från Claude Code (det JSON som hooken får på stdin).
struct HookEvent {
    let name: String            // hook_event_name, t.ex. "PermissionRequest"
    let sessionId: String
    let cwd: String
    let toolName: String?
    let toolInput: [String: Any]
    let message: String?        // Notification
    let notificationType: String?
    let raw: [String: Any]

    init?(json: [String: Any]) {
        guard let name = json["hook_event_name"] as? String else { return nil }
        self.name = name
        self.sessionId = json["session_id"] as? String ?? "okänd"
        self.cwd = json["cwd"] as? String ?? ""
        self.toolName = json["tool_name"] as? String
        self.toolInput = json["tool_input"] as? [String: Any] ?? [:]
        self.message = json["message"] as? String
        self.notificationType = json["notification_type"] as? String
        self.raw = json
    }

    var projectName: String { (cwd as NSString).lastPathComponent }

    /// Kort, läsbar beskrivning av vad verktyget ska göra.
    var toolSummary: String {
        switch toolName ?? "" {
        case "Bash":
            let cmd = (toolInput["command"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return cmd.count > 80 ? String(cmd.prefix(80)) + "…" : cmd
        case "Edit", "Write", "Read", "MultiEdit":
            let path = toolInput["file_path"] as? String ?? ""
            return "\(toolName!) \((path as NSString).lastPathComponent)"
        case "WebFetch":
            return "Hämta \(toolInput["url"] as? String ?? "webbsida")"
        case "WebSearch":
            return "Sök: \(toolInput["query"] as? String ?? "")"
        default:
            return toolName ?? "verktyg"
        }
    }

    /// Kommandon som alltid kräver ett klick, även om röstgodkännande är på.
    var isRisky: Bool {
        guard toolName == "Bash", let cmd = toolInput["command"] as? String else { return false }
        let pattern = #"(\brm\b|\bsudo\b|git\s+push|git\s+reset\s+--hard|curl[^|]*\|\s*(ba|z)?sh|\bmkfs\b|\bdd\b|chmod\s+-R|>\s*/dev/|\bkill(all)?\b)"#
        return cmd.range(of: pattern, options: .regularExpression) != nil
    }
}

/// Svarskanal tillbaka till en väntande hook (används bara för PermissionRequest).
final class HookReply {
    private var fd: Int32
    private let lock = NSLock()
    private var watcher: DispatchSourceRead?
    /// Anropas (på huvudtråden) om hooken försvinner innan du svarat
    var onClosed: (@MainActor () -> Void)?

    init(fd: Int32) {
        self.fd = fd
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global())
        src.setEventHandler { [weak self] in
            guard let self else { return }
            var b: UInt8 = 0
            if recv(fd, &b, 1, MSG_PEEK) <= 0 {       // 0 = andra sidan stängde
                self.watcher?.cancel()
                let cb = self.onClosed
                DispatchQueue.main.async { MainActor.assumeIsolated { cb?() } }
            }
        }
        watcher = src
        src.resume()
    }

    /// Skicka JSON-svar (eller tom rad = "inget beslut, visa vanliga dialogen i terminalen").
    func send(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        guard fd >= 0 else { return }
        watcher?.cancel(); watcher = nil
        let data = Array((line + "\n").utf8)
        _ = data.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
        close(fd)
        fd = -1
    }

    func allow() {
        send(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#)
    }
    func deny(_ message: String = "Nekat från Notchi") {
        let payload: [String: Any] = ["hookSpecificOutput": [
            "hookEventName": "PermissionRequest",
            "decision": ["behavior": "deny", "message": message]]]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        send(String(data: data, encoding: .utf8)!)
    }
    func passToTerminal() { send("") }
    deinit { watcher?.cancel(); if fd >= 0 { close(fd) } }
}

/// Lyssnar på en Unix-socket som notchi-hook skriver till.
final class HookServer {
    private let path: String
    private var listenFD: Int32 = -1
    private let queue = DispatchQueue(label: "notchi.hookserver")
    var onEvent: (@MainActor (HookEvent, HookReply?) -> Void)?

    init(path: String) { self.path = path }

    func start() {
        unlink(path)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { print("socket() misslyckades"); return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for (i, b) in bytes.prefix(buf.count - 1).enumerated() { buf[i] = b }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, size) }
        }
        guard ok == 0 else { print("bind() misslyckades: \(String(cString: strerror(errno)))"); return }
        chmod(path, 0o600)   // bara din användare får prata med appen
        listen(listenFD, 16)

        queue.async { [weak self] in self?.acceptLoop() }
    }

    private func acceptLoop() {
        while true {
            let client = accept(listenFD, nil, nil)
            if client < 0 { if errno != EINTR { usleep(100_000) }; continue }
            DispatchQueue.global().async { [weak self] in self?.handle(client) }
        }
    }

    private func handle(_ fd: Int32) {
        var buffer = [UInt8]()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
            if chunk[0..<n].contains(10) { break } // radslut = slut på meddelandet
        }
        guard let json = try? JSONSerialization.jsonObject(with: Data(buffer)) as? [String: Any],
              let event = HookEvent(json: json) else { close(fd); return }

        let reply: HookReply?
        if event.name == "PermissionRequest" {
            reply = HookReply(fd: fd)       // hooken väntar på svar
        } else {
            close(fd)
            reply = nil
        }
        let callback = onEvent
        DispatchQueue.main.async { MainActor.assumeIsolated { callback?(event, reply) } }
    }
}
