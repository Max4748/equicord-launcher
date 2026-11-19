#!/usr/bin/env bash
# Fait lancer Equicord par les entrées de menu des branches Discord choisies, pour
# l'utilisateur courant (~/.local/share/applications). Remet les autres d'origine.
#
# Usage :
#   equicord-shortcuts                  # demande pour chaque branche (défaut : détectées)
#   equicord-shortcuts stable canary    # branches explicites
#   equicord-shortcuts --auto           # branches détectées, sans question
#   equicord-shortcuts --refresh        # réécrit les entrées déjà équipées (mise à jour)
#   equicord-shortcuts --remove         # retire tout, restaure les entrées d'origine
#   --icon discord|equicord             # logo des entrées (défaut : discord ; demandé
#                                       # en mode interactif, conservé par --refresh)
set -euo pipefail

PKG="equicord-launcher"
BRANCHES="stable ptb canary"
# Ligne posée dans chaque entrée écrite par ce script : on ne touche qu'à celles-là.
MARK="X-Equicord-Launcher=true"

# Les binaires du launcher sont à côté du vrai script (symlink résolu).
self="$(readlink -f "${BASH_SOURCE[0]}")"
libdir="$(dirname "$self")"
appsdir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

dir_name() { case "$1" in stable) echo Discord;; ptb) echo DiscordPTB;; canary) echo DiscordCanary;; esac; }
# Nom de la commande Discord = nom de son .desktop = classe de sa fenêtre (vérifié sous
# KDE Plasma 6 / Wayland pour les trois branches). Discord impose cette classe : on remplace donc son entrée
# plutôt que d'en créer une à part, sinon la barre des tâches affiche deux icônes.
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

ours() { [ -f "$1" ] && grep -qx "$MARK" "$1"; }

# Branche déjà équipée : entrée de ce script, ou ancien format equicord-<b>.desktop.
equipped() {
  ours "$appsdir/$(linux_bin "$1").desktop" || [ -f "$appsdir/equicord-$1.desktop" ]
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

# Choix d'icône des entrées déjà en place (pour --refresh). Lu dans X-Equicord-Icon, pas
# déduit de Icon= : le logo Equicord peut n'être que le repli de « discord ». Ancien
# format (sans cette clé) : logo Equicord = choix « equicord ».
current_icon() {
  local b f v
  for b in $BRANCHES; do
    f="$appsdir/$(linux_bin "$b").desktop"
    if ours "$f"; then
      v="$(sed -n 's/^X-Equicord-Icon=//p' "$f" | head -n1)"
      case "$v" in discord|equicord) echo "$v"; return;; esac
    fi
    f="$appsdir/equicord-$b.desktop"
    if [ -f "$f" ] && grep -qx "Icon=$PKG" "$f"; then echo equicord; return; fi
  done
  echo discord
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
  --refresh)
    for b in $BRANCHES; do equipped "$b" && selected="$selected $b"; done
    [ -n "$icon" ] || icon="$(current_icon)"
    ;;
  "")
    if [ ! -t 0 ]; then
      echo "Pas de terminal interactif : passe les branches en argument (ex. equicord-shortcuts stable)." >&2
      exit 1
    fi
    for b in $BRANCHES; do
      if detected "$b"; then def="O"; hint="[O/n]"; state="détecté"; else def="N"; hint="[o/N]"; state="non détecté"; fi
      read -r -p "Lancer $(label "$b") depuis le menu ($state) ? $hint " ans
      ans="${ans:-$def}"
      case "$ans" in [oOyY]*) selected="$selected $b";; esac
    done
    if [ -z "$icon" ] && [ -n "${selected// /}" ]; then
      read -r -p "Icône des entrées : logo Discord ou Equicord ? [D/e] " ans
      case "${ans:-d}" in [eE]*) icon="equicord";; *) icon="discord";; esac
    fi
    ;;
  -h|--help)
    sed -n '2,12p' "$self" | sed 's/^# \{0,1\}//'
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
  id="$(linux_bin "$b")"
  file="$appsdir/$id.desktop"
  backup="$file.equicord-bak"
  # Format des versions ≤ 0.2.1 : entrée séparée, remplacée par celle-ci.
  rm -f "$appsdir/equicord-$b.desktop"

  case " $selected " in
    *" $b "*)
      # Une entrée utilisateur existante (pas la nôtre) est mise de côté, restaurée par --remove.
      if [ -f "$file" ] && ! ours "$file" && [ ! -e "$backup" ]; then
        mv "$file" "$backup"
        echo ">> $id.desktop existant sauvegardé : $backup"
      fi
      exe="$libdir/equicord-$b"
      if [ "$icon" = "discord" ]; then icon_name="$(discord_icon "$b")"; else icon_name="$PKG"; fi
      mime=""
      [ "$b" = stable ] && mime="MimeType=x-scheme-handler/discord;"
      # --url -- %u : comme l'entrée officielle, pour ouvrir les liens discord://.
      cat > "$file" <<EOF
[Desktop Entry]
Type=Application
Name=$(label "$b")
Comment=Lance Discord avec Equicord injecté
Exec=$exe -- --url -- %u
TryExec=$exe
Icon=$icon_name
Terminal=false
Categories=Network;InstantMessaging;
StartupWMClass=$id
$mime
$MARK
X-Equicord-Icon=$icon
EOF
      echo ">> Menu : $(label "$b") (icône : $icon_name)"
      ;;
    *)
      if ours "$file"; then
        rm -f "$file"
        if [ -e "$backup" ]; then
          mv "$backup" "$file"
          echo ">> $id.desktop d'origine restauré."
        fi
      fi
      ;;
  esac
done

[ -n "${selected// /}" ] || echo ">> Aucune entrée Equicord : le menu lance Discord sans Equicord."
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$appsdir" >/dev/null 2>&1 || true
command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 >/dev/null 2>&1 || true
