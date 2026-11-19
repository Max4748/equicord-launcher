# equicord-launcher

Launcher natif qui réinjecte **Equicord** dans Discord à **chaque lancement**, sans
jamais modifier les fichiers de l'installation Discord. Comme Discord est toujours
démarré via ce launcher, l'injection survit aux mises à jour du client.

Inspiré de [Vencord-Launcher](https://github.com/MeguminSama/Vencord-Launcher) et
[Discord-Modloader](https://github.com/MeguminSama/Discord-Modloader) de MeguminSama.
Repose sur la crate [`electron-hook`](https://crates.io/crates/electron-hook).

## Fonctionnement

1. Sans build local configuré, le launcher télécharge `desktop.asar` de la
   [release officielle](https://github.com/Equicord/Equicord/releases/tag/latest)
   d'Equicord, et le remplace à chaque lancement si une nouvelle version est publiée.
2. Il génère un petit `app.asar` (dans le cache `electron-hook`) dont l'`index.js`
   fait `require()` de cet asar (ou du `patcher.js` d'un build local).
3. Il lance Discord avec la bibliothèque `equicord_launcher.dll` injectée.
4. La lib hooke les accès fichiers de Discord et redirige la lecture de `app.asar`
   vers l'asar généré. L'`app.asar` original reste accessible sous `_app.asar`,
   et c'est le patcher d'Equicord qui recharge Discord par-dessus.

Aucun fichier du dossier `resources` de Discord n'est touché.

### Mise à jour d'Equicord

| Fichier | Emplacement |
| --- | --- |
| Build officielle | `%APPDATA%\equicord-launcher\equicord.asar` / `~/.local/share/equicord-launcher/equicord.asar` |
| Version installée | `equicord.asar.version` (id + date de l'asset GitHub ; le tag est toujours `latest`) |

La vérification se fait à chaque lancement (une requête à l'API GitHub). Hors ligne, la
copie en cache est utilisée. L'updater intégré d'Equicord peut aussi réécrire ce fichier
depuis Discord. Si Discord tourne déjà (Windows), le remplacement échoue et la copie en
cache est utilisée jusqu'au prochain lancement.

## Prérequis

- **Rust via [rustup](https://rustup.rs)** (pas le `cargo` d'apt). Le dépôt épingle
  `nightly-2025-03-01` dans `rust-toolchain.toml` : `retour`, tiré par `electron-hook`
  sous Linux, ne compile pas sur les rustc récents (ABI stdcall/fastcall,
  retour-rs#69). rustup installe cette toolchain tout seul, sur les deux plateformes.
- Optionnel, pour un build local d'Equicord : Node ≥ 22 et `pnpm`.

## Compiler le launcher

```
cargo build --release
```

Produit, dans `target/release/` : `equicord-stable.exe`, `equicord-ptb.exe`,
`equicord-canary.exe` et `equicord_launcher.dll`. **La DLL doit rester dans le même
dossier que l'exécutable** (le launcher la cherche à côté de lui).

## Build local d'Equicord (optionnel)

Utile pour tester des modifications d'Equicord. Le build local n'est jamais mis à jour
par le launcher.

```
git clone https://github.com/Equicord/Equicord
cd Equicord
pnpm install --frozen-lockfile
pnpm build
```

Le fichier à cibler est alors `Equicord/dist/desktop/patcher.js`.

## Utilisation

Ferme complètement Discord, puis lance `equicord-stable.exe` (build officielle). Avec un
build local :

```
equicord-stable.exe --equicord "C:\chemin\vers\Equicord\dist\desktop"
```

ou `equicord_dist` dans le fichier de config (voir `config.example.toml`).

### Options

| Option | Rôle |
| --- | --- |
| `--equicord <chemin>` | Build local : racine du repo, `dist/`, `dist/desktop/`, ou `.../patcher.js`. Désactive le téléchargement. |
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
donc Rust est requis sur la machine qui construit le paquet. Equicord n'est pas dans le
paquet : le launcher télécharge la build officielle au premier lancement (comme
Vencord-Launcher), puis la tient à jour.

### Windows (`.exe` via Inno Setup)

```
powershell -ExecutionPolicy Bypass -File installer\windows\build.ps1
```

Produit `installer\windows\output\equicord-launcher-setup.exe`. Nécessite Inno Setup 6
(`winget install -e --id JRSoftware.InnoSetup`). Le setup pose les trois exécutables + la
DLL pour l'utilisateur courant (sans droits admin), propose une case par Discord installé
(Stable, PTB, Canary ; seule Stable cochée) pour
créer les raccourcis menu Démarrer (+ Bureau en option), demande l'icône des raccourcis
(logo Discord de la branche, par défaut, ou logo Equicord ; relancer le setup pour changer), et
propose un build local d'Equicord (champ vide = build officielle ; écrit alors
`%APPDATA%\equicord-launcher\config.toml` sans écraser un fichier existant).

### Ubuntu / Debian (`.deb`)

```
chmod +x installer/linux/build-deb.sh
installer/linux/build-deb.sh
sudo apt install ./target/equicord-launcher_0.2.1_amd64.deb
```

Installe les binaires et la lib dans `/usr/lib/equicord-launcher/`, des symlinks dans
`/usr/bin` et l'icône Equicord. Installé via `sudo`, il crée les entrées de menu des
Discord détectés pour ton utilisateur. Configure ensuite
`~/.config/equicord-launcher/config.toml` (modèle dans `/usr/share/doc/equicord-launcher/`).

### Choisir les Discord équipés (Linux)

`equicord-shortcuts` crée les entrées de menu dans `~/.local/share/applications` et retire
celles des branches non choisies. Détection : `~/.local/share/<Discord>`, PATH, Flatpak.

| Commande | Effet |
| --- | --- |
| `equicord-shortcuts` | Demande pour chaque branche (défaut : oui si détectée) |
| `equicord-shortcuts stable canary` | Branches explicites |
| `equicord-shortcuts --auto` | Branches détectées, sans question |
| `equicord-shortcuts --remove` | Retire toutes les entrées |
| `--icon discord\|equicord` | Logo des raccourcis, combinable avec les commandes ci-dessus (défaut : `discord`, demandé en mode interactif) |

Avec `discord`, l'icône est cherchée dans le même ordre que Discord lui-même :
`~/.local/share/<Discord>/discord.png` (tar.gz), `discord*.png` du paquet système, puis
`com.discordapp.<Discord>` du Flatpak. Si rien n'est trouvé, le logo Equicord est utilisé.
Relancer `equicord-shortcuts` sans `--icon` remet le logo Discord.

Les entrées ont `TryExec` : elles disparaissent du menu si le launcher est désinstallé.

### Linux sans root (`~/.local`)

```
chmod +x installer/linux/install.sh installer/linux/uninstall.sh
installer/linux/install.sh      # pose tout sous ~/.local, puis lance equicord-shortcuts
                                # (arguments transmis : install.sh --auto --icon equicord)
installer/linux/uninstall.sh    # retire la version utilisateur
```

## Désinstallation

Le launcher ne modifie aucun fichier de Discord : une fois retiré, Discord se lance sans
Equicord, sans rien à restaurer.

| Installé via | Commande |
| --- | --- |
| Setup Windows | Paramètres > Applications > Equicord Launcher > Désinstaller (ou « Désinstaller Equicord Launcher » dans le menu Démarrer) |
| `.deb` | `equicord-shortcuts --remove` puis `sudo apt remove equicord-launcher` |
| `install.sh` | `installer/linux/uninstall.sh` |
| Build du dépôt | supprimer le raccourci créé à la main, puis `target/` |

Restent ensuite (à supprimer à la main si besoin) :

| Contenu | Windows | Linux |
| --- | --- | --- |
| Config | `%APPDATA%\equicord-launcher\config.toml` | `~/.config/equicord-launcher/` |
| Build Equicord téléchargée | retirée par le setup ; sinon `%APPDATA%\equicord-launcher\` | `~/.local/share/equicord-launcher/` (retirée par `uninstall.sh`) |
| Asar généré par electron-hook | `%LOCALAPPDATA%\electron-hook\` | `~/.cache/electron-hook/` |

Avec le `.deb`, les entrées `~/.local/share/applications/equicord-*.desktop` restent sur
le disque si `--remove` n'a pas été lancé avant, mais `TryExec` les masque du menu.

## Plateformes

- **Windows** : supporté (branche principale).
- **Linux** : supporté (installation classique et Flatpak) — non testé à ce jour.
- **macOS** : non supporté (`electron-hook` ne le gère pas encore).

## Licences

- Ce launcher : **GPL-3.0**.
- `electron-hook` : LGPL-3.0 (dépendance dynamique).
- Equicord : GPL-3.0. Non inclus dans les paquets ; téléchargé depuis ses releases GitHub.
