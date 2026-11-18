#!/usr/bin/env bash
# Installe Equicord Launcher pour l'utilisateur courant (sans sudo), sous ~/.local.
# Prérequis : rust (cargo). À exécuter sur la machine Linux cible.
set -euo pipefail

PKG="equicord-launcher"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"

# nightly requis : retour (static-detour), utilisé par electron-hook sous Linux,
# dépend de features Rust nightly.
echo ">> cargo +nightly build --release"
( cd "$root" && cargo +nightly build --release )

rel="$root/target/release"
so="$rel/libequicord_launcher.so"
[ -f "$so" ] || { echo "libequicord_launcher.so introuvable dans $rel" >&2; exit 1; }

libdir="$HOME/.local/lib/$PKG"
bindir="$HOME/.local/bin"
appsdir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$libdir" "$bindir" "$appsdir"

install -m 0755 "$rel/equicord-stable" "$libdir/"
install -m 0755 "$rel/equicord-ptb"    "$libdir/"
install -m 0755 "$rel/equicord-canary" "$libdir/"
install -m 0644 "$so" "$libdir/"

for b in stable ptb canary; do
  ln -sf "$libdir/equicord-$b" "$bindir/equicord-$b"
done

for b in stable ptb canary; do
  case "$b" in
    stable) label="Equicord (Discord)";;
    ptb)    label="Equicord (Discord PTB)";;
    canary) label="Equicord (Discord Canary)";;
  esac
  cat > "$appsdir/equicord-$b.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$label
Comment=Lance Discord avec Equicord injecté
Exec=$bindir/equicord-$b
Icon=discord
Terminal=false
Categories=Network;InstantMessaging;
StartupWMClass=equicord-$b
EOF
done

echo ">> Installé dans $libdir (binaires + lib) et $bindir (raccourcis PATH)."
case ":$PATH:" in
  *":$bindir:"*) : ;;
  *) echo ">> Ajoute $bindir à ton PATH (ex. dans ~/.profile) pour lancer par le nom.";;
esac
echo ">> Configure ensuite ~/.config/$PKG/config.toml (voir $root/config.example.toml)"
echo "   ou lance : equicord-stable --equicord <chemin-vers-Equicord/dist/desktop>"
