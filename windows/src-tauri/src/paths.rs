//! Var Tamanotchi och Claude Code har sina filer.
use std::path::PathBuf;

/// Användarens hemmapp (C:\Users\namn)
pub fn home() -> PathBuf {
    std::env::var_os("USERPROFILE")
        .or_else(|| std::env::var_os("HOME"))
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."))
}

/// %USERPROFILE%\.tamanotchi – samma namn som på Mac
pub fn dir() -> PathBuf {
    let d = home().join(".tamanotchi");
    let _ = std::fs::create_dir_all(&d);
    d
}

/// Port och nyckel till appens lokala server (skrivs när appen startar)
pub fn server_file() -> PathBuf {
    dir().join("server.json")
}

/// Den här exe-filen, med snedstreck framåt så att sökvägen fungerar både i cmd och i Git Bash
pub fn exe_for_hooks() -> Option<String> {
    let p = std::env::current_exe().ok()?;
    let s = p.to_string_lossy().replace("\\\\?\\", "").replace('\\', "/");
    Some(format!("\"{s}\""))
}
