#!/usr/bin/env bash
set -euo pipefail

ui_has_whiptail() {
  command -v whiptail >/dev/null 2>&1
}

UI_CANCELLED=0
UI_RESULT=""

ui__with_errexit_disabled() {
  # Runs a command with errexit disabled, preserving previous state.
  # Usage: ui__with_errexit_disabled cmd arg...
  local was_errexit=0
  case "$-" in
    *e*) was_errexit=1 ;;
  esac

  set +e
  "$@"
  local rc=$?
  if [[ "$was_errexit" -eq 1 ]]; then
    set -e
  fi
  return "$rc"
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
    UI_CANCELLED=0
    UI_RESULT=""
    local rc was_errexit=0
    case "$-" in *e*) was_errexit=1 ;; esac
    set +e
    whiptail --backtitle "$(ui_backtitle)" --title "$(ui_title "$title")" --ok-button "OK" --msgbox "$msg" 12 78
    rc=$?
    if [[ "$was_errexit" -eq 1 ]]; then set -e; fi
    # msgbox has only OK; treat Esc as cancelled but never propagate failure.
    if [[ "$rc" -ne 0 ]]; then UI_CANCELLED=1; fi
    return 0
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
  local yes_label="${3:-Yes}"
  local no_label="${4:-No}"
  if ui_has_whiptail; then
    UI_CANCELLED=0
    UI_RESULT=""
    local rc was_errexit=0
    case "$-" in *e*) was_errexit=1 ;; esac
    set +e
    whiptail --backtitle "$(ui_backtitle)" --title "$(ui_title "$title")" --yes-button "$yes_label" --no-button "$no_label" --yesno "$msg" 20 90
    rc=$?
    if [[ "$was_errexit" -eq 1 ]]; then set -e; fi
    case "$rc" in
      0) return 0 ;;      # Yes
      1) return 1 ;;      # No
      255) UI_CANCELLED=1; return 1 ;; # Esc
      *) UI_CANCELLED=1; return 1 ;;
    esac
  fi

  printf "%s [y/N]: " "$msg" >&2
  local yn
  UI_CANCELLED=0
  UI_RESULT=""
  read -r yn || { UI_CANCELLED=1; return 1; }
  [[ "${yn,,}" == "y" || "${yn,,}" == "yes" ]]
}

ui_input() {
  local title="${1:-Input}"
  local prompt="${2:-}"
  local default="${3:-}"
  local ok_label="${4:-OK}"
  local cancel_label="${5:-Cancel}"

  if ui_has_whiptail; then
    UI_CANCELLED=0
    UI_RESULT=""
    local out rc was_errexit=0
    case "$-" in *e*) was_errexit=1 ;; esac
    set +e
    out="$(whiptail --backtitle "$(ui_backtitle)" --title "$(ui_title "$title")" --ok-button "$ok_label" --cancel-button "$cancel_label" --inputbox "$prompt" 12 78 "$default" 3>&1 1>&2 2>&3)"
    rc=$?
    if [[ "$was_errexit" -eq 1 ]]; then set -e; fi
    if [[ "$rc" -ne 0 ]]; then
      UI_CANCELLED=1
      UI_RESULT=""
      return 0
    fi
    UI_RESULT="$out"
    return 0
  fi

  printf "%s " "$prompt" >&2
  if [[ -n "$default" ]]; then
    printf "[%s] " "$default" >&2
  fi

  local out
  UI_CANCELLED=0
  UI_RESULT=""
  read -r out || { UI_CANCELLED=1; return 0; }
  if [[ -z "$out" && -n "$default" ]]; then
    UI_RESULT="$default"
  else
    UI_RESULT="$out"
  fi
}

ui_textbox() {
  local title="${1:-View}"
  local text="${2:-}"
  local ok_label="${3:-OK}"
  if ui_has_whiptail; then
    UI_CANCELLED=0
    UI_RESULT=""
    local tmp
    tmp="$(mktemp)"
    printf "%s\n" "$text" >"$tmp"
    local rc was_errexit=0
    case "$-" in *e*) was_errexit=1 ;; esac
    set +e
    whiptail --backtitle "$(ui_backtitle)" --title "$(ui_title "$title")" --ok-button "$ok_label" --textbox "$tmp" 24 90
    rc=$?
    if [[ "$was_errexit" -eq 1 ]]; then set -e; fi
    rm -f "$tmp"
    if [[ "$rc" -ne 0 ]]; then UI_CANCELLED=1; fi
    return 0
  else
    printf "\n== %s ==\n%s\n\n" "$title" "$text"
    printf "Press Enter to continue..." >&2
    local _
    UI_CANCELLED=0
    UI_RESULT=""
    read -r _ || { UI_CANCELLED=1; return 0; }
  fi
}

ui_menu() {
  local title="${1:-Menu}"
  local prompt="${2:-Select}"
  local ok_label="${3:-OK}"
  local cancel_label="${4:-Cancel}"
  shift 4

  if ui_has_whiptail; then
    UI_CANCELLED=0
    UI_RESULT=""
    local out rc was_errexit=0
    case "$-" in *e*) was_errexit=1 ;; esac
    set +e
    out="$(whiptail --backtitle "$(ui_backtitle)" --title "$(ui_title "$title")" --ok-button "$ok_label" --cancel-button "$cancel_label" --menu "$prompt" 18 78 10 "$@" 3>&1 1>&2 2>&3)"
    rc=$?
    if [[ "$was_errexit" -eq 1 ]]; then set -e; fi
    if [[ "$rc" -ne 0 ]]; then
      UI_CANCELLED=1
      UI_RESULT=""
      return 0
    fi
    UI_RESULT="$out"
    return 0
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
  printf "\nChoose [1-%d] (empty = %s): " "${#keys[@]}" "$cancel_label" >&2

  local choice
  UI_CANCELLED=0
  UI_RESULT=""
  read -r choice || { UI_CANCELLED=1; return 0; }
  choice="$(trim "$choice")"
  [[ -z "$choice" ]] && { UI_CANCELLED=1; return 0; }
  [[ "$choice" =~ ^[0-9]+$ ]] || { UI_CANCELLED=1; return 0; }
  (( choice >= 1 && choice <= ${#keys[@]} )) || { UI_CANCELLED=1; return 0; }
  UI_RESULT="${keys[$((choice - 1))]}"
}

