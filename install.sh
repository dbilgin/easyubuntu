#!/usr/bin/env bash
set -euo pipefail

DEFAULT_REPO="dbilgin/easyubuntu"
DEFAULT_REF="master"
EASYUBUNTU_VERSION="0.1.0"

say() { printf "%s\n" "$*"; }
err() { printf "install.sh: %s\n" "$*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; exit 1; }
}

os_sanity_check() {
  if [[ ! -f /etc/os-release ]]; then
    return 0
  fi
  # shellcheck disable=SC1091
  . /etc/os-release || true
  case "${ID:-}" in
    ubuntu|debian|pop|linuxmint|elementary|kali) return 0 ;;
    *)
      err "Warning: this tool targets Ubuntu/Debian-like systems (detected ID=${ID:-unknown})."
      return 0
      ;;
  esac
}

install_paths() {
  local bin_dir="${XDG_BIN_HOME:-$HOME/.local/bin}"
  local data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/easyubuntu"
  printf "%s\n" "$bin_dir" "$data_dir"
}

path_has() {
  case ":$PATH:" in
    *":$1:"*) return 0 ;;
    *) return 1 ;;
  esac
}

print_path_hint() {
  local bin_dir="$1"
  if path_has "$bin_dir"; then
    return 0
  fi

say ""
say "Note: your PATH does not include $bin_dir"
say "Add this to your shell rc file (e.g. ~/.bashrc):"
say ""
say "  export PATH=\"\$PATH:$bin_dir\""
say ""
}

install_from_local_repo() {
  local script_dir="$1"
  [[ -f "$script_dir/bin/easyubuntu" && -f "$script_dir/lib/ui.sh" && -f "$script_dir/lib/desktop.sh" ]]
}

download_repo_tarball() {
  local repo="$1"
  local ref="$2"
  local tmp_dir="$3"

  need_cmd curl
  need_cmd tar
  need_cmd find
  need_cmd head

  local url="https://codeload.github.com/$repo/tar.gz/$ref"
  say "Downloading $repo@$ref ..."
  curl -fsSL "$url" | tar -xz -C "$tmp_dir"
}

main() {
  os_sanity_check

  local repo="${EASYUBUNTU_REPO:-$DEFAULT_REPO}"
  local ref="${EASYUBUNTU_REF:-$DEFAULT_REF}"

  local bin_dir data_dir
  local -a p=()
  mapfile -t p < <(install_paths)
  bin_dir="${p[0]}"
  data_dir="${p[1]}"

  need_cmd install

  mkdir -p "$bin_dir" "$data_dir/lib"

  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

  local src_root=""
  local tmp=""

  if install_from_local_repo "$script_dir"; then
    src_root="$script_dir"
    say "Installing from local checkout: $src_root"
  else
    tmp="$(mktemp -d)"
    download_repo_tarball "$repo" "$ref" "$tmp"
    # The tarball extracts into <repo>-<ref> (unknown exact suffix), so pick the only directory.
    src_root="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    if [[ -z "$src_root" ]]; then
      err "Download failed (no extracted directory)."
      exit 1
    fi
  fi

  if [[ ! -f "$src_root/bin/easyubuntu" ]]; then
    err "Could not find bin/easyubuntu in sources."
    exit 1
  fi

  install -m 0755 "$src_root/bin/easyubuntu" "$bin_dir/easyubuntu"
  install -m 0644 "$src_root/lib/ui.sh" "$data_dir/lib/ui.sh"
  install -m 0644 "$src_root/lib/desktop.sh" "$data_dir/lib/desktop.sh"
  install -m 0644 "$src_root/lib/apparmor.sh" "$data_dir/lib/apparmor.sh"
  printf "%s\n" "$EASYUBUNTU_VERSION" >"$data_dir/VERSION"

  if [[ -n "$tmp" ]]; then
    rm -rf "$tmp"
  fi

  say ""
  say "Installed EasyUbuntu to:"
  say "  $bin_dir/easyubuntu"
  say ""
  say "Run:"
  say "  easyubuntu"

  print_path_hint "$bin_dir"

  if command -v whiptail >/dev/null 2>&1; then
    say "UI: whiptail detected."
  else
    say "UI: whiptail not found; EasyUbuntu will use a simple text fallback."
    say "To install whiptail on Ubuntu:"
    say "  sudo apt-get update && sudo apt-get install -y whiptail"
  fi
}

main "$@"

