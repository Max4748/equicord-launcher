//! Orchestration : résout la config, génère l'asar, lance Discord avec la lib injectée.

use crate::config::Config;
use crate::discord::Branch;

/// `main` des binaires. Sous Windows ils sont compilés sans console (pas de fenêtre cmd
/// au lancement) : on se rattache à la console du parent si lancé depuis un terminal,
/// sinon les erreurs s'affichent dans une boîte de dialogue.
pub fn main(default_branch: Branch) {
    #[cfg(windows)]
    let has_console = attach_parent_console();
    #[cfg(windows)]
    wait_for_relaunching_discord();

    if let Err(e) = run(default_branch) {
        eprintln!("[equicord-launcher] Erreur : {e}");
        #[cfg(windows)]
        if !has_console {
            error_box(&e);
        }
        std::process::exit(1);
    }
}

#[cfg(windows)]
fn attach_parent_console() -> bool {
    use winapi::um::wincon::{AttachConsole, ATTACH_PARENT_PROCESS};
    unsafe { AttachConsole(ATTACH_PARENT_PROCESS) != 0 }
}

/// Relancé par Discord (« Relaunch » d'Equicord, voir require.js) : attend que l'ancien
/// Discord se ferme, sinon son verrou d'instance unique bloque le nouveau.
#[cfg(windows)]
fn wait_for_relaunching_discord() {
    use winapi::um::handleapi::CloseHandle;
    use winapi::um::processthreadsapi::OpenProcess;
    use winapi::um::synchapi::WaitForSingleObject;
    use winapi::um::winnt::SYNCHRONIZE;

    let Some(pid) = std::env::var("EQUICORD_LAUNCHER_WAIT_PID")
        .ok()
        .and_then(|p| p.parse::<u32>().ok())
    else {
        return;
    };
    std::env::remove_var("EQUICORD_LAUNCHER_WAIT_PID");
    unsafe {
        let handle = OpenProcess(SYNCHRONIZE, 0, pid);
        if !handle.is_null() {
            WaitForSingleObject(handle, 15_000);
            CloseHandle(handle);
        }
    }
}

#[cfg(windows)]
fn error_box(message: &str) {
    use std::os::windows::ffi::OsStrExt;
    use winapi::um::winuser::{MessageBoxW, MB_ICONERROR, MB_OK};

    let wide = |s: &str| -> Vec<u16> {
        std::ffi::OsStr::new(s).encode_wide().chain(std::iter::once(0)).collect()
    };
    let text = wide(message);
    let caption = wide("Equicord Launcher");
    unsafe {
        MessageBoxW(std::ptr::null_mut(), text.as_ptr(), caption.as_ptr(), MB_OK | MB_ICONERROR);
    }
}

/// Résout la config puis lance Discord.
pub fn run(default_branch: Branch) -> Result<(), String> {
    let config = Config::resolve(default_branch)?;
    run_with(config)
}

/// Lance Discord avec une configuration déjà résolue.
pub fn run_with(config: Config) -> Result<(), String> {
    let patcher = config.resolve_entrypoint()?;
    let library = resolve_library_path()?;

    // Par prudence : empêche un éventuel auto-patch côté mod (hérité de Vencord).
    std::env::set_var("DISABLE_UPDATER_AUTO_PATCHING", "true");

    let asar = electron_hook::asar::Asar::new()
        .with_id(&format!("equicord-{}", config.branch.as_str()))
        .with_mod_entrypoint(&patcher)
        .with_template(include_str!("require.js"))
        .with_wm_class(&format!("equicord-{}", config.branch.as_str()))
        .create()?;
    let asar = asar
        .to_str()
        .ok_or_else(|| "Chemin de l'asar généré invalide (non UTF-8).".to_string())?
        .to_string();

    let args = config.extra_args.clone();

    #[cfg(windows)]
    {
        let exe = crate::discord::find_executable(config.branch)?;
        electron_hook::launch(&exe, &library, &asar, args, false)?;
    }

    #[cfg(target_os = "linux")]
    {
        use crate::discord::Target;
        match crate::discord::find_target(config.branch)? {
            Target::Executable(exe) => {
                electron_hook::launch(&exe, &library, &asar, args, true)?;
            }
            Target::Flatpak(id) => {
                electron_hook::launch_flatpak(&id, &library, &asar, args, true)?;
            }
        }
    }

    #[cfg(not(any(windows, target_os = "linux")))]
    {
        let _ = (&library, &asar, &args);
        return Err("Plateforme non supportée (electron-hook ne gère que Windows et Linux).".into());
    }

    Ok(())
}

/// Localise la bibliothèque injectée (`equicord_launcher.dll` / `libequicord_launcher.so`)
/// à côté de l'exécutable, puis dans le répertoire courant.
fn resolve_library_path() -> Result<String, String> {
    #[cfg(windows)]
    let name = "equicord_launcher.dll";
    #[cfg(target_os = "linux")]
    let name = "libequicord_launcher.so";
    #[cfg(target_os = "macos")]
    let name = "libequicord_launcher.dylib";
    #[cfg(not(any(windows, target_os = "linux", target_os = "macos")))]
    let name = "equicord_launcher";

    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            let candidate = dir.join(name);
            if candidate.exists() {
                return Ok(candidate.to_string_lossy().into_owned());
            }
        }
    }

    if let Ok(cwd) = std::env::current_dir() {
        let candidate = cwd.join(name);
        if candidate.exists() {
            return Ok(candidate.to_string_lossy().into_owned());
        }
    }

    Err(format!(
        "Bibliothèque injectée « {name} » introuvable à côté de l'exécutable. \
         Garde-la dans le même dossier que le launcher."
    ))
}
