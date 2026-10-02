//! Kopplar in (och ur) Tamanotchi i Claude Codes settings.json. Samma regler som merge-hooks.js på Mac:
//! dina egna hooks lämnas orörda, en säkerhetskopia sparas innan något ändras, och en statusrad
//! du redan hade körs vidare av Tamanotchi.
use std::fs;
use std::path::PathBuf;

use serde_json::{json, Map, Value};

use crate::paths;

/// (händelse, körs i bakgrunden, timeout)
const EVENTS: &[(&str, bool, Option<u64>)] = &[
    ("SessionStart", true, None),
    ("UserPromptSubmit", true, None),
    ("PreToolUse", true, None),
    ("PostToolUse", true, None),
    ("Notification", true, None),
    ("Stop", true, None),
    ("SessionEnd", true, None),
    // Godkännanden måste vänta på ditt svar
    ("PermissionRequest", false, Some(600)),
];

fn settings_path() -> PathBuf {
    paths::home().join(".claude").join("settings.json")
}

fn is_ours(v: &Value) -> bool {
    let s = v.to_string().to_lowercase();
    (s.contains("tamanotchi") && s.contains("--hook")) || s.contains("notchi-hook")
}

/// Lägg till (cmd = Some) eller ta bort (cmd = None) våra hooks och vår statusrad
pub fn merge(root: &mut Value, cmd: Option<&str>) {
    if !root.is_object() {
        *root = json!({});
    }
    let obj = root.as_object_mut().unwrap();

    let mut hooks = obj.get("hooks").and_then(Value::as_object).cloned().unwrap_or_default();
    for (ev, background, timeout) in EVENTS {
        let mut groups: Vec<Value> = hooks
            .get(*ev)
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default()
            .into_iter()
            .filter(|g| !is_ours(g))
            .collect();
        if let Some(c) = cmd {
            let mut h = Map::new();
            h.insert("type".into(), json!("command"));
            h.insert("command".into(), json!(format!("{c} --hook")));
            if *background {
                h.insert("async".into(), json!(true));
            }
            if let Some(t) = timeout {
                h.insert("timeout".into(), json!(t));
            }
            groups.push(json!({ "matcher": "*", "hooks": [Value::Object(h)] }));
        }
        if groups.is_empty() {
            hooks.remove(*ev);
        } else {
            hooks.insert((*ev).to_string(), Value::Array(groups));
        }
    }
    if hooks.is_empty() {
        obj.remove("hooks");
    } else {
        obj.insert("hooks".into(), Value::Object(hooks));
    }

    // Statusraden: där skickar Claude Code din användning (5 tim / vecka)
    let prev_file = paths::dir().join("prev-statusline.txt");
    let current = obj.get("statusLine").cloned();
    let ours = current.as_ref().map(is_ours).unwrap_or(false);
    match cmd {
        Some(c) => {
            if let (Some(sl), false) = (&current, ours) {
                let prev = sl.get("command").and_then(Value::as_str).unwrap_or("");
                let _ = fs::write(&prev_file, prev);
            }
            obj.insert("statusLine".into(), json!({ "type": "command", "command": format!("{c} --hook --statusline"), "padding": 0 }));
        }
        None if ours => {
            let prev = fs::read_to_string(&prev_file).unwrap_or_default();
            if prev.trim().is_empty() {
                obj.remove("statusLine");
            } else {
                obj.insert("statusLine".into(), json!({ "type": "command", "command": prev.trim() }));
            }
        }
        None => {}
    }
}

fn apply(cmd: Option<&str>) -> Result<bool, String> {
    let path = settings_path();
    let raw = fs::read_to_string(&path).unwrap_or_default();
    let mut root: Value = if raw.trim().is_empty() {
        json!({})
    } else {
        // Går filen inte att läsa som JSON rör vi den inte
        serde_json::from_str(&raw).map_err(|e| format!("settings.json gick inte att läsa: {e}"))?
    };
    let before = root.to_string();
    merge(&mut root, cmd);
    if root.to_string() == before {
        return Ok(false);
    }
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    if !raw.trim().is_empty() {
        let stamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
        let _ = fs::write(path.with_file_name(format!("settings.json.tamanotchi-backup-{stamp}")), &raw);
    }
    let text = serde_json::to_string_pretty(&root).map_err(|e| e.to_string())? + "\n";
    fs::write(&path, text).map_err(|e| e.to_string())?;
    Ok(true)
}

/// Körs varje gång appen startar (gör inget om allt redan är på plats)
pub fn install_hooks() -> Result<bool, String> {
    let exe = paths::exe_for_hooks().ok_or("hittar inte appens sökväg")?;
    apply(Some(&exe))
}

/// Körs av avinstalleraren
pub fn uninstall_hooks() -> Result<bool, String> {
    apply(None)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn merge_keeps_user_hooks_and_is_idempotent() {
        let mut v = json!({
            "model": "opus",
            "hooks": { "Stop": [ { "matcher": "*", "hooks": [ { "type": "command", "command": "say klar" } ] } ] }
        });
        merge(&mut v, Some("\"C:/App/tamanotchi.exe\""));
        let once = v.to_string();
        merge(&mut v, Some("\"C:/App/tamanotchi.exe\""));
        assert_eq!(once, v.to_string());
        assert_eq!(v["hooks"]["Stop"].as_array().unwrap().len(), 2);
        assert_eq!(v["hooks"]["PermissionRequest"][0]["hooks"][0]["timeout"], 600);
        assert_eq!(v["statusLine"]["command"], "\"C:/App/tamanotchi.exe\" --hook --statusline");
        merge(&mut v, None);
        assert_eq!(v["hooks"]["Stop"].as_array().unwrap().len(), 1);
        assert!(v["hooks"].get("PreToolUse").is_none());
        assert!(v.get("statusLine").is_none());
        assert_eq!(v["model"], "opus");
    }
}
