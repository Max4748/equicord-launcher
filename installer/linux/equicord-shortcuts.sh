#!/usr/bin/env bash
# Crée les entrées de menu Equicord pour les branches Discord choisies, pour
# l'utilisateur courant (~/.local/share/applications). Retire celles non choisies.
#
# Usage :
#   equicord-shortcuts                  # demande pour chaque branche (défaut : détectées)
#   equicord-shortcuts stable canary    # branches explicites
#   equicord-shortcuts --auto           # branches détectées, sans question
#   equicord-shortcuts --remove         # retire toutes les entrées
#   --icon discord|equicord             # logo des raccourcis (défaut : discord ;
#                                       # demandé en mode interactif)
set -euo pipefail

PKG="equicord-launcher"
BRANCHES="stable ptb canary"

# Les binaires du launcher sont à côté du vrai script (symlink résolu).
self="$(readlink -f "${BASH_SOURCE[0]}")"
libdir="$(dirname "$self")"
appsdir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

dir_name() { case "$1" in stable) echo Discord;; ptb) echo DiscordPTB;; canary) echo DiscordCanary;; esac; }
linux_bin() { case "$1" in stable) echo discord;; ptb) echo discord-ptb;; canary) echo discord-canary;; esac; }
label() { case "$1" in stable) echo "Equicord (Discord)";; ptb) echo "Equicord (Discord PTB)";; canary) echo "Equicord (Discord Canary)";; esac; }

# Même ordre de recherche que src/discord.rs (find_target).
detected() {
  local d id
  d="$(dir_name "$1")"
  id="com.discordapp.$d"
  [ -f "$HOME/.local/share/$d/$d" ] \
    || command -v "$(linux_bin "$1")" >/dev/null 2>&1 \
    || [ -d "$HOME/.local/share/flatpak/app/$id" ] \
    || [ -d "/var/lib/flatpak/app/$id" ]
}

valid_branch() { case "$1" in stable|ptb|canary) return 0;; *) return 1;; esac; }

# Icône Discord de la branche, dans l'ordre de find_target (src/discord.rs) : tar.gz,
# paquet système, Flatpak. Rien trouvé : logo Equicord, plutôt qu'une icône vide.
discord_icon() {
  local d bin id f
  d="$(dir_name "$1")"; bin="$(linux_bin "$1")"; id="com.discordapp.$d"
  for f in "$HOME/.local/share/$d/discord.png" "$HOME/.local/share/$d/$bin.png"; do
    [ -f "$f" ] && { echo "$f"; return; }
  done
  for f in /usr/share/pixmaps/"$bin".png /usr/share/icons/hicolor/*/apps/"$bin".png; do
    [ -f "$f" ] && { echo "$bin"; return; }
  done
  for f in "$HOME"/.local/share/flatpak/exports/share/icons/hicolor/*/apps/"$id".* \
           /var/lib/flatpak/exports/share/icons/hicolor/*/apps/"$id".*; do
    [ -f "$f" ] && { echo "$id"; return; }
  done
  echo "$PKG"
}

# --icon peut se placer n'importe où ; le reste des arguments garde son sens.
icon=""
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --icon)
      [ $# -ge 2 ] || { echo "--icon attend « discord » ou « equicord »" >&2; exit 1; }
      icon="$2"; shift 2;;
    --icon=*) icon="${1#--icon=}"; shift;;
    *)        args+=("$1"); shift;;
  esac
done
set -- "${args[@]+"${args[@]}"}"
case "$icon" in
  ""|discord|equicord) ;;
  *) echo "--icon attend « discord » ou « equicord » (reçu : « $icon »)" >&2; exit 1;;
esac

selected=""
case "${1:-}" in
  --remove)
    ;;
  --auto)
    for b in $BRANCHES; do detected "$b" && selected="$selected $b"; done
    ;;
  "")
    if [ ! -t 0 ]; then
      echo "Pas de terminal interactif : passe les branches en argument (ex. equicord-shortcuts stable)." >&2
      exit 1
    fi
    for b in $BRANCHES; do
      if detected "$b"; then def="O"; hint="[O/n]"; state="détecté"; else def="N"; hint="[o/N]"; state="non détecté"; fi
      read -r -p "Raccourci pour $(label "$b") ($state) ? $hint " ans
      ans="${ans:-$def}"
      case "$ans" in [oOyY]*) selected="$selected $b";; esac
    done
    if [ -z "$icon" ] && [ -n "${selected// /}" ]; then
      read -r -p "Icône des raccourcis : logo Discord ou Equicord ? [D/e] " ans
      case "${ans:-d}" in [eE]*) icon="equicord";; *) icon="discord";; esac
    fi
    ;;
  -h|--help)
    sed -n '2,11p' "$self" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    for b in "$@"; do
      valid_branch "$b" || { echo "Branche inconnue : $b (stable, ptb ou canary)" >&2; exit 1; }
      selected="$selected $b"
    done
    ;;
esac

icon="${icon:-discord}"

mkdir -p "$appsdir"
for b in $BRANCHES; do
  file="$appsdir/equicord-$b.desktop"
  case " $selected " in
    *" $b "*)
      exe="$libdir/equicord-$b"
      if [ "$icon" = "discord" ]; then icon_name="$(discord_icon "$b")"; else icon_name="$PKG"; fi
      # TryExec : l'entrée disparaît du menu si le launcher est désinstallé.
      cat > "$file" <<EOF
[Desktop Entry]
Type=Application
Name=$(label "$b")
Comment=Lance Discord avec Equicord injecté
Exec=$exe
TryExec=$exe
Icon=$icon_name
Terminal=false
Categories=Network;InstantMessaging;
StartupWMClass=equicord-$b
EOF
      echo ">> Raccourci : $(label "$b") (icône : $icon_name)"
      ;;
    *)
      rm -f "$file"
      ;;
  esac
done

[ -n "${selected// /}" ] || echo ">> Aucun raccourci Equicord dans le menu."
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$appsdir" >/dev/null 2>&1 || true
