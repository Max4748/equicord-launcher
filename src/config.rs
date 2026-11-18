//! Configuration du launcher : arguments CLI (prioritaires) + fichier `config.toml` optionnel.

use crate::discord::Branch;
use clap::{Parser, ValueEnum};
use serde::Deserialize;
use std::path::{Path, PathBuf};

#[derive(Parser, Debug)]
#[command(about = "Réinjecte Equicord dans Discord à chaque lancement, sans patcher Discord.")]
struct Cli {
    /// Chemin vers le build Equicord : racine du repo, `dist/`, `dist/desktop/`,
    /// ou directement `.../dist/desktop/patcher.js`.
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

#[derive(Deserialize, Default)]
struct FileConfig {
    /// Chemin vers le build Equicord.
    equicord_dist: Option<String>,
    /// Branche par défaut (`stable` | `ptb` | `canary`).
    branch: Option<String>,
    /// Arguments passés à Discord.
    extra_args: Option<Vec<String>>,
}

/// Configuration résolue, prête à l'emploi.
pub struct Config {
    pub branch: Branch,
    pub equicord: PathBuf,
    pub extra_args: Vec<String>,
}

impl Config {
    /// Fusionne les arguments CLI et le fichier de config. Le CLI est prioritaire.
    pub fn resolve(default_branch: Branch) -> Result<Config, String> {
        let cli = Cli::parse();
        let file = load_file_config(cli.config.as_deref())?;

        let branch = cli
            .branch
            .map(Branch::from)
            .or_else(|| file.branch.as_deref().and_then(parse_branch))
            .unwrap_or(default_branch);

        let equicord = cli
            .equicord
            .or_else(|| file.equicord_dist.as_ref().map(PathBuf::from))
            .ok_or_else(|| {
                "Aucun chemin Equicord fourni. Passe --equicord <.../dist/desktop> \
                 ou renseigne 'equicord_dist' dans le fichier de config."
                    .to_string()
            })?;

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

    /// Résout le chemin absolu du `patcher.js` d'Equicord à partir du chemin fourni.
    pub fn resolve_patcher(&self) -> Result<String, String> {
        let base = &self.equicord;
        let candidates = [
            base.clone(),
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

fn parse_branch(s: &str) -> Option<Branch> {
    match s.to_ascii_lowercase().as_str() {
        "stable" => Some(Branch::Stable),
        "ptb" => Some(Branch::Ptb),
        "canary" => Some(Branch::Canary),
        _ => None,
    }
}
