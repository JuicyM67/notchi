import Foundation
import Darwin

// notchi-hook: körs av Claude Code vid varje hook-händelse.
// Läser händelsen (JSON) från stdin och skickar den till Notchi-appen via en Unix-socket.
// För PermissionRequest väntar den på svar (Tillåt/Neka) och skriver det till stdout.
// Om appen inte är igång avslutar den tyst, så att Claude Code fungerar precis som vanligt.

// Läge 2: --statusline. Claude Code kör statusraden ofta och skickar med användningen
// (rate_limits). Vi vidarebefordrar den till Notchi och kör sedan din gamla statusrad, om du hade en.

let isStatusLine = CommandLine.arguments.contains("--statusline")
let input = FileHandle.standardInput.readDataToEndOfFile()
guard !input.isEmpty,
      var json = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else { exit(0) }
if isStatusLine { json["hook_event_name"] = "StatusLine" }

/// Vilken app körs sessionen i? Gå uppåt bland föräldraprocesserna tills vi hittar
/// en .app (Terminal, iTerm, Visual Studio Code, Claude …). Används för "hoppa dit".
func parentPID(_ pid: pid_t) -> pid_t? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
    let pp = info.kp_eproc.e_ppid
    return pp > 1 ? pp : nil
}
func executablePath(_ pid: pid_t) -> String? {
    var buf = [CChar](repeating: 0, count: 4 * 1024)
    let n = proc_pidpath(pid, &buf, UInt32(buf.count))
    return n > 0 ? String(cString: buf) : nil
}
func hostApp() -> String? {
    var pid = getppid()
    for _ in 0..<40 {
        if let p = executablePath(pid), let r = p.range(of: ".app/") {
            return String(p[..<r.lowerBound]) + ".app"     // yttersta .app, t.ex. "Visual Studio Code.app"
        }
        guard let pp = parentPID(pid) else { break }
        pid = pp
    }
    return nil
}
if !isStatusLine, ["SessionStart", "UserPromptSubmit", "PermissionRequest"].contains(json["hook_event_name"] as? String ?? ""),
   let app = hostApp() {
    json["notchi_app"] = app
}
let event = json["hook_event_name"] as? String ?? ""
let waitForReply = event == "PermissionRequest"

/// Kör din tidigare statusrad med samma indata, eller skriv en enkel egen
func finishStatusLine() -> Never {
    let prevFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notchi/prev-statusline.txt")
    if let prev = try? String(contentsOf: prevFile, encoding: .utf8),
       !prev.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", prev]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = FileHandle.nullDevice
        if (try? p.run()) != nil {
            inPipe.fileHandleForWriting.write(input)
            try? inPipe.fileHandleForWriting.close()
            let out = outPipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            FileHandle.standardOutput.write(out)
            exit(0)
        }
    }
    // Ingen tidigare statusrad: visa modell, kontext och 5-timmarsanvändning
    let model = (json["model"] as? [String: Any])?["display_name"] as? String ?? "Claude"
    var parts = [model]
    if let ctx = ((json["context_window"] as? [String: Any])?["used_percentage"] as? NSNumber)?.intValue {
        parts.append("\(ctx) % kontext")
    }
    if let five = (((json["rate_limits"] as? [String: Any])?["five_hour"] as? [String: Any])?["used_percentage"] as? NSNumber)?.doubleValue {
        parts.append("5 tim \(Int(five.rounded())) %")
    }
    print(parts.joined(separator: " · "))
    exit(0)
}

let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notchi/notchi.sock").path
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { if isStatusLine { finishStatusLine() }; exit(0) }

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let bytes = Array(path.utf8)
withUnsafeMutableBytes(of: &addr.sun_path) { buf in
    for (i, b) in bytes.prefix(buf.count - 1).enumerated() { buf[i] = b }
}
let connected = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard connected == 0 else {               // appen kör inte: gör ingenting
    if isStatusLine { finishStatusLine() }
    exit(0)
}

// Skicka händelsen på en rad (JSONSerialization skriver utan radbrytningar)
var payload = (try? JSONSerialization.data(withJSONObject: json)) ?? input
payload.append(10)
_ = payload.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }

guard waitForReply else {
    close(fd)
    if isStatusLine { finishStatusLine() }
    exit(0)
}

// Vänta på beslut (strax under Claude Codes standardtimeout på 600 s)
var tv = timeval(tv_sec: 590, tv_usec: 0)
setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
var reply = [UInt8]()
var chunk = [UInt8](repeating: 0, count: 1024)
while true {
    let n = read(fd, &chunk, chunk.count)
    if n <= 0 { break }
    reply.append(contentsOf: chunk[0..<n])
    if chunk[0..<n].contains(10) { break }
}
close(fd)

let text = String(decoding: reply, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
if !text.isEmpty { print(text) }   // tom = inget beslut → vanliga dialogen i terminalen
exit(0)
