#!/usr/bin/env bash
# Construit un paquet .deb (Ubuntu/Debian) pour Equicord Launcher.
# Prérequis : rust (cargo), dpkg-deb. À exécuter sur la machine Linux cible.
set -euo pipefail

VERSION="0.2.2"
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
docdir="$build/usr/share/doc/$PKG"
mkdir -p "$libdir" "$bindir" "$docdir" "$build/DEBIAN"

# Les binaires et la .so vivent ensemble : le launcher cherche la lib à côté de lui,
# et current_exe() résout le symlink de /usr/bin vers le vrai chemin dans /usr/lib.
install -m 0755 "$rel/equicord-stable" "$libdir/"
install -m 0755 "$rel/equicord-ptb"    "$libdir/"
install -m 0755 "$rel/equicord-canary" "$libdir/"
install -m 0644 "$so" "$libdir/"

for b in stable ptb canary; do
  ln -sf "../lib/$PKG/equicord-$b" "$bindir/equicord-$b"
done

# Icône Equicord embarquée : "Icon=discord" n'existe que si le .deb officiel de
# Discord est installé (absente avec Flatpak ou le tar.gz).
icondir="$build/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$icondir"
install -m 0644 "$root/assets/equicord.png" "$icondir/$PKG.png"

# Pas d'entrée de menu système : chaque utilisateur choisit ses branches Discord
# avec equicord-shortcuts (entrées dans ~/.local/share/applications).
install -m 0755 "$here/equicord-shortcuts.sh" "$libdir/equicord-shortcuts"
ln -sf "../lib/$PKG/equicord-shortcuts" "$bindir/equicord-shortcuts"

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
 Télécharge la build officielle d'Equicord et la tient à jour ; un build local
 peut être configuré (voir /usr/share/doc/$PKG/config.example.toml).
EOF

cat > "$build/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
# Installé via sudo : équipe les entrées de menu des Discord détectés pour cet
# utilisateur. Mise à jour ($2 = version précédente) : garde son choix de branches.
if [ "$1" = "configure" ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  if [ -n "${2:-}" ]; then mode="--refresh"; else mode="--auto"; fi
  su - "$SUDO_USER" -c "/usr/bin/equicord-shortcuts $mode" || true
fi
echo "equicord-launcher : choisis les Discord à équiper avec : equicord-shortcuts"
echo "Equicord est téléchargé au premier lancement et mis à jour automatiquement."
echo "Build local (optionnel) : voir /usr/share/doc/equicord-launcher/config.example.toml"
exit 0
EOF
chmod 0755 "$build/DEBIAN/postinst"

cat > "$build/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
# Les entrées Equicord masquent celles de Discord : on les retire (et restaure les
# originales) avant que le script disparaisse, sinon Discord n'aurait plus d'entrée.
# Seul l'utilisateur qui lance sudo est traité ; les autres : equicord-shortcuts --remove.
if [ "$1" = "remove" ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  su - "$SUDO_USER" -c "/usr/bin/equicord-shortcuts --remove" || true
fi
exit 0
EOF
chmod 0755 "$build/DEBIAN/prerm"

out="$root/target/${PKG}_${VERSION}_${ARCH}.deb"
dpkg-deb --root-owner-group --build "$build" "$out"

echo ">> Paquet : $out"
echo ">> Installe : sudo apt install \"$out\""
