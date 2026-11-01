#!/usr/bin/env bash
# Interactive SSH login banner manager for Rocky Linux.
set -euo pipefail

BANNER_FILE='/etc/tbox-ssh-banner.txt'
PROFILE_FILE='/etc/profile.d/99-tbox-ssh-banner.sh'

if (( EUID != 0 )); then
  echo 'Run this script with sudo: sudo bash rocky-ssh-banner.sh' >&2
  exit 1
fi
if [[ ! -t 0 ]]; then
  echo 'An interactive terminal is required.' >&2
  exit 1
fi

install_figlet() {
  if command -v figlet >/dev/null 2>&1; then return; fi
  echo 'Installing figlet...'
  if ! dnf -y install figlet; then
    dnf -y install epel-release
    dnf -y install figlet
  fi
}

configure_banner() {
  install_figlet
  local title font color answer rendered tmpfile tmpprofile
  printf '\nBanner text [TBOX]: '
  IFS= read -r title
  title=${title:-TBOX}
  if [[ ! "$title" =~ ^[A-Za-z0-9._\ -]{1,24}$ ]]; then
    echo 'Use 1-24 characters: letters, numbers, spaces, dot, underscore or hyphen.' >&2
    return 1
  fi
  echo 'Font: 1) big  2) standard  3) slant  4) small'
  read -r -p 'Choose [1]: ' answer
  case "${answer:-1}" in
    1) font=big;; 2) font=standard;; 3) font=slant;; 4) font=small;;
    *) echo 'Invalid font choice.' >&2; return 1;;
  esac
  echo 'Color: 1) default  2) green  3) cyan  4) yellow'
  read -r -p 'Choose [1]: ' answer
  case "${answer:-1}" in
    1) color=default;; 2) color=green;; 3) color=cyan;; 4) color=yellow;;
    *) echo 'Invalid color choice.' >&2; return 1;;
  esac
  rendered=$(figlet -f "$font" -- "$title")
  printf '\nPreview:\n\n%s\n\n' "$rendered"
  read -r -p 'Install this banner for interactive SSH logins? [y/N]: ' answer
  case "$answer" in y|Y|yes|YES) ;; *) echo 'Cancelled.'; return;; esac

  tmpfile=$(mktemp /etc/.tbox-banner.XXXXXXXX)
  tmpprofile=$(mktemp /etc/profile.d/.tbox-profile.XXXXXXXX)
  printf '%s\n' "$rendered" > "$tmpfile"
  chmod 644 "$tmpfile"
  cat > "$tmpprofile" <<'PROFILE'
# Show a static login banner only for interactive SSH shell sessions.
case "$-" in
  *i*)
    if [ -n "${SSH_TTY:-}" ] && [ -r /etc/tbox-ssh-banner.txt ]; then
      if [ -t 1 ]; then
        case "${TBOX_BANNER_COLOR:-default}" in
          green)  printf '\033[32m';;
          cyan)   printf '\033[36m';;
          yellow) printf '\033[33m';;
        esac
        cat /etc/tbox-ssh-banner.txt
        printf '\033[0m'
      fi
    fi
    ;;
esac
PROFILE
  # Store a fixed administrator-selected color without shell interpolation of user input.
  sed -i "1iTBOX_BANNER_COLOR='$color'" "$tmpprofile"
  chmod 644 "$tmpprofile"
  mv -f "$tmpfile" "$BANNER_FILE"
  mv -f "$tmpprofile" "$PROFILE_FILE"
  restorecon "$BANNER_FILE" "$PROFILE_FILE" 2>/dev/null || true
  echo 'Installed. Open a NEW interactive SSH session to verify.'
  echo 'Applies to login shells that source /etc/profile (including Bash).'
}

remove_banner() {
  local answer
  read -r -p 'Remove the SSH banner? [y/N]: ' answer
  case "$answer" in
    y|Y|yes|YES)
      rm -f "$BANNER_FILE" "$PROFILE_FILE"
      echo 'Removed. New SSH logins will no longer display the banner.';;
    *) echo 'Cancelled.';;
  esac
}

while :; do
  printf '\n=== Rocky Linux SSH Banner Manager ===\n'
  echo '1) Install or update banner'
  echo '2) Preview installed banner'
  echo '3) Remove banner'
  echo '4) Exit'
  read -r -p 'Choose [1-4]: ' choice
  case "$choice" in
    1) configure_banner;;
    2) if [[ -r "$BANNER_FILE" ]]; then cat "$BANNER_FILE"; else echo 'No banner installed.'; fi;;
    3) remove_banner;;
    4) exit 0;;
    *) echo 'Invalid choice.';;
  esac
done
