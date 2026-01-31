#!/usr/bin/env bash
set -euo pipefail

say() { printf "%s\n" "$*"; }
err() { printf "uninstall.sh: %s\n" "$*" >&2; }

has_whiptail() { command -v whiptail >/dev/null 2>&1; }

confirm() {
  local title="$1"
  local msg="$2"
  if has_whiptail; then
    whiptail --title "$title" --yesno "$msg" 12 78
    return $?
  fi
  printf "%s [y/N]: " "$msg" >&2
  local yn
  read -r yn || return 1
  [[ "${yn,,}" == "y" || "${yn,,}" == "yes" ]]
}

paths() {
  local bin_dir="${XDG_BIN_HOME:-$HOME/.local/bin}"
  local data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/easyubuntu"
  local desktop_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/easyubuntu"
  printf "%s\n" "$bin_dir" "$data_dir" "$config_dir" "$desktop_dir"
}

cleanup_managed_desktop_entries() {
  local desktop_dir="$1"
  [[ -d "$desktop_dir" ]] || return 0

  local -a managed=()
  shopt -s nullglob
  local f
  for f in "$desktop_dir"/*.desktop; do
    if grep -q '^X-EasyUbuntu-Managed=true' "$f"; then
      managed+=("$f")
    fi
  done

  if [[ "${#managed[@]}" -eq 0 ]]; then
    say "No EasyUbuntu-managed .desktop entries found."
    return 0
  fi

  say "Found ${#managed[@]} EasyUbuntu-managed .desktop entries."
  if ! confirm "EasyUbuntu" "Remove EasyUbuntu-managed .desktop entries from:\n\n$desktop_dir\n\nThis cannot be undone."; then
    return 0
  fi

  for f in "${managed[@]}"; do
    rm -f -- "$f"
  done
  say "Removed EasyUbuntu-managed .desktop entries."
}

main() {
  local bin_dir data_dir config_dir desktop_dir
  local -a p=()
  mapfile -t p < <(paths)
  bin_dir="${p[0]}"
  data_dir="${p[1]}"
  config_dir="${p[2]}"
  desktop_dir="${p[3]}"

  say "Uninstalling EasyUbuntu (user install)."

  if [[ -f "$bin_dir/easyubuntu" ]]; then
    rm -f -- "$bin_dir/easyubuntu"
    say "Removed: $bin_dir/easyubuntu"
  else
    say "Not found: $bin_dir/easyubuntu"
  fi

  if [[ -d "$data_dir" ]]; then
    rm -rf -- "$data_dir"
    say "Removed: $data_dir"
  else
    say "Not found: $data_dir"
  fi

  if [[ -d "$config_dir" ]]; then
    if confirm "EasyUbuntu" "Remove config directory?\n\n$config_dir"; then
      rm -rf -- "$config_dir"
      say "Removed: $config_dir"
    else
      say "Kept: $config_dir"
    fi
  fi

  cleanup_managed_desktop_entries "$desktop_dir"

  say "Done."
}

main "$@"

