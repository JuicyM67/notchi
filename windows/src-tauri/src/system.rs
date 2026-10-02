//! Det som pratar med Windows: autostart, hoppa till projektet och reservrösten.
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;

use tauri::{AppHandle, Emitter};

#[cfg(windows)]
use std::os::windows::process::CommandExt;

/// Inget konsolfönster blinkar till när vi kör ett kommando
#[cfg(windows)]
const NO_WINDOW: u32 = 0x0800_0000;

fn quiet(mut c: Command) -> Command {
    #[cfg(windows)]
    c.creation_flags(NO_WINDOW);
    c
}

/// Starta med Windows (HKCU\…\Run, bara för ditt konto)
pub fn set_autostart(on: bool) {
    #[cfg(windows)]
    {
        let key = r"HKCU\Software\Microsoft\Windows\CurrentVersion\Run";
        let mut c = quiet(Command::new("reg"));
        if on {
            let Ok(exe) = std::env::current_exe() else { return };
            c.args(["add", key, "/v", "Tamanotchi", "/t", "REG_SZ", "/f", "/d"])
                .arg(format!("\"{}\"", exe.display()));
        } else {
            c.args(["delete", key, "/v", "Tamanotchi", "/f"]);
        }
        let _ = c.stdout(Stdio::null()).stderr(Stdio::null()).status();
    }
    #[cfg(not(windows))]
    let _ = on;
}

/// Klick på en session: VS Code öppnar (eller visar) fönstret för just det projektet.
/// Annars öppnas projektmappen i Utforskaren.
pub fn jump(cwd: String, app: String) {
    if cwd.is_empty() {
        return;
    }
    std::thread::spawn(move || {
        #[cfg(windows)]
        {
            if app != "terminal" {
                let mut c = quiet(Command::new("cmd"));
                c.raw_arg(format!("/C code \"{cwd}\""));
                if matches!(c.stdout(Stdio::null()).stderr(Stdio::null()).status(), Ok(s) if s.success()) {
                    return;
                }
            }
            let _ = quiet(Command::new("explorer")).arg(&cwd).spawn();
        }
        #[cfg(not(windows))]
        let _ = (cwd, app);
    });
}

/// Reservröst via Windows talsyntes (System.Speech), om webbvyns röst inte får prata
#[derive(Default)]
pub struct Speech(Mutex<Option<Child>>);

const SPEAK_PS: &str = "[Console]::InputEncoding=[Text.Encoding]::UTF8;$t=[Console]::In.ReadToEnd();\
Add-Type -AssemblyName System.Speech;$s=New-Object System.Speech.Synthesis.SpeechSynthesizer;\
$v=$s.GetInstalledVoices()|Where-Object{$_.VoiceInfo.Culture.Name -like 'sv*'}|Select-Object -First 1;\
if($v){$s.SelectVoice($v.VoiceInfo.Name)};$s.Speak($t)";

pub fn speak(app: AppHandle, speech: &Speech, text: String) {
    stop(speech);
    let mut c = quiet(Command::new("powershell"));
    c.args(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", SPEAK_PS]);
    let Ok(mut child) = c.stdin(Stdio::piped()).stdout(Stdio::null()).stderr(Stdio::null()).spawn() else {
        let _ = app.emit("speech-end", ());
        return;
    };
    if let Some(mut si) = child.stdin.take() {
        use std::io::Write;
        let _ = si.write_all(text.as_bytes());
    }
    let pid = child.id();
    *speech.0.lock().unwrap() = Some(child);
    // Säg till när talet är klart (pollar, så att stop() kan döda processen under tiden)
    let app2 = app.clone();
    std::thread::spawn(move || loop {
        std::thread::sleep(std::time::Duration::from_millis(200));
        use tauri::Manager;
        let state = app2.state::<Speech>();
        let mut guard = state.0.lock().unwrap();
        match guard.as_mut() {
            Some(ch) if ch.id() == pid => {
                if let Ok(Some(_)) = ch.try_wait() {
                    *guard = None;
                    let _ = app2.emit("speech-end", ());
                    break;
                }
            }
            _ => break,
        }
    });
}

pub fn stop(speech: &Speech) {
    if let Some(mut ch) = speech.0.lock().unwrap().take() {
        let _ = ch.kill();
    }
}
