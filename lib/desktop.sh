#!/usr/bin/env bash
set -euo pipefail

desktop_user_dir() {
  printf "%s\n" "${XDG_DATA_HOME:-$HOME/.local/share}/applications"
}

desktop_marker_key() {
  printf "%s\n" "X-EasyUbuntu-Managed"
}

desktop_ensure_dirs() {
  mkdir -p "$(desktop_user_dir)"
}

desktop_find_image_candidates() {
  local container_dir="$1"
  [[ -d "$container_dir" ]] || return 0

  local -a exact_icons=()
  local -a contains_icons=()
  local -a others=()

  # Recursively enumerate common image formats.
  local f base stem lower_base lower_stem
  while IFS= read -r -d '' f; do
    base="$(basename -- "$f")"
    stem="${base%.*}"
    lower_base="${base,,}"
    lower_stem="${stem,,}"

    if [[ "$lower_stem" == "icon" ]]; then
      exact_icons+=("$f")
    elif [[ "$lower_base" == *"icon"* ]]; then
      contains_icons+=("$f")
    else
      others+=("$f")
    fi
  done < <(
    find "$container_dir" -type f \
      \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.svg" -o -iname "*.webp" -o -iname "*.gif" -o -iname "*.ico" \) \
      -print0 2>/dev/null
  )

  local p
  for p in "${exact_icons[@]}"; do printf "%s\n" "$p"; done
  for p in "${contains_icons[@]}"; do printf "%s\n" "$p"; done
  for p in "${others[@]}"; do printf "%s\n" "$p"; done
}

desktop_render_image_preview() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    printf "File not found: %s\n" "$path"
    return 0
  fi

  desktop__sanitize_preview() {
    # Strip ANSI/control sequences so output is whiptail-safe.
    # Remove CSI escapes + control chars; keep UTF-8 glyphs.
    sed -E $'s/\x1B\\[[0-9;?]*[ -/]*[@-~]//g' | tr -d '\000-\010\013\014\016-\037\177'
  }

  if command -v chafa >/dev/null 2>&1; then
    # Best-effort: render as monochrome unicode blocks (whiptail-safe after sanitize).
    local preview=""
    if command -v timeout >/dev/null 2>&1; then
      preview="$(timeout 2s chafa -f symbols -c none --symbols block+border+solid --optimize 0 --polite on --relative off -s 60x20 "$path" 2>/dev/null | desktop__sanitize_preview || true)"
    else
      preview="$(chafa -f symbols -c none --symbols block+border+solid --optimize 0 --polite on --relative off -s 60x20 "$path" 2>/dev/null | desktop__sanitize_preview || true)"
    fi
    if [[ -n "$preview" ]]; then
      printf "%s\n" "$preview"
      return 0
    fi
  fi

  if command -v viu >/dev/null 2>&1; then
    # Viu usually outputs ANSI; sanitize for whiptail.
    local preview=""
    if command -v timeout >/dev/null 2>&1; then
      preview="$(timeout 2s viu -w 60 "$path" 2>/dev/null | desktop__sanitize_preview || true)"
    else
      preview="$(viu -w 60 "$path" 2>/dev/null | desktop__sanitize_preview || true)"
    fi
    if [[ -n "$preview" ]]; then
      printf "%s\n" "$preview"
      return 0
    fi
  fi

  if command -v file >/dev/null 2>&1; then
    printf "%s\n" "$path"
    file -b -- "$path" 2>/dev/null || true
    printf "\nTip: install chafa for a safe preview inside whiptail:\n"
    printf "  sudo apt-get update && sudo apt-get install -y chafa\n"
  else
    printf "%s\n" "$path"
    printf "(no terminal image preview tool found)\n"
  fi
}

desktop__tty_preview_and_confirm_icon() {
  # Show a high-fidelity preview in the terminal (not inside whiptail),
  # then ask for a single-key confirmation.
  #
  # Returns:
  #  0 => use
  #  1 => skip (no icon)
  #  2 => back
  local icon_path="$1"
  local tty="/dev/tty"

  [[ -r "$tty" && -w "$tty" ]] || return 1

  # Clear a bit of space; avoid full clear to reduce flicker.
  printf "\nSuggested icon:\n%s\n\n" "$icon_path" >"$tty"

  if command -v chafa >/dev/null 2>&1; then
    # Use chafa's default color selection for best fidelity in the user's terminal.
    # Avoid cursor-relative output so it doesn't behave strangely.
    if command -v timeout >/dev/null 2>&1; then
      timeout 2s chafa -f symbols --polite on --relative off --optimize 0 -s 60x20 "$icon_path" >"$tty" 2>/dev/null || true
    else
      chafa -f symbols --polite on --relative off --optimize 0 -s 60x20 "$icon_path" >"$tty" 2>/dev/null || true
    fi
  else
    # Fallback: just show file info.
    if command -v file >/dev/null 2>&1; then
      file -b -- "$icon_path" >"$tty" 2>/dev/null || true
    fi
  fi

  printf "\n[u] Use   [s] Skip   [b] Back: " >"$tty"
  local key=""
  IFS= read -r -n1 key <"$tty" || return 2
  printf "\n" >"$tty"

  key="${key,,}"
  case "$key" in
    u|y) return 0 ;;
    $'\e') return 2 ;; # Esc
    b) return 2 ;;
    s|n|"") return 1 ;;
    *) return 1 ;;
  esac
}

