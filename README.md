# EasyUbuntu

EasyUbuntu is a small Ubuntu-focused CLI with a terminal UI (TUI) that currently supports:

- **Managing `.desktop` launchers**: list/create/import/remove user launchers
- **Managing AppArmor profiles**: create/remove EasyUbuntu-managed profiles (requires sudo)

<img width="700" alt="image" src="https://github.com/user-attachments/assets/5bb55f59-71df-4872-b701-2574ada16449" />


## Install

```bash
curl -fsSL "https://raw.githubusercontent.com/dbilgin/easyubuntu/master/install.sh" | bash
```

### Install from different branch/tag/commit:

```bash
curl -fsSL "https://raw.githubusercontent.com/dbilgin/easyubuntu/master/install.sh" | EASYUBUNTU_REF="master" bash
```

## Run

```bash
easyubuntu
```

If your shell can’t find it, ensure `~/.local/bin` is on your `PATH` (the installer prints the exact snippet).

## Uninstall

```bash
curl -fsSL "https://raw.githubusercontent.com/dbilgin/easyubuntu/master/uninstall.sh" | bash
```

## Dependencies

- **UI**: `whiptail` (recommended). If missing, EasyUbuntu uses a basic text fallback.
- **Icon preview**: `chafa` (optional; enables real terminal preview during icon selection).
- **AppArmor**: requires `apparmor_parser` and `systemctl`, and writing profiles requires **sudo**.

## What it installs / touches

- **Binary**: `~/.local/bin/easyubuntu`
- **Libraries/data**: `~/.local/share/easyubuntu/`
- **User `.desktop` entries**: `~/.local/share/applications/`
- **AppArmor profiles (when used)**: `/etc/apparmor.d/` (EasyUbuntu-managed profiles are marked in-file)
