#!/usr/bin/env bash
set -euo pipefail

apparmor_profiles_dir() {
  printf "%s\n" "/etc/apparmor.d"
}

apparmor_managed_marker() {
  printf "%s\n" "# Managed-By: easyubuntu"
}

apparmor_profile_path() {
  local name="$1"
  printf "%s/%s\n" "$(apparmor_profiles_dir)" "$name"
}

apparmor_require_tools() {
  if ! command -v apparmor_parser >/dev/null 2>&1; then
    ui_error "Missing command: apparmor_parser\n\nInstall AppArmor tools first (e.g. apparmor-utils)."
    return 1
  fi
  if ! command -v systemctl >/dev/null 2>&1; then
    ui_error "Missing command: systemctl"
    return 1
  fi
  return 0
}

apparmor_sudo_or_error() {
  # Prompt for sudo only when needed.
  if sudo -n true >/dev/null 2>&1; then
    return 0
  fi

  ui_msg "Sudo required" "EasyUbuntu needs sudo to write into:\n\n$(apparmor_profiles_dir)\n\nYou may be prompted for your password."

  if ! sudo -v; then
    ui_error "Sudo authentication failed."
    return 1
  fi
  return 0
}

apparmor_slugify_name() {
  # Prefer reusing desktop.sh slugify if available.
  if command -v slugify >/dev/null 2>&1; then
    slugify "$1"
  else
    local s="${1:-}"
    s="${s,,}"
    s="${s//[[:space:]]/-}"
    s="${s//\//-}"
    s="$(printf "%s" "$s" | tr -cd 'a-z0-9._-')"
    s="$(printf "%s" "$s" | sed -E 's/-{2,}/-/g; s/^-+//; s/-+$//')"
    printf "%s\n" "${s:-profile}"
  fi
}

apparmor_strip_exec_placeholders() {
  # Strip common Desktop Entry Exec placeholders.
  # https://specifications.freedesktop.org/desktop-entry-spec/latest/ar01s07.html
  local s="${1:-}"
  s="${s//%U/}"
  s="${s//%u/}"
  s="${s//%F/}"
  s="${s//%f/}"
  s="${s//%i/}"
  s="${s//%c/}"
  s="${s//%k/}"
  printf "%s\n" "$s"
}

apparmor_generate_profile_text() {
  local exec_path="$1"
  local perms_block="$2"
  local source_desktop="$3"
  local source_exec="$4"

  cat <<EOF
abi <abi/4.0>,
include <tunables/global>

$(apparmor_managed_marker)
# Source-Desktop: $source_desktop
# Source-Exec: $source_exec

# adjust path if you move the app
$exec_path flags=(unconfined) {
$perms_block
}
EOF
}

apparmor_permissions_default() {
  printf "  userns,\n"
}

apparmor_permissions_join() {
  # Join permission lines, indenting if needed.
  # Input: lines separated by \n without trailing \n.
  local s="${1:-}"
  local out=""
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue
    if [[ "$line" != "  "* ]]; then
      line="  $line"
    fi
    out+="$line"$'\n'
  done <<<"$s"

  # Ensure it ends with newline.
  printf "%s" "$out"
}

apparmor_write_profile() {
  local profile_name="$1"
  local content="$2"

  apparmor_sudo_or_error || return 1

  local tmp
  tmp="$(mktemp)"
  printf "%s\n" "$content" >"$tmp"

  local dest
  dest="$(apparmor_profile_path "$profile_name")"

  # install is safer than redirection with sudo.
  if ! sudo install -m 0644 "$tmp" "$dest"; then
    rm -f "$tmp"
    ui_error "Failed to write profile:\n\n$dest"
    return 1
  fi

  rm -f "$tmp"
  return 0
}

apparmor_load_and_reload() {
  local profile_name="$1"
  local path
  path="$(apparmor_profile_path "$profile_name")"

  apparmor_require_tools || return 1
  apparmor_sudo_or_error || return 1

  local out=""
  local rc=0
  out+="Running: sudo apparmor_parser -r $path"$'\n'
  if ! sudo apparmor_parser -r "$path" 2>&1 | sed -n '1,200p' >>/dev/null; then
    rc=1
  fi

  out+="Running: sudo systemctl reload apparmor"$'\n'
  if ! sudo systemctl reload apparmor 2>&1 | sed -n '1,200p' >>/dev/null; then
    rc=1
  fi

  # We don’t capture full outputs into out to avoid mixing sudo prompts.
  if [[ "$rc" -eq 0 ]]; then
    ui_msg "AppArmor" "Loaded and reloaded successfully:\n\n$path"
  else
    ui_error "AppArmor command failed.\n\nTried:\n- sudo apparmor_parser -r $path\n- sudo systemctl reload apparmor"
  fi
  return "$rc"
}

apparmor_list_managed_profiles() {
  # Outputs full paths, one per line, that are marked as managed by EasyUbuntu.
  local dir
  dir="$(apparmor_profiles_dir)"
  [[ -d "$dir" ]] || return 0

  local f
  for f in "$dir"/*; do
    [[ -f "$f" ]] || continue
    # read first ~40 lines only (fast).
    if sed -n '1,40p' "$f" 2>/dev/null | grep -qF "$(apparmor_managed_marker)"; then
      printf "%s\n" "$f"
    fi
  done
}

apparmor_pick_managed_profile() {
  UI_CANCELLED=0
  UI_RESULT=""

  local -a files=()
  local -a args=()
  local i=1
  local f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    files+=("$f")
    args+=("$i" "$(basename -- "$f")")
    i=$((i + 1))
  done < <(apparmor_list_managed_profiles)

  if [[ "${#args[@]}" -eq 0 ]]; then
    ui_msg "AppArmor" "No EasyUbuntu-managed AppArmor profiles found in:\n\n$(apparmor_profiles_dir)"
    UI_CANCELLED=1
    return 0
  fi

  ui_menu "Remove AppArmor profile" "Select a profile to remove" "Select" "Back" "${args[@]}"
  if [[ "${UI_CANCELLED:-0}" -eq 1 ]]; then
    UI_RESULT=""
    return 0
  fi

  local choice
  choice="$(trim "${UI_RESULT:-}")"
  [[ "$choice" =~ ^[0-9]+$ ]] || { UI_CANCELLED=1; UI_RESULT=""; return 0; }
  (( choice >= 1 && choice <= ${#files[@]} )) || { UI_CANCELLED=1; UI_RESULT=""; return 0; }
  UI_RESULT="${files[$((choice - 1))]}"
  return 0
}

apparmor_remove_profile() {
  local profile_path="$1"
  local profile_name
  profile_name="$(basename -- "$profile_path")"

  apparmor_sudo_or_error || return 1

  if ! sudo rm -f -- "$profile_path"; then
    ui_error "Failed to remove:\n\n$profile_path"
    return 1
  fi

  # Reload AppArmor so it drops the profile.
  if ! sudo systemctl reload apparmor; then
    ui_error "Removed file, but failed to reload AppArmor."
    return 1
  fi

  ui_msg "Removed" "Removed AppArmor profile:\n\n$profile_name"
  return 0
}

