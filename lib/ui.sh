#!/usr/bin/env bash
set -euo pipefail

ui_has_whiptail() {
  command -v whiptail >/dev/null 2>&1
}

ui_backtitle() {
  if [[ -n "${EASYUBUNTU_VERSION:-}" ]]; then
    printf "EasyUbuntu v%s\n" "$EASYUBUNTU_VERSION"
  else
    printf "EasyUbuntu\n"
  fi
}

trim() {
  # shellcheck disable=SC2001
  sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//' <<<"${1:-}"
}

ui_title() {
  printf "%s\n" "${1:-EasyUbuntu}"
}

ui_msg() {
  local title="${1:-Message}"
  local msg="${2:-}"
  if ui_has_whiptail; then
    whiptail --backtitle "$(ui_backtitle)" --title "$(ui_title "$title")" --msgbox "$msg" 12 78
  else
    printf "\n== %s ==\n%s\n\n" "$title" "$msg"
  fi
}

ui_error() {
  ui_msg "Error" "$*"
}

ui_yesno() {
  local title="${1:-Confirm}"
  local msg="${2:-Are you sure?}"
  if ui_has_whiptail; then
    whiptail --backtitle "$(ui_backtitle)" --title "$(ui_title "$title")" --yesno "$msg" 12 78
    return $?
  fi

  printf "%s [y/N]: " "$msg" >&2
  local yn
  read -r yn || return 1
  [[ "${yn,,}" == "y" || "${yn,,}" == "yes" ]]
}

ui_input() {
  local title="${1:-Input}"
  local prompt="${2:-}"
  local default="${3:-}"

  if ui_has_whiptail; then
    whiptail --backtitle "$(ui_backtitle)" --title "$(ui_title "$title")" --inputbox "$prompt" 12 78 "$default" 3>&1 1>&2 2>&3
    return $?
  fi

  printf "%s " "$prompt" >&2
  if [[ -n "$default" ]]; then
    printf "[%s] " "$default" >&2
  fi

  local out
  read -r out || return 1
  if [[ -z "$out" && -n "$default" ]]; then
    printf "%s\n" "$default"
  else
    printf "%s\n" "$out"
  fi
}

ui_textbox() {
  local title="${1:-View}"
  local text="${2:-}"
  if ui_has_whiptail; then
    local tmp
    tmp="$(mktemp)"
    printf "%s\n" "$text" >"$tmp"
    whiptail --backtitle "$(ui_backtitle)" --title "$(ui_title "$title")" --textbox "$tmp" 24 90
    rm -f "$tmp"
  else
    printf "\n== %s ==\n%s\n\n" "$title" "$text"
    printf "Press Enter to continue..." >&2
    local _
    read -r _ || true
  fi
}

ui_menu() {
  local title="${1:-Menu}"
  local prompt="${2:-Select}"
  shift 2

  if ui_has_whiptail; then
    whiptail --backtitle "$(ui_backtitle)" --title "$(ui_title "$title")" --menu "$prompt" 18 78 10 "$@" 3>&1 1>&2 2>&3
    return $?
  fi

  # Fallback: print numbered list
  local -a keys=()
  local -a labels=()
  while (( "$#" )); do
    keys+=("$1"); labels+=("$2"); shift 2
  done

  printf "\n== %s ==\n%s\n\n" "$title" "$prompt" >&2
  local i
  for i in "${!keys[@]}"; do
    printf "%d) %s\n" "$((i + 1))" "${labels[$i]}" >&2
  done
  printf "\nChoose [1-%d] (empty cancels): " "${#keys[@]}" >&2

  local choice
  read -r choice || return 1
  choice="$(trim "$choice")"
  [[ -z "$choice" ]] && return 1
  [[ "$choice" =~ ^[0-9]+$ ]] || return 1
  (( choice >= 1 && choice <= ${#keys[@]} )) || return 1
  printf "%s\n" "${keys[$((choice - 1))]}"
}

