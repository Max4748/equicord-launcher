//! Configuration du launcher : arguments CLI (prioritaires) + fichier `config.toml` optionnel.

use crate::discord::Branch;
use clap::{Parser, ValueEnum};
use serde::Deserialize;
use std::path::{Path, PathBuf};

#[derive(Parser, Debug)]
#[command(about = "Réinjecte Equicord dans Discord à chaque lancement, sans patcher Discord.")]
struct Cli {
    /// Build Equicord local (racine du repo, `dist/`, `dist/desktop/` ou `.../patcher.js`).
    /// Sans ce chemin, la build officielle est téléchargée et tenue à jour.
    #[arg(long)]
    equicord: Option<PathBuf>,

    /// Branche Discord à lancer (défaut : celle du binaire utilisé).
    #[arg(long, value_enum)]
    branch: Option<BranchArg>,

    /// Fichier de config explicite (défaut : <config>/equicord-launcher/config.toml).
    #[arg(long)]
    config: Option<PathBuf>,

    /// Arguments passés tels quels à Discord (tout ce qui suit `--`).
    #[arg(last = true)]
    discord_args: Vec<String>,
}

#[derive(Copy, Clone, Debug, ValueEnum)]
enum BranchArg {
    Stable,
    Ptb,
    Canary,
}

impl From<BranchArg> for Branch {
    fn from(b: BranchArg) -> Self {
        match b {
            BranchArg::Stable => Branch::Stable,
            BranchArg::Ptb => Branch::Ptb,
            BranchArg::Canary => Branch::Canary,
        }
    }
}

/// Pas de `branch` ici : le fichier est partagé par les trois binaires, une branche
/// fixée dans le fichier faisait lancer la même à tous les raccourcis. Une clé `branch`
/// laissée par une version ≤ 0.2.2 est ignorée (serde ignore les clés inconnues).
#[derive(Deserialize, Default)]
struct FileConfig {
    /// Chemin vers le build Equicord.
    equicord_dist: Option<String>,
    /// Arguments passés à Discord.
    extra_args: Option<Vec<String>>,
}

/// Configuration résolue, prête à l'emploi.
pub struct Config {
    pub branch: Branch,
    /// Build local ; `None` = build officielle téléchargée.
    pub equicord: Option<PathBuf>,
    pub extra_args: Vec<String>,
}

impl Config {
    /// Fusionne les arguments CLI et le fichier de config. Le CLI est prioritaire.
    pub fn resolve(default_branch: Branch) -> Result<Config, String> {
        let cli = Cli::parse();
        let file = load_file_config(cli.config.as_deref())?;

        // La branche est celle du binaire lancé ; seul --branch la remplace.
        let branch = cli.branch.map(Branch::from).unwrap_or(default_branch);

        let equicord = cli
            .equicord
            .or_else(|| {
                file.equicord_dist
                    .as_deref()
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(PathBuf::from)
            });

        let extra_args = if cli.discord_args.is_empty() {
            file.extra_args.unwrap_or_default()
        } else {
            cli.discord_args
        };

        Ok(Config {
            branch,
            equicord,
            extra_args,
        })
    }

    /// Point d'entrée Equicord à charger : `patcher.js` du build local, sinon
    /// l'asar officiel (téléchargé ou mis à jour si besoin).
    pub fn resolve_entrypoint(&self) -> Result<String, String> {
        match &self.equicord {
            Some(base) => resolve_patcher(base),
            None => crate::updater::ensure_latest(),
        }
    }
}

/// Résout le chemin absolu du `patcher.js` d'un build local.
fn resolve_patcher(base: &Path) -> Result<String, String> {
    let candidates = [
        base.to_path_buf(),
        base.join("patcher.js"),
        base.join("desktop").join("patcher.js"),
        base.join("dist").join("desktop").join("patcher.js"),
    ];
    for c in candidates {
        if c.is_file() && c.file_name().is_some_and(|n| n == "patcher.js") {
            let abs = std::path::absolute(&c).map_err(|e| e.to_string())?;
            return Ok(abs.to_string_lossy().into_owned());
        }
    }
    Err(format!(
        "patcher.js introuvable à partir de « {} ». Attendu dist/desktop/patcher.js \
         (lance `pnpm build` dans ton clone d'Equicord).",
        base.display()
    ))
}

fn load_file_config(explicit: Option<&Path>) -> Result<FileConfig, String> {
    let path = match explicit {
        Some(p) => p.to_path_buf(),
        None => match dirs::config_dir() {
            Some(d) => d.join("equicord-launcher").join("config.toml"),
            None => return Ok(FileConfig::default()),
        },
    };

    if !path.exists() {
        if explicit.is_some() {
            return Err(format!("Fichier de config introuvable : {}", path.display()));
        }
        return Ok(FileConfig::default());
    }

    let text = std::fs::read_to_string(&path)
        .map_err(|e| format!("Lecture de {} : {e}", path.display()))?;
    toml::from_str(&text).map_err(|e| format!("Parsing de {} : {e}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::FileConfig;

    /// Un config.toml d'une ancienne version (avec `branch`) doit toujours se lire.
    #[test]
    fn ancienne_cle_branch_ignoree() {
        let file: FileConfig =
            toml::from_str("equicord_dist = \"x\"\nbranch = \"stable\"\n").unwrap();
        assert_eq!(file.equicord_dist.as_deref(), Some("x"));
    }
}
