//! Localisation de l'installation Discord selon la branche et la plateforme.

/// Branche de Discord ciblée.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Branch {
    Stable,
    Ptb,
    Canary,
}

impl Branch {
    /// Identifiant court (`stable`, `ptb`, `canary`).
    pub fn as_str(self) -> &'static str {
        match self {
            Branch::Stable => "stable",
            Branch::Ptb => "ptb",
            Branch::Canary => "canary",
        }
    }

    /// Nom du dossier dans `%LOCALAPPDATA%` (Windows) et libellé générique.
    pub fn dir_name(self) -> &'static str {
        match self {
            Branch::Stable => "Discord",
            Branch::Ptb => "DiscordPTB",
            Branch::Canary => "DiscordCanary",
        }
    }

    /// Nom de l'exécutable Discord sous Windows.
    #[cfg(windows)]
    pub fn exe_name(self) -> &'static str {
        match self {
            Branch::Stable => "Discord.exe",
            Branch::Ptb => "DiscordPTB.exe",
            Branch::Canary => "DiscordCanary.exe",
        }
    }

    /// Identifiant Flatpak (Linux).
    #[cfg(target_os = "linux")]
    pub fn flatpak_id(self) -> &'static str {
        match self {
            Branch::Stable => "com.discordapp.Discord",
            Branch::Ptb => "com.discordapp.DiscordPTB",
            Branch::Canary => "com.discordapp.DiscordCanary",
        }
    }

    /// Suffixe du binaire Linux (`discord`, `discord-ptb`, `discord-canary`).
    #[cfg(target_os = "linux")]
    pub fn linux_bin(self) -> &'static str {
        match self {
            Branch::Stable => "discord",
            Branch::Ptb => "discord-ptb",
            Branch::Canary => "discord-canary",
        }
    }
}

/// Trouve le chemin complet de l'exécutable Discord versionné sous Windows.
///
/// electron-hook attend ce chemin (ex. `...\Discord\app-1.0.9191\Discord.exe`) :
/// il en déduit le dossier `app-<version>` via `executable.parent()`.
#[cfg(windows)]
pub fn find_executable(branch: Branch) -> Result<String, String> {
    use std::path::PathBuf;

    let base = dirs::data_local_dir()
        .ok_or_else(|| "Impossible de déterminer %LOCALAPPDATA%.".to_string())?
        .join(branch.dir_name());

    if !base.join("Update.exe").exists() {
        return Err(format!(
            "Installation Discord ({}) introuvable : {} (Update.exe absent).",
            branch.as_str(),
            base.display()
        ));
    }

    // Collecte les dossiers app-<version> et trie par version (numériquement).
    let mut versions: Vec<(Vec<u64>, PathBuf)> = Vec::new();
    let entries = std::fs::read_dir(&base)
        .map_err(|e| format!("Lecture de {} : {e}", base.display()))?;
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if let Some(ver) = name.strip_prefix("app-") {
            let parts: Vec<u64> = ver.split('.').filter_map(|p| p.parse().ok()).collect();
            if !parts.is_empty() {
                versions.push((parts, path));
            }
        }
    }

    versions.sort_by(|a, b| a.0.cmp(&b.0));
    let (_, latest) = versions
        .last()
        .ok_or_else(|| format!("Aucun dossier app-<version> dans {}.", base.display()))?;

    let exe = latest.join(branch.exe_name());
    if !exe.exists() {
        return Err(format!("Exécutable introuvable : {}", exe.display()));
    }
    Ok(exe.to_string_lossy().into_owned())
}

/// Cible de lancement sous Linux : binaire du système de fichiers ou paquet Flatpak.
#[cfg(target_os = "linux")]
pub enum Target {
    Executable(String),
    Flatpak(electron_hook::FlatpakID),
}

/// Localise Discord sous Linux (installation classique puis Flatpak).
#[cfg(target_os = "linux")]
pub fn find_target(branch: Branch) -> Result<Target, String> {
    use std::path::PathBuf;
    use std::process::Command;

    let home = dirs::home_dir().ok_or_else(|| "HOME introuvable.".to_string())?;

    // 1. ~/.local/share/<Name>/<Name>
    let local = home
        .join(".local/share")
        .join(branch.dir_name())
        .join(branch.dir_name());
    if local.is_file() {
        return Ok(Target::Executable(local.to_string_lossy().into_owned()));
    }

    // 2. /usr/bin/discord[-branch]
    let usr = PathBuf::from("/usr/bin").join(branch.linux_bin());
    if usr.is_file() {
        return Ok(Target::Executable(usr.to_string_lossy().into_owned()));
    }

    // 3. `command -v <bin>`, sauf un snap : retenu pour le message d'erreur, mais on
    // essaie d'abord le Flatpak.
    let mut snap = None;
    if let Ok(output) = Command::new("sh")
        .arg("-c")
        .arg(format!("command -v {}", branch.linux_bin()))
        .output()
    {
        if output.status.success() {
            let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if is_snap(&path) {
                snap = Some(path);
            } else if !path.is_empty() {
                return Ok(Target::Executable(path));
            }
        }
    }

    // 4. Flatpak (installation utilisateur puis système)
    let id = branch.flatpak_id();
    let user_flatpak = home
        .join(".local/share/flatpak/app")
        .join(id);
    if user_flatpak.is_dir() {
        return Ok(Target::Flatpak(electron_hook::FlatpakID::User(id.to_string())));
    }
    if PathBuf::from("/var/lib/flatpak/app").join(id).is_dir() {
        return Ok(Target::Flatpak(electron_hook::FlatpakID::System(id.to_string())));
    }

    if let Some(path) = snap {
        return Err(format!(
            "Discord ({}) est installé en snap ({path}) : non supporté. Le confinement du \
             snap bloque l'injection (LD_PRELOAD ignoré par snap-confine, /usr/lib et \
             ~/.local invisibles). Installe le .deb officiel ou le Flatpak \
             (flatpak install flathub {}), puis relance.",
            branch.as_str(),
            branch.flatpak_id()
        ));
    }

    Err(format!(
        "Installation Discord ({}) introuvable sous Linux (ni dans ~/.local/share, ni /usr/bin, ni Flatpak).",
        branch.as_str()
    ))
}

/// Discord en snap : `/snap/bin/<bin>` est un lien vers `/usr/bin/snap`.
#[cfg(target_os = "linux")]
fn is_snap(path: &str) -> bool {
    let p = std::path::Path::new(path);
    // /usr/bin/snap peut lui-même être un lien (vers /usr/lib/snapd/snapd) : on compare
    // les chemins résolus.
    p.starts_with("/snap")
        || matches!(
            (std::fs::canonicalize(p), std::fs::canonicalize("/usr/bin/snap")),
            (Ok(a), Ok(b)) if a == b
        )
}

#[cfg(all(test, target_os = "linux"))]
mod tests {
    use super::is_snap;

    #[test]
    fn detects_snap_paths() {
        assert!(is_snap("/snap/bin/discord"));
        assert!(!is_snap("/usr/bin/env"));
        assert!(!is_snap(""));
    }

    #[test]
    fn detects_link_to_snap_binary() {
        if !std::path::Path::new("/usr/bin/snap").exists() {
            return; // snapd absent : rien à vérifier
        }
        let dir = std::env::temp_dir().join(format!("equicord-snap-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let link = dir.join("discord");
        let _ = std::fs::remove_file(&link);
        std::os::unix::fs::symlink("/usr/bin/snap", &link).unwrap();
        let result = is_snap(link.to_str().unwrap());
        std::fs::remove_dir_all(&dir).unwrap();
        assert!(result);
    }
}
