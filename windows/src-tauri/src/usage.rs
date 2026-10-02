//! Hämtar Claude-användningen (5 timmar / vecka) med Claude Codes egen inloggning.
//!
//! Statusraden – den dokumenterade vägen – körs inte i VS Code-tillägget, så här frågar vi samma
//! interna adress som Claude Code själv använder för /usage. Den är inte dokumenterad och kan
//! ändras; slutar den fungera blir det bara tyst. Var 5:e minut, 15 minuters paus vid "för många".
use std::time::Duration;

use serde_json::Value;
use tauri::{AppHandle, Emitter};

use crate::paths;

const URL: &str = "https://api.anthropic.com/api/oauth/usage";

/// Claude Code sparar inloggningen i %USERPROFILE%\.claude\.credentials.json på Windows
fn token() -> Option<String> {
    let raw = std::fs::read_to_string(paths::home().join(".claude").join(".credentials.json")).ok()?;
    let v: Value = serde_json::from_str(&raw).ok()?;
    let oauth = v.get("claudeAiOauth")?;
    let tok = oauth.get("accessToken")?.as_str()?.to_string();
    if let Some(exp) = oauth.get("expiresAt").and_then(Value::as_f64) {
        let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).ok()?.as_millis() as f64;
        if exp < now {
            return None; // utgången: Claude Code förnyar den nästa gång du använder det
        }
    }
    (!tok.is_empty()).then_some(tok)
}

pub fn start(app: AppHandle) {
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(6));
        let Ok(tls) = native_tls::TlsConnector::new() else { return };
        let agent = ureq::AgentBuilder::new()
            .timeout(Duration::from_secs(15))
            .tls_connector(std::sync::Arc::new(tls))
            .build();
        loop {
            let mut wait = 300;
            if let Some(tok) = token() {
                let res = agent
                    .get(URL)
                    .set("Authorization", &format!("Bearer {tok}"))
                    .set("anthropic-beta", "oauth-2025-04-20")
                    .set("Accept", "application/json")
                    .set("User-Agent", "tamanotchi-windows/0.1")
                    .call();
                match res {
                    Ok(r) => {
                        if let Ok(v) = r.into_json::<Value>() {
                            let _ = app.emit("usage", v);
                        }
                    }
                    Err(ureq::Error::Status(429, _)) => wait = 900,
                    Err(_) => {}
                }
            }
            std::thread::sleep(Duration::from_secs(wait));
        }
    });
}