desktop__find_first() {
  # Sets UI_RESULT to the first matching file (or empty) and returns 0.
  # Arguments: <container_dir> <find-args...>
  local container_dir="$1"
  shift 1

  UI_RESULT=""

  local found=""
  if command -v timeout >/dev/null 2>&1; then
    while IFS= read -r -d '' found; do
      break
    done < <(timeout 6s find "$container_dir" "$@" -print0 -quit 2>/dev/null || true)
  else
    while IFS= read -r -d '' found; do
      break
    done < <(find "$container_dir" "$@" -print0 -quit 2>/dev/null || true)
  fi

  UI_RESULT="$found"
  return 0
}

desktop_find_best_icon_candidate() {
  # Sets UI_RESULT to best match, or empty if none.
  local container_dir="$1"
  UI_RESULT=""
  [[ -d "$container_dir" ]] || return 0

  # 1) Exact icon.* with common extensions
  desktop__find_first "$container_dir" -type f \( \
    -iname "icon.png" -o -iname "icon.jpg" -o -iname "icon.jpeg" -o -iname "icon.svg" -o -iname "icon.webp" -o -iname "icon.gif" -o -iname "icon.ico" \
  \)
  [[ -n "${UI_RESULT:-}" ]] && return 0

  # 2) Anything containing 'icon' in the name with common extensions
  desktop__find_first "$container_dir" -type f \( \
    -iname "*icon*.png" -o -iname "*icon*.jpg" -o -iname "*icon*.jpeg" -o -iname "*icon*.svg" -o -iname "*icon*.webp" -o -iname "*icon*.gif" -o -iname "*icon*.ico" \
  \)
  [[ -n "${UI_RESULT:-}" ]] && return 0

  # 3) Any image file
  desktop__find_first "$container_dir" -type f \( \
    -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.svg" -o -iname "*.webp" -o -iname "*.gif" -o -iname "*.ico" \
  \)
  return 0
}

desktop_choose_icon_from_container() {
  local container_dir="$1"
  UI_CANCELLED=0
  UI_RESULT=""
  [[ -d "$container_dir" ]] || return 0

  # Best-effort: show something while searching (non-blocking).
  if ui_has_whiptail; then
    # Don't let an infobox failure trigger set -e exits.
    ui__with_errexit_disabled whiptail --backtitle "$(ui_backtitle)" --title "EasyUbuntu" --infobox "Searching for an icon in:\n\n$container_dir" 10 70 || true
  fi

  desktop_find_best_icon_candidate "$container_dir"
  local candidate="${UI_RESULT:-}"
  if [[ -z "$candidate" ]]; then
    UI_RESULT=""
    return 0
  fi

  # If possible, show a real preview directly in the terminal (not whiptail),
  # because whiptail cannot render ANSI graphics reliably.
  if [[ -r /dev/tty && -w /dev/tty ]]; then
    local rc
    # IMPORTANT: This function intentionally returns non-zero for Skip/Back.
    # With `set -e` enabled, calling it as a bare command would exit the app.
    if desktop__tty_preview_and_confirm_icon "$candidate"; then
      rc=0
    else
      rc=$?
    fi
    case "$rc" in
      0)
        UI_RESULT="$candidate"
        return 0
        ;;
      1) UI_RESULT=""; return 0 ;;          # skip
      2) UI_CANCELLED=1; UI_RESULT=""; return 0 ;; # back
      *) UI_RESULT=""; return 0 ;;
    esac
  fi

  # Fallback: show a simple prompt in whiptail.
  if ui_yesno "Icon" "Suggested icon:\n$candidate\n\nUse it?" "Use" "Skip"; then
    UI_RESULT="$candidate"
  else
    # No = Skip, Esc = Back (UI_CANCELLED=1)
    if [[ "${UI_CANCELLED:-0}" -eq 1 ]]; then
      UI_RESULT=""
      return 0
    fi
    UI_RESULT=""
  fi
  return 0
}

slugify() {
  local s="${1:-}"
  s="${s,,}"
  # replace spaces and slashes with dashes, drop unsafe chars
  s="${s//[[:space:]]/-}"
  s="${s//\//-}"
  s="$(printf "%s" "$s" | tr -cd 'a-z0-9._-')"
  # collapse repeated dashes
  s="$(printf "%s" "$s" | sed -E 's/-{2,}/-/g; s/^-+//; s/-+$//')"
  printf "%s\n" "${s:-app}"
}

desktop_suggest_filename() {
  local name="${1:-app}"
  printf "easyubuntu-%s.desktop\n" "$(slugify "$name")"
}

desktop_is_desktop_file() {
  local path="$1"
  grep -q '^\[Desktop Entry\]' "$path"
}

