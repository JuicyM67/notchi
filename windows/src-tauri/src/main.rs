// Tamanotchi för Windows. Samma exe är både appen och hooken som Claude Code kör:
//   tamanotchi.exe                 → ön högst upp på skärmen + ikon i aktivitetsfältet
//   tamanotchi.exe --hook          → skickar en Claude Code-händelse till appen
//   tamanotchi.exe --uninstall     → tar bort hooks och autostart (körs av avinstalleraren)
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod hook;
mod paths;
mod server;
mod setup;
mod system;
mod usage;

use std::sync::Mutex;
use std::time::Duration;

use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, LogicalPosition, Manager, State, WebviewWindow};

/// Var ön är i fönstret (logiska pixlar). Utanför den går musen rakt igenom till fönstren under.
#[derive(Default)]
struct Hit(Mutex<[f64; 4]>);

#[tauri::command]
fn set_hit(hit: State<Hit>, x: f64, y: f64, w: f64, h: f64) {
    *hit.0.lock().unwrap() = [x, y, w, h];
}

#[tauri::command]
fn decide(pending: State<server::Pending>, id: u64, reply: String) {
    pending.answer(id, reply);
}

#[tauri::command]
fn place(window: WebviewWindow, x: f64, y: f64) {
    let _ = window.set_position(LogicalPosition::new(x, y));
}

#[tauri::command]
fn ready(window: WebviewWindow, autostart: bool) {
    let _ = window.show();
    let _ = window.set_always_on_top(true);
    system::set_autostart(autostart);
}

#[tauri::command]
fn set_autostart(on: bool) {
    system::set_autostart(on);
}

#[tauri::command]
fn jump(cwd: String, app: String) {
    system::jump(cwd, app);
}

#[tauri::command]
fn speak(app: AppHandle, speech: State<system::Speech>, text: String) {
    system::speak(app, &speech, text);
}

#[tauri::command]
fn stop_speaking(speech: State<system::Speech>) {
    system::stop(&speech);
}

/// Känner av musen 20 gånger i sekunden: över ön tar vi emot klick, annars släpps de igenom
fn watch_mouse(app: AppHandle) {
    std::thread::spawn(move || {
        let mut was_inside = false;
        loop {
            std::thread::sleep(Duration::from_millis(50));
            let Some(w) = app.get_webview_window("main") else { continue };
            let (Ok(cur), Ok(pos), Ok(scale)) = (w.cursor_position(), w.outer_position(), w.scale_factor()) else { continue };
            let [x, y, rw, rh] = *app.state::<Hit>().0.lock().unwrap();
            let cx = (cur.x - pos.x as f64) / scale;
            let cy = (cur.y - pos.y as f64) / scale;
            let inside = rw > 0.0 && cx >= x - 2.0 && cx <= x + rw + 2.0 && cy >= y - 2.0 && cy <= y + rh + 2.0;
            if inside != was_inside {
                was_inside = inside;
                let _ = w.set_ignore_cursor_events(!inside);
                let _ = app.emit("cursor", inside);
            }
        }
    });
}

fn tray(app: &tauri::App) -> tauri::Result<()> {
    let show = MenuItem::with_id(app, "show", "Visa Tamanotchi", true, None::<&str>)?;
    let settings = MenuItem::with_id(app, "settings", "Inställningar…", true, None::<&str>)?;
    let sep = PredefinedMenuItem::separator(app)?;
    let quit = MenuItem::with_id(app, "quit", "Avsluta Tamanotchi", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &settings, &sep, &quit])?;
    let mut builder = TrayIconBuilder::with_id("main")
        .tooltip("Tamanotchi")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, e| match e.id.as_ref() {
            "show" => {
                let _ = app.emit("show", "main");
            }
            "settings" => {
                let _ = app.emit("show", "settings");
            }
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, e| {
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = e {
                let _ = tray.app_handle().emit("show", "main");
            }
        });
    if let Some(icon) = app.default_window_icon() {
        builder = builder.icon(icon.clone());
    }
    builder.build(app)?;
    Ok(())
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.iter().any(|a| a == "--hook") {
        hook::run(args.iter().any(|a| a == "--statusline"));
        return;
    }
    if args.iter().any(|a| a == "--uninstall") {
        let _ = setup::uninstall_hooks();
        system::set_autostart(false);
        let _ = std::fs::remove_file(paths::server_file());
        return;
    }
    // Kör den redan? Visa den i stället för att starta en till.
    if server::poke_running() {
        return;
    }

    tauri::Builder::default()
        .manage(Hit::default())
        .manage(server::Pending::default())
        .manage(system::Speech::default())
        .invoke_handler(tauri::generate_handler![set_hit, decide, place, ready, set_autostart, jump, speak, stop_speaking])
        .setup(|app| {
            if let Err(e) = setup::install_hooks() {
                eprintln!("Kunde inte koppla in hooks: {e}");
            }
            server::start(app.handle().clone())?;
            usage::start(app.handle().clone());
            if let Some(w) = app.get_webview_window("main") {
                let _ = w.set_ignore_cursor_events(true);
            }
            watch_mouse(app.handle().clone());
            tray(app)?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("Tamanotchi kunde inte starta");
}
