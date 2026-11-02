#!/usr/bin/env bash
# Name: universal-linux-ssh-banner.sh
# Description: Interactive FIGlet SSH login banner manager for Linux.
# Version: 2.0.0
# Updated: 2026-11-02
# Usage: sudo bash universal-linux-ssh-banner.sh [--help]
# Requirements: Bash, supported package manager, FIGlet (installed on demand).
set -euo pipefail

BANNER_FILE=/etc/tbox-ssh-banner.txt
COLOR_FILE=/etc/tbox-ssh-banner.color
PROFILE_FILE=/etc/profile.d/99-tbox-ssh-banner.sh
LEGACY_FILE=/etc/profile.d/tbox-banner.sh

usage() {
  cat <<'HELP'
Universal Linux SSH Banner Manager
Usage: sudo bash universal-linux-ssh-banner.sh [--help]
Supports: dnf, yum, apt-get, zypper, pacman, apk
Installs a banner for interactive SSH login shells sourcing /etc/profile.
No changes are made to sshd_config.
HELP
}
[[ ${1:-} == --help || ${1:-} == -h ]] && { usage; exit 0; }
(( EUID == 0 )) || { echo 'Run as root using sudo.' >&2; exit 1; }
[[ -t 0 ]] || { echo 'An interactive terminal is required.' >&2; exit 1; }

install_figlet() {
  command -v figlet >/dev/null 2>&1 && return 0
  echo 'FIGlet is not installed.'
  local response
  read -r -p 'Install FIGlet using the system package manager? [Y/n]: ' response
  [[ ${response:-y} =~ ^[Yy]$ ]] || { echo 'Installation cancelled.'; return 1; }
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get install -y figlet
  elif command -v dnf >/dev/null 2>&1; then
    if ! dnf install -y figlet; then
      echo 'FIGlet was not available in enabled repositories. Enable EPEL or another trusted repository and retry.' >&2
      return 1
    fi
  elif command -v yum >/dev/null 2>&1; then
    yum install -y figlet
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install figlet
  elif command -v pacman >/dev/null 2>&1; then
    pacman --noconfirm -S figlet
  elif command -v apk >/dev/null 2>&1; then
    apk add figlet
  else
    echo 'Unsupported package manager; install figlet manually.' >&2
    return 1
  fi
  command -v figlet >/dev/null 2>&1 || { echo 'FIGlet installation could not be verified.' >&2; return 1; }
}

color_code() {
  case "$1" in
    green) printf 32;; cyan) printf 36;; yellow) printf 33;; red) printf 31;;
    blue) printf 34;; magenta) printf 35;; white) printf 37;; default) printf '';;
    *) printf '';;
  esac
}

preview() {
  local color=$1 content=$2 code
  code=$(color_code "$color")
  if [[ -t 1 && -n "$code" && ${TERM:-dumb} != dumb ]]; then
    printf '\033[%sm%s\033[0m\n' "$code" "$content"
  else
    printf '%s\n' "$content"
  fi
}

choose_color() {
  local answer
  echo 'Colors: 1) default  2) green  3) cyan  4) yellow  5) red  6) blue  7) magenta  8) white'
  read -r -p 'Choose color [2]: ' answer
  case "${answer:-2}" in
    1) COLOR=default;; 2) COLOR=green;; 3) COLOR=cyan;; 4) COLOR=yellow;;
    5) COLOR=red;; 6) COLOR=blue;; 7) COLOR=magenta;; 8) COLOR=white;;
    *) echo 'Invalid color selection.'; return 1;;
  esac
}