desktop_unique_path_for_filename() {
  local filename="$1"
  local dir base ext n candidate
  dir="$(desktop_user_dir)"

  if [[ "$filename" != *.desktop ]]; then
    filename="$filename.desktop"
  fi

  base="${filename%.desktop}"
  ext="desktop"
  candidate="$dir/$base.$ext"

  if [[ ! -e "$candidate" ]]; then
    printf "%s\n" "$candidate"
    return 0
  fi

  n=2
  while true; do
    candidate="$dir/$base-$n.$ext"
    if [[ ! -e "$candidate" ]]; then
      printf "%s\n" "$candidate"
      return 0
    fi
    n=$((n + 1))
  done
}

desktop_list_files() {
  local dir
  dir="$(desktop_user_dir)"
  [[ -d "$dir" ]] || return 0
  shopt -s nullglob
  local f
  for f in "$dir"/*.desktop; do
    printf "%s\n" "$f"
  done
}

desktop_entry_name() {
  local path="$1"
  local name
  name="$(grep -m1 '^Name=' "$path" | sed 's/^Name=//')"
  if [[ -z "${name:-}" ]]; then
    name="$(basename -- "$path")"
  fi
  printf "%s\n" "$name"
}

desktop_list_pretty() {
  local out=""
  local any=0
  local f name
  while IFS= read -r f; do
    any=1
    name="$(desktop_entry_name "$f")"
    out+="$(basename -- "$f")"$'\t'"$name"$'\n'
  done < <(desktop_list_files)

  if [[ "$any" -eq 0 ]]; then
    printf "%s\n" "No .desktop files found in $(desktop_user_dir)"
    return 0
  fi

  if command -v column >/dev/null 2>&1; then
    printf "%s\n" "$out" | column -t -s $'\t'
  else
    printf "%s\n" "$out"
  fi
}

desktop_write_entry_file() {
  local dest="$1"
  local name="$2"
  local exec="$3"
  local icon="$4"
  local comment="$5"
  local categories="$6"
  local terminal="$7"

  {
    printf "[Desktop Entry]\n"
    printf "Type=Application\n"
    printf "Version=1.0\n"
    printf "Name=%s\n" "$name"
    printf "Exec=%s\n" "$exec"
    if [[ -n "${icon:-}" ]]; then printf "Icon=%s\n" "$icon"; fi
    if [[ -n "${comment:-}" ]]; then printf "Comment=%s\n" "$comment"; fi
    if [[ -n "${categories:-}" ]]; then printf "Categories=%s\n" "$categories"; fi
    printf "Terminal=%s\n" "${terminal:-false}"
    printf "%s=%s\n" "$(desktop_marker_key)" "true"
  } >"$dest"
}

desktop_create_entry() {
  local filename="$1"
  local name="$2"
  local exec="$3"
  local icon="$4"
  local comment="$5"
  local categories="$6"
  local terminal="$7"

  desktop_ensure_dirs

  local dest
  dest="$(desktop_user_dir)/$filename"

  desktop_write_entry_file "$dest" "$name" "$exec" "$icon" "$comment" "$categories" "$terminal"
}

desktop_import_entry() {
  local src="$1"
  local filename="$2"

  desktop_ensure_dirs

  local dest
  dest="$(desktop_user_dir)/$filename"

  cp -a -- "$src" "$dest"

  # Ensure it has our marker so uninstall cleanup can find it if user opts in.
  if ! grep -q "^$(desktop_marker_key)=" "$dest"; then
    printf "%s=%s\n" "$(desktop_marker_key)" "true" >>"$dest"
  fi
}

desktop_remove_entry() {
  local path="$1"
  [[ -e "$path" ]] || return 1
  desktop_ensure_dirs
  rm -f -- "$path"
}

desktop_pick_entry() {
  UI_CANCELLED=0
  UI_RESULT=""

  local -a files=()
  local -a args=()
  local f name i
  i=1
  while IFS= read -r f; do
    files+=("$f")
    name="$(desktop_entry_name "$f")"
    args+=("$i" "$name ($(basename -- "$f"))")
    i=$((i + 1))
  done < <(desktop_list_files)

  if [[ "${#args[@]}" -eq 0 ]]; then
    ui_msg "Remove .desktop" "No entries found in $(desktop_user_dir)."
    UI_CANCELLED=1
    UI_RESULT=""
    return 0
  fi

  local choice
  ui_menu "Remove .desktop" "Select an entry to remove" "Select" "Back" "${args[@]}"
  if [[ "${UI_CANCELLED:-0}" -eq 1 ]]; then
    UI_RESULT=""
    return 0
  fi
  choice="$(trim "${UI_RESULT:-}")"
  [[ "$choice" =~ ^[0-9]+$ ]] || { UI_CANCELLED=1; UI_RESULT=""; return 0; }
  (( choice >= 1 && choice <= ${#files[@]} )) || { UI_CANCELLED=1; UI_RESULT=""; return 0; }
  UI_RESULT="${files[$((choice - 1))]}"
  return 0
}

