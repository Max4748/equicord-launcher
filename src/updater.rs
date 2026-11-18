//! Téléchargement et mise à jour de la build officielle d'Equicord.
//!
//! On récupère `desktop.asar` de la release GitHub `latest` d'Equicord, comme
//! l'installeur officiel (Equilotl). Le tag ne change jamais (`latest`) : la
//! version est identifiée par l'id + la date de l'asset, stockés à côté de l'asar.
//!
//! L'updater intégré d'Equicord réécrit lui-même ce fichier (`writeFileSync(__dirname)`)
//! quand une mise à jour est appliquée depuis Discord : les deux mécanismes coexistent.

use serde::Deserialize;
use std::path::PathBuf;
use std::time::Duration;

const RELEASE_URL: &str = "https://api.github.com/repos/Equicord/Equicord/releases/latest";
const ASSET_NAME: &str = "desktop.asar";
const USER_AGENT: &str = concat!("equicord-launcher/", env!("CARGO_PKG_VERSION"));

#[derive(Deserialize)]
struct Release {
    assets: Vec<Asset>,
}

#[derive(Deserialize)]
struct Asset {
    id: u64,
    name: String,
    updated_at: String,
    browser_download_url: String,
}

/// Dossier de cache : `%APPDATA%\equicord-launcher` / `~/.local/share/equicord-launcher`.
fn cache_dir() -> Result<PathBuf, String> {
    let dir = dirs::data_dir()
        .ok_or_else(|| "Dossier de données utilisateur introuvable.".to_string())?
        .join("equicord-launcher");
    std::fs::create_dir_all(&dir).map_err(|e| format!("Création de {} : {e}", dir.display()))?;
    Ok(dir)
}

/// Garantit une copie à jour de `equicord.asar` et renvoie son chemin.
///
/// Hors ligne ou en cas d'erreur réseau, la copie en cache est utilisée si elle existe.
pub fn ensure_latest() -> Result<String, String> {
    let dir = cache_dir()?;
    let asar = dir.join("equicord.asar");
    let version_file = dir.join("equicord.asar.version");

    match update(&asar, &version_file) {
        Ok(true) => println!("[equicord-launcher] Equicord mis à jour."),
        Ok(false) => {}
        Err(e) if asar.is_file() => {
            eprintln!("[equicord-launcher] Mise à jour impossible ({e}), version en cache utilisée.")
        }
        Err(e) => return Err(format!("Téléchargement d'Equicord impossible : {e}")),
    }

    Ok(asar.to_string_lossy().into_owned())
}

/// Télécharge l'asar si la release a changé. Renvoie `true` si un fichier a été écrit.
fn update(asar: &PathBuf, version_file: &PathBuf) -> Result<bool, String> {
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_connect(Some(Duration::from_secs(5)))
        .timeout_recv_body(Some(Duration::from_secs(120)))
        .build()
        .into();

    let release: Release = agent
        .get(RELEASE_URL)
        .header("User-Agent", USER_AGENT)
        .header("Accept", "application/vnd.github+json")
        .call()
        .map_err(|e| e.to_string())?
        .body_mut()
        .read_json()
        .map_err(|e| e.to_string())?;

    let asset = release
        .assets
        .into_iter()
        .find(|a| a.name == ASSET_NAME)
        .ok_or_else(|| format!("{ASSET_NAME} absent de la release."))?;

    let version = format!("{}:{}", asset.id, asset.updated_at);
    let current = std::fs::read_to_string(version_file).unwrap_or_default();
    if asar.is_file() && current.trim() == version {
        return Ok(false);
    }

    println!("[equicord-launcher] Téléchargement d'Equicord ({})...", asset.updated_at);
    let mut response = agent
        .get(&asset.browser_download_url)
        .header("User-Agent", USER_AGENT)
        .call()
        .map_err(|e| e.to_string())?;

    // Écriture dans un fichier temporaire puis renommage : l'asar en place n'est
    // jamais laissé à moitié écrit.
    let tmp = asar.with_extension("asar.tmp");
    {
        let mut file =
            std::fs::File::create(&tmp).map_err(|e| format!("{} : {e}", tmp.display()))?;
        std::io::copy(&mut response.body_mut().as_reader(), &mut file)
            .map_err(|e| format!("Téléchargement interrompu : {e}"))?;
    }
    if let Err(e) = std::fs::rename(&tmp, asar) {
        let _ = std::fs::remove_file(&tmp);
        // Typiquement : Discord tourne déjà et garde l'asar ouvert (Windows).
        return Err(format!("Remplacement de {} : {e}", asar.display()));
    }
    std::fs::write(version_file, version).map_err(|e| e.to_string())?;
    Ok(true)
}

#[cfg(test)]
mod tests {
    /// Test réseau : `cargo test -- --ignored`.
    #[test]
    #[ignore]
    fn downloads_release() {
        let path = super::ensure_latest().expect("téléchargement");
        let len = std::fs::metadata(&path).unwrap().len();
        assert!(len > 1_000_000, "asar trop petit : {len} octets");
    }
}