load_fonts() {
  local dir path name
  FONT_PATHS=() FONT_NAMES=()
  dir=$(figlet -I2 2>/dev/null || true)
  if [[ -z "$dir" || ! -d "$dir" ]]; then
    echo 'Could not locate the FIGlet font directory.' >&2
    return 1
  fi
  while IFS= read -r -d '' path; do
    name=${path##*/}
    FONT_NAMES+=("${name%.*}")
    FONT_PATHS+=("$path")
  done < <(find "$dir" -maxdepth 1 -type f \( -name '*.flf' -o -name '*.tlf' \) -print0 | sort -z)
  ((${#FONT_PATHS[@]} > 0)) || { echo 'No FIGlet font files found.' >&2; return 1; }
}

choose_font() {
  local title=$1 color=$2 page=0 per_page=12 count start stop i answer index rendered
  count=${#FONT_PATHS[@]}
  while :; do
    start=$((page * per_page)); stop=$((start + per_page))
    ((stop > count)) && stop=$count
    printf '\n=== Fonts: %d installed | page %d/%d ===\n' "$count" "$((page+1))" "$(((count+per_page-1)/per_page))"
    for ((i=start;i<stop;i++)); do printf '%3d) %s\n' "$((i+1))" "${FONT_NAMES[i]}"; done
    echo 'Number=select | p NUMBER=preview | n=next | b=back | q=cancel'
    read -r -p 'Choice: ' answer
    case "$answer" in
      n|N) if ((stop < count)); then page=$((page+1)); else echo 'Last page.'; fi;;
      b|B) if ((page > 0)); then page=$((page-1)); else echo 'First page.'; fi;;
      q|Q) return 1;;
      p\ *)
        index=${answer#p }
        if [[ "$index" =~ ^[0-9]+$ ]] && ((${#index} <= 6)) && ((10#$index>=1 && 10#$index<=count)); then
          index=$((10#$index-1))
          if rendered=$(figlet -f "${FONT_PATHS[index]}" -- "$title" 2>/dev/null); then
            printf '\nFont: %s\n' "${FONT_NAMES[index]}"
            preview "$color" "$rendered"
          else echo 'This font cannot render the selected text.'; fi
        else echo 'Invalid preview number.'; fi;;
      *)
        if [[ "$answer" =~ ^[0-9]+$ ]] && ((${#answer} <= 6)) && ((10#$answer>=1 && 10#$answer<=count)); then
          index=$((10#$answer-1))
          SELECTED_FONT=${FONT_PATHS[index]}
          SELECTED_FONT_NAME=${FONT_NAMES[index]}
          return 0
        fi
        echo 'Invalid selection.';;
    esac
  done
}

install_banner() {
  local title answer rendered tmp_banner tmp_color tmp_profile
  install_figlet || return 0
  read -r -p 'Banner text [TBOX]: ' title
  title=${title:-TBOX}
  [[ "$title" =~ ^[a-zA-Z0-9._\ -]{1,30}$ ]] || { echo 'Use 1-30 ASCII letters, digits, spaces, dots, underscores or hyphens.'; return 0; }
  choose_color || return 0
  load_fonts || return 0
  choose_font "$title" "$COLOR" || { echo 'Cancelled.'; return 0; }
  rendered=$(figlet -f "$SELECTED_FONT" -- "$title") || { echo 'Rendering failed.'; return 0; }
  printf '\nFinal preview (font: %s, color: %s):\n' "$SELECTED_FONT_NAME" "$COLOR"
  preview "$COLOR" "$rendered"
  read -r -p 'Install this banner? [y/N]: ' answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo 'Cancelled.'; return 0; }
  mkdir -p /etc/profile.d
  tmp_banner=$(mktemp /etc/.tbox-banner.XXXXXX)
  tmp_color=$(mktemp /etc/.tbox-color.XXXXXX)
  tmp_profile=$(mktemp /etc/profile.d/.tbox-profile.XXXXXX)
  printf '%s\n' "$rendered" > "$tmp_banner"
  printf '%s\n' "$COLOR" > "$tmp_color"
  cat > "$tmp_profile" <<'PROFILE'
# Managed by Universal Linux SSH Banner Manager.
# Only display in interactive SSH login shells with a terminal.
case "$-" in
  *i*)
    if [ -n "${SSH_TTY:-}" ] && [ -t 1 ] && [ -r /etc/tbox-ssh-banner.txt ]; then
      _tbox_color=default
      if [ -r /etc/tbox-ssh-banner.color ]; then
        IFS= read -r _tbox_color < /etc/tbox-ssh-banner.color || :
      fi
      case "$_tbox_color" in
        green) _tbox_ansi=32;; cyan) _tbox_ansi=36;; yellow) _tbox_ansi=33;;
        red) _tbox_ansi=31;; blue) _tbox_ansi=34;; magenta) _tbox_ansi=35;;
        white) _tbox_ansi=37;; *) _tbox_ansi=;;
      esac
      if [ -n "$_tbox_ansi" ] && [ "${TERM:-dumb}" != dumb ]; then
        printf '\033[%sm' "$_tbox_ansi"
        cat /etc/tbox-ssh-banner.txt
        printf '\033[0m'
      else
        cat /etc/tbox-ssh-banner.txt
      fi
      unset _tbox_color _tbox_ansi
    fi
    ;;
esac
PROFILE
  chmod 644 "$tmp_banner" "$tmp_color" "$tmp_profile"
  mv -f "$tmp_banner" "$BANNER_FILE"
  mv -f "$tmp_color" "$COLOR_FILE"
  mv -f "$tmp_profile" "$PROFILE_FILE"
  if [[ -f "$LEGACY_FILE" ]]; then
    echo "Notice: Old banner script exists: $LEGACY_FILE"
    echo 'Remove it manually if duplicate banners appear.'
  fi
  echo 'Installed. Open a NEW interactive SSH login session to verify.'
}

preview_installed() {
  if [[ ! -r "$BANNER_FILE" ]]; then echo 'No managed banner is installed.'; return; fi
  local color=default
  if [[ -r "$COLOR_FILE" ]]; then IFS= read -r color < "$COLOR_FILE" || :; fi
  printf '\nInstalled banner (color: %s):\n' "$color"
  preview "$color" "$(cat "$BANNER_FILE")"
}

remove_banner() {
  local answer
  if [[ ! -e "$PROFILE_FILE" && ! -e "$BANNER_FILE" && ! -e "$COLOR_FILE" ]]; then
    echo 'No managed banner found.'; return
  fi
  read -r -p 'Delete managed banner files? [y/N]: ' answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    rm -f -- "$PROFILE_FILE" "$BANNER_FILE" "$COLOR_FILE"
    echo 'Removed. Existing login sessions are unaffected.'
  else echo 'Cancelled.'; fi
}

while :; do
  printf '\n=== Universal Linux SSH Banner Manager v2.0.0 ===\n'
  echo '1) Install or update banner'
  echo '2) Preview installed banner'
  echo '3) Remove managed banner'
  echo '4) Exit'
  read -r -p 'Choose [1-4]: ' choice
  case "$choice" in
    1) install_banner;; 2) preview_installed;; 3) remove_banner;;
    4) exit 0;; *) echo 'Invalid selection.';;
  esac
done
