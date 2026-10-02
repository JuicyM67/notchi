//! Lokal server som hooken pratar med (bara 127.0.0.1, skyddad med en slumpad nyckel).
//! Samma idé som Unix-socketen på Mac: en rad JSON in, och för godkännanden en rad svar tillbaka.
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{mpsc, Mutex};
use std::time::{Duration, Instant};

use serde_json::{json, Value};
use tauri::{AppHandle, Emitter, Manager};

use crate::paths;

/// Godkännanden som väntar på ditt svar
#[derive(Default)]
pub struct Pending(Mutex<HashMap<u64, mpsc::Sender<String>>>);

impl Pending {
    pub fn answer(&self, id: u64, reply: String) {
        if let Some(tx) = self.0.lock().unwrap().remove(&id) {
            let _ = tx.send(reply);
        }
    }
}

static NEXT_ID: AtomicU64 = AtomicU64::new(1);

/// En nyckel som bara ditt konto kan läsa (den ligger i din hemmapp)
fn random_token() -> String {
    use std::collections::hash_map::RandomState;
    use std::hash::{BuildHasher, Hasher};
    let mut out = String::new();
    for i in 0..2u64 {
        let mut h = RandomState::new().build_hasher();
        h.write_u64(i);
        h.write_u128(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_nanos());
        h.write_u32(std::process::id());
        out.push_str(&format!("{:016x}", h.finish()));
    }
    out
}

pub fn start(app: AppHandle) -> std::io::Result<()> {
    let listener = TcpListener::bind("127.0.0.1:0")?;
    let port = listener.local_addr()?.port();
    let token = random_token();
    std::fs::write(paths::server_file(), json!({ "port": port, "token": token, "pid": std::process::id() }).to_string())?;

    std::thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            let app = app.clone();
            let token = token.clone();
            std::thread::spawn(move || handle(app, stream, &token));
        }
    });
    Ok(())
}

fn handle(app: AppHandle, mut stream: TcpStream, token: &str) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
    let mut line = String::new();
    {
        let Ok(clone) = stream.try_clone() else { return };
        let mut reader = BufReader::new(clone).take(4 * 1024 * 1024);
        if reader.read_line(&mut line).is_err() {
            return;
        }
    }
    let Ok(mut json) = serde_json::from_str::<Value>(&line) else { return };
    if json.get("tamanotchi_token").and_then(Value::as_str) != Some(token) {
        return;
    }
    if let Some(o) = json.as_object_mut() {
        o.remove("tamanotchi_token");
    }
    let name = json.get("hook_event_name").and_then(Value::as_str).unwrap_or("").to_string();

    match name.as_str() {
        // Appen startades igen: visa den som redan kör i stället
        "Show" => {
            let _ = app.emit("show", "main");
            let _ = stream.write_all(b"ok\n");
        }
        "PermissionRequest" => {
            let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
            let (tx, rx) = mpsc::channel();
            app.state::<Pending>().0.lock().unwrap().insert(id, tx);
            json["tamanotchi_id"] = json!(id);
            let _ = app.emit("hook", &json);

            // Vänta på ditt svar, men märk om hooken försvinner (du svarade i VS Code, eller sessionen avbröts)
            let started = Instant::now();
            loop {
                match rx.recv_timeout(Duration::from_millis(500)) {
                    Ok(reply) => {
                        let _ = stream.write_all(format!("{reply}\n").as_bytes());
                        break;
                    }
                    Err(mpsc::RecvTimeoutError::Timeout) => {
                        if peer_closed(&stream) || started.elapsed() > Duration::from_secs(590) {
                            let _ = app.emit("hook-closed", id);
                            break;
                        }
                    }
                    Err(_) => break,
                }
            }
            app.state::<Pending>().0.lock().unwrap().remove(&id);
        }
        _ => {
            let _ = app.emit("hook", &json);
        }
    }
}

fn peer_closed(s: &TcpStream) -> bool {
    if s.set_nonblocking(true).is_err() {
        return true;
    }
    let mut b = [0u8; 1];
    let closed = match s.peek(&mut b) {
        Ok(0) => true,
        Ok(_) => false,
        Err(e) => e.kind() != std::io::ErrorKind::WouldBlock,
    };
    let _ = s.set_nonblocking(false);
    closed
}

/// Läs port och nyckel till en app som redan kör
pub fn connection() -> Option<(TcpStream, String)> {
    let raw = std::fs::read_to_string(paths::server_file()).ok()?;
    let v: Value = serde_json::from_str(&raw).ok()?;
    let port = v.get("port")?.as_u64()? as u16;
    let token = v.get("token")?.as_str()?.to_string();
    let addr = std::net::SocketAddr::from(([127, 0, 0, 1], port));
    let stream = TcpStream::connect_timeout(&addr, Duration::from_millis(400)).ok()?;
    Some((stream, token))
}

/// Kör Tamanotchi redan? Då ber vi den visa sig och avslutar den här kopian.
pub fn poke_running() -> bool {
    let Some((mut s, token)) = connection() else { return false };
    let msg = json!({ "tamanotchi_token": token, "hook_event_name": "Show" }).to_string() + "\n";
    if s.write_all(msg.as_bytes()).is_err() {
        return false;
    }
    let _ = s.set_read_timeout(Some(Duration::from_millis(800)));
    let mut buf = String::new();
    let _ = s.read_to_string(&mut buf);
    buf.trim() == "ok"
}
