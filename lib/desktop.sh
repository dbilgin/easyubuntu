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

  if command -v chafa >/dev/null 2>&1; then
    # Best-effort: may include ANSI escapes depending on terminal.
    if chafa -s 60x20 "$path" 2>/dev/null; then
      return 0
    fi
  fi

  if command -v viu >/dev/null 2>&1; then
    if viu -w 60 "$path" 2>/dev/null; then
      return 0
    fi
  fi

  if command -v file >/dev/null 2>&1; then
    printf "%s\n" "$path"
    file -b -- "$path" 2>/dev/null || true
  else
    printf "%s\n" "$path"
    printf "(no terminal image preview tool found)\n"
  fi
}

desktop_choose_icon_from_container() {
  local container_dir="$1"
  [[ -d "$container_dir" ]] || { printf "%s\n" ""; return 0; }

  local any=0
  local candidate preview
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    any=1
    preview="$(desktop_render_image_preview "$candidate")"
    ui_textbox "Icon preview" "$preview"
    if ui_yesno "Use this icon?" "$candidate"; then
      printf "%s\n" "$candidate"
      return 0
    fi
  done < <(desktop_find_image_candidates "$container_dir")

  if [[ "$any" -eq 0 ]]; then
    return 0
  fi

  # User rejected all.
  printf "%s\n" ""
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
    out+=$(printf "%s\t%s\n" "$(basename -- "$f")" "$name")
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
    return 1
  fi

  local choice
  choice="$(ui_menu "Remove .desktop" "Select an entry to remove" "${args[@]}")" || return 1
  choice="$(trim "$choice")"
  [[ "$choice" =~ ^[0-9]+$ ]] || return 1
  (( choice >= 1 && choice <= ${#files[@]} )) || return 1
  printf "%s\n" "${files[$((choice - 1))]}"
}

