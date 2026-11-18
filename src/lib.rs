//! Launcher Equicord natif.
//!
//! Ce crate produit deux choses :
//!
//! - une **cdylib** (`equicord_launcher.dll` / `libequicord_launcher.so`) qui
//!   réexporte `electron_hook`. C'est elle qu'on passe en `library_path` à
//!   [`electron_hook::launch`] : elle est injectée dans le process Discord et
//!   redirige la lecture de `app.asar` vers l'asar généré. Aucun fichier de
//!   l'installation Discord n'est modifié.
//! - des **binaires** (un par branche Discord) qui appellent [`launcher::run`].
pub use electron_hook::*;

pub mod config;
pub mod discord;
pub mod launcher;
