#!/usr/bin/env bash
# Construit un paquet .deb (Ubuntu/Debian) pour Equicord Launcher.
# Prérequis : rust (cargo), dpkg-deb. À exécuter sur la machine Linux cible.
set -euo pipefail

VERSION="0.1.0"
PKG="equicord-launcher"
ARCH="$(dpkg --print-architecture)"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"

# Toolchain épinglée par rust-toolchain.toml (nightly datée, requise par retour).
echo ">> cargo build --release"
( cd "$root" && cargo build --release )

rel="$root/target/release"
so="$rel/libequicord_launcher.so"
[ -f "$so" ] || { echo "libequicord_launcher.so introuvable dans $rel" >&2; exit 1; }

build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

libdir="$build/usr/lib/$PKG"
bindir="$build/usr/bin"
appsdir="$build/usr/share/applications"
docdir="$build/usr/share/doc/$PKG"
mkdir -p "$libdir" "$bindir" "$appsdir" "$docdir" "$build/DEBIAN"

# Les binaires et la .so vivent ensemble : le launcher cherche la lib à côté de lui,
# et current_exe() résout le symlink de /usr/bin vers le vrai chemin dans /usr/lib.
install -m 0755 "$rel/equicord-stable" "$libdir/"
install -m 0755 "$rel/equicord-ptb"    "$libdir/"
install -m 0755 "$rel/equicord-canary" "$libdir/"
install -m 0644 "$so" "$libdir/"

for b in stable ptb canary; do
  ln -sf "../lib/$PKG/equicord-$b" "$bindir/equicord-$b"
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
Exec=equicord-$b
Icon=discord
Terminal=false
Categories=Network;InstantMessaging;
StartupWMClass=equicord-$b
EOF
done

install -m 0644 "$root/config.example.toml" "$docdir/"
install -m 0644 "$root/README.md" "$docdir/"

cat > "$build/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION
Section: net
Priority: optional
Architecture: $ARCH
Maintainer: equicord-launcher <noreply@localhost>
Depends: libc6
Description: Launcher natif qui réinjecte Equicord dans Discord à chaque lancement.
 Ne modifie jamais les fichiers de Discord ; l'injection survit aux mises à jour.
 Nécessite un build local d'Equicord, configuré dans
 ~/.config/equicord-launcher/config.toml (voir /usr/share/doc/$PKG/config.example.toml).
EOF

cat > "$build/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
echo "equicord-launcher : crée ~/.config/equicord-launcher/config.toml avec le chemin de"
echo "ton build Equicord (dist/desktop), ou lance : equicord-stable --equicord <chemin>"
echo "Modèle : /usr/share/doc/equicord-launcher/config.example.toml"
exit 0
EOF
chmod 0755 "$build/DEBIAN/postinst"

out="$root/target/${PKG}_${VERSION}_${ARCH}.deb"
dpkg-deb --root-owner-group --build "$build" "$out"

echo ">> Paquet : $out"
echo ">> Installe : sudo apt install \"$out\""
