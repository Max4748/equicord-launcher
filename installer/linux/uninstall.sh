#!/usr/bin/env bash
# Désinstalle la version utilisateur posée par install.sh (ne touche pas à un paquet .deb).
set -euo pipefail

PKG="equicord-launcher"
libdir="$HOME/.local/lib/$PKG"
bindir="$HOME/.local/bin"
appsdir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

for b in stable ptb canary; do
  rm -f "$bindir/equicord-$b" "$appsdir/equicord-$b.desktop"
done
rm -f "$bindir/equicord-shortcuts"
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps/$PKG.png"
rm -rf "$libdir"
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/$PKG/equicord.asar"*

echo ">> Désinstallé. La config ~/.config/$PKG/ et le build Equicord ne sont pas touchés."
