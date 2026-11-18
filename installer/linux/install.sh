#!/usr/bin/env bash
# Installe Equicord Launcher pour l'utilisateur courant (sans sudo), sous ~/.local.
# Prérequis : rust (cargo). À exécuter sur la machine Linux cible.
set -euo pipefail

PKG="equicord-launcher"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"

# Toolchain épinglée par rust-toolchain.toml (nightly datée, requise par retour).
echo ">> cargo build --release"
( cd "$root" && cargo build --release )

rel="$root/target/release"
so="$rel/libequicord_launcher.so"
[ -f "$so" ] || { echo "libequicord_launcher.so introuvable dans $rel" >&2; exit 1; }

libdir="$HOME/.local/lib/$PKG"
bindir="$HOME/.local/bin"
mkdir -p "$libdir" "$bindir"

install -m 0755 "$rel/equicord-stable" "$libdir/"
install -m 0755 "$rel/equicord-ptb"    "$libdir/"
install -m 0755 "$rel/equicord-canary" "$libdir/"
install -m 0644 "$so" "$libdir/"

for b in stable ptb canary; do
  ln -sf "$libdir/equicord-$b" "$bindir/equicord-$b"
done

icondir="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
mkdir -p "$icondir"
install -m 0644 "$root/assets/equicord.png" "$icondir/$PKG.png"

install -m 0755 "$here/equicord-shortcuts.sh" "$libdir/equicord-shortcuts"
ln -sf "$libdir/equicord-shortcuts" "$bindir/equicord-shortcuts"

# Choix des Discord à équiper. Arguments transmis tels quels
# (ex. install.sh stable canary, ou install.sh --auto) ; sans argument, demande.
if [ "$#" -eq 0 ] && [ ! -t 0 ]; then
  "$libdir/equicord-shortcuts" --auto
else
  "$libdir/equicord-shortcuts" "$@"
fi

echo ">> Installé dans $libdir (binaires + lib) et $bindir (raccourcis PATH)."
case ":$PATH:" in
  *":$bindir:"*) : ;;
  *) echo ">> Ajoute $bindir à ton PATH (ex. dans ~/.profile) pour lancer par le nom.";;
esac
echo ">> Equicord est téléchargé au premier lancement et mis à jour automatiquement."
echo "   Build local (optionnel) : voir $root/config.example.toml"
