# equicord-launcher

Launcher natif qui réinjecte **Equicord** dans Discord à **chaque lancement**, sans
jamais modifier les fichiers de l'installation Discord. Comme Discord est toujours
démarré via ce launcher, l'injection survit aux mises à jour du client.

Inspiré de [Vencord-Launcher](https://github.com/MeguminSama/Vencord-Launcher) et
[Discord-Modloader](https://github.com/MeguminSama/Discord-Modloader) de MeguminSama.
Repose sur la crate [`electron-hook`](https://crates.io/crates/electron-hook).

## Fonctionnement

1. Le launcher génère un petit `app.asar` (dans le cache `electron-hook`) dont
   l'`index.js` fait `require(patcher.js)` d'Equicord.
2. Il lance Discord avec la bibliothèque `equicord_launcher.dll` injectée.
3. La lib hooke les accès fichiers de Discord et redirige la lecture de `app.asar`
   vers l'asar généré. L'`app.asar` original reste accessible sous `_app.asar`,
   et c'est le patcher d'Equicord qui recharge Discord par-dessus.

Aucun fichier du dossier `resources` de Discord n'est touché.

## Prérequis

- **Rust via [rustup](https://rustup.rs)** (pas le `cargo` d'apt). Le dépôt épingle
  `nightly-2025-03-01` dans `rust-toolchain.toml` : `retour`, tiré par `electron-hook`
  sous Linux, ne compile pas sur les rustc récents (ABI stdcall/fastcall,
  retour-rs#69). rustup installe cette toolchain tout seul, sur les deux plateformes.
- Un **build local d'Equicord** : Node ≥ 22 et `pnpm`.

## Compiler le launcher

```
cargo build --release
```

Produit, dans `target/release/` : `equicord-stable.exe`, `equicord-ptb.exe`,
`equicord-canary.exe` et `equicord_launcher.dll`. **La DLL doit rester dans le même
dossier que l'exécutable** (le launcher la cherche à côté de lui).

## Construire Equicord

```
git clone https://github.com/Equicord/Equicord
cd Equicord
pnpm install --frozen-lockfile
pnpm build
```

Le fichier à cibler est alors `Equicord/dist/desktop/patcher.js`.

## Utilisation

Ferme complètement Discord, puis lance par exemple :

```
equicord-stable.exe --equicord "C:\chemin\vers\Equicord\dist\desktop"
```

Ou renseigne le chemin une fois pour toutes dans un fichier de config (voir
`config.example.toml`) et lance simplement `equicord-stable.exe`.

### Options

| Option | Rôle |
| --- | --- |
| `--equicord <chemin>` | Build Equicord : racine du repo, `dist/`, `dist/desktop/`, ou `.../patcher.js`. |
| `--branch <stable\|ptb\|canary>` | Force la branche (par défaut : celle du binaire). |
| `--config <fichier>` | Fichier de config explicite. |
| `-- <args>` | Arguments transmis tels quels à Discord. |

### Fichier de config

Cherché par défaut dans :

- Windows : `%APPDATA%\equicord-launcher\config.toml`
- Linux : `~/.config/equicord-launcher/config.toml`

Les options CLI sont prioritaires. Voir `config.example.toml`.

## Installeurs

Scripts dans `installer/`. Ils compilent d'abord le launcher (`cargo build --release`),
donc Rust est requis sur la machine qui construit le paquet. Ils n'embarquent **pas**
Equicord : tu renseignes le chemin de ton build local après coup (config ou `--equicord`).

### Windows (`.exe` via Inno Setup)

```
powershell -ExecutionPolicy Bypass -File installer\windows\build.ps1
```

Produit `installer\windows\output\equicord-launcher-setup.exe`. Nécessite Inno Setup 6
(`winget install -e --id JRSoftware.InnoSetup`). Le setup pose les trois exécutables + la
DLL, crée les raccourcis (Bureau + menu Démarrer pour Stable ; PTB/Canary en option) et
propose d'écrire `%APPDATA%\equicord-launcher\config.toml` (sans écraser un fichier existant).
Désinstallation via « Applications » de Windows.

### Ubuntu / Debian (`.deb`)

```
chmod +x installer/linux/build-deb.sh
installer/linux/build-deb.sh
sudo apt install ./target/equicord-launcher_0.1.0_amd64.deb
```

Installe les binaires et la lib dans `/usr/lib/equicord-launcher/`, des symlinks dans
`/usr/bin`, et les entrées de menu dans `/usr/share/applications`. Configure ensuite
`~/.config/equicord-launcher/config.toml` (modèle dans `/usr/share/doc/equicord-launcher/`).

### Linux sans root (`~/.local`)

```
chmod +x installer/linux/install.sh installer/linux/uninstall.sh
installer/linux/install.sh      # pose tout sous ~/.local
installer/linux/uninstall.sh    # retire la version utilisateur
```

## Plateformes

- **Windows** : supporté (branche principale).
- **Linux** : supporté (installation classique et Flatpak) — non testé à ce jour.
- **macOS** : non supporté (`electron-hook` ne le gère pas encore).

## Licences

- Ce launcher : **GPL-3.0**.
- `electron-hook` : LGPL-3.0 (dépendance dynamique).
- Equicord : GPL-3.0 — non redistribué ici, c'est ton propre build local qui est chargé.
