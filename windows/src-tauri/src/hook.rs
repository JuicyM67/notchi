//! `tamanotchi.exe --hook`: körs av Claude Code vid varje hook-händelse.
//! Läser händelsen (JSON) från stdin och skickar den till appen. För PermissionRequest väntar den
//! på Tillåt/Neka och skriver svaret till stdout. Kör inte appen gör den ingenting, och Claude Code
//! frågar som vanligt.
//!
//! `--hook --statusline`: Claude Codes statusrad. Skickar vidare användningen (rate_limits) och
//! skriver sedan statusraden: din gamla, om du hade en, annars en enkel egen.
use std::io::{Read, Write};
use std::time::Duration;

use serde_json::{json, Value};

use crate::{paths, server};

/// Var körs Claude Code? Används för "hoppa dit" (VS Code öppnar rätt projektfönster).
fn host_app() -> Option<&'static str> {
    let e = |k: &str| std::env::var(k).unwrap_or_default();
    if e("TERM_PROGRAM") == "vscode"
        || e("CLAUDE_CODE_ENTRYPOINT").contains("vscode")
        || !e("VSCODE_PID").is_empty()
        || !e("VSCODE_IPC_HOOK").is_empty()
        || !e("VSCODE_IPC_HOOK_CLI").is_empty()
    {
        Some("vscode")
    } else if !e("WT_SESSION").is_empty() {
        Some("terminal")
    } else {
        None
    }
}

pub fn run(statusline: bool) {
    let mut input = String::new();
    let _ = std::io::stdin().read_to_string(&mut input);
    let mut json: Value = serde_json::from_str(&input).unwrap_or(Value::Null);
    if !json.is_object() {
        if statusline {
            finish_statusline(&input, &json);
        }
        return;
    }
    if statusline {
        json["hook_event_name"] = json!("StatusLine");
    }
    let event = json.get("hook_event_name").and_then(Value::as_str).unwrap_or("").to_string();
    if matches!(event.as_str(), "SessionStart" | "UserPromptSubmit" | "PermissionRequest") {
        if let Some(app) = host_app() {
            json["tamanotchi_app"] = json!(app);
        }
    }

    if let Some((mut stream, token)) = server::connection() {
        json["tamanotchi_token"] = json!(token);
        let line = json.to_string() + "\n";
        if stream.write_all(line.as_bytes()).is_ok() && event == "PermissionRequest" {
            // Vänta på beslut (strax under Claude Codes timeout på 600 s)
            let _ = stream.set_read_timeout(Some(Duration::from_secs(590)));
            let mut reply = String::new();
            let _ = stream.read_to_string(&mut reply);
            let reply = reply.trim();
            if !reply.is_empty() {
                let mut out = std::io::stdout();
                let _ = writeln!(out, "{reply}");
                let _ = out.flush();
            }
        }
    }

    if statusline {
        finish_statusline(&input, &json);
    }
}

fn finish_statusline(input: &str, json: &Value) {
    let prev = std::fs::read_to_string(paths::dir().join("prev-statusline.txt")).unwrap_or_default();
    let prev = prev.trim();
    let mut out = std::io::stdout();
    if !prev.is_empty() {
        if let Some(text) = run_previous(prev, input) {
            let _ = out.write_all(text.as_bytes());
            let _ = out.flush();
            return;
        }
    }
    let model = json.pointer("/model/display_name").and_then(Value::as_str).unwrap_or("Claude");
    let mut parts = vec![model.to_string()];
    if let Some(c) = json.pointer("/context_window/used_percentage").and_then(Value::as_f64) {
        parts.push(format!("{} % kontext", c.round()));
    }
    if let Some(f) = json.pointer("/rate_limits/five_hour/used_percentage").and_then(Value::as_f64) {
        parts.push(format!("5 tim {} %", f.round()));
    }
    let _ = writeln!(out, "{}", parts.join(" · "));
    let _ = out.flush();
}

fn run_previous(cmd: &str, input: &str) -> Option<String> {
    use std::process::{Command, Stdio};
    #[cfg(windows)]
    let mut c = {
        use std::os::windows::process::CommandExt;
        let mut c = Command::new("cmd");
        c.raw_arg(format!("/C {cmd}")).creation_flags(0x0800_0000);
        c
    };
    #[cfg(not(windows))]
    let mut c = {
        let mut c = Command::new("sh");
        c.arg("-c").arg(cmd);
        c
    };
    let mut child = c.stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().ok()?;
    if let Some(mut si) = child.stdin.take() {
        let _ = si.write_all(input.as_bytes());
    }
    let out = child.wait_with_output().ok()?;
    Some(String::from_utf8_lossy(&out.stdout).into_owned())
}
