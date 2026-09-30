import Foundation
import Darwin

// notchi-hook: körs av Claude Code vid varje hook-händelse.
// Läser händelsen (JSON) från stdin och skickar den till Notchi-appen via en Unix-socket.
// För PermissionRequest väntar den på svar (Tillåt/Neka) och skriver det till stdout.
// Om appen inte är igång avslutar den tyst, så att Claude Code fungerar precis som vanligt.

let input = FileHandle.standardInput.readDataToEndOfFile()
guard !input.isEmpty,
      let json = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else { exit(0) }
let event = json["hook_event_name"] as? String ?? ""
let waitForReply = event == "PermissionRequest"

let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notchi/notchi.sock").path
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(0) }

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
guard connected == 0 else { exit(0) }   // appen kör inte: gör ingenting

// Skicka händelsen på en rad (JSONSerialization skriver utan radbrytningar)
var payload = (try? JSONSerialization.data(withJSONObject: json)) ?? input
payload.append(10)
_ = payload.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }

guard waitForReply else { close(fd); exit(0) }

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
