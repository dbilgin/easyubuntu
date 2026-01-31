# EasyUbuntu

`easyubuntu` is a small CLI for Ubuntu that helps you **create/import/list/remove** user `.desktop` launcher entries.

## Install

### Install from GitHub (curl)

```bash
curl -fsSL "https://raw.githubusercontent.com/dbilgin/easyubuntu/master/install.sh" | bash
```

To install from a different branch/tag/commit, set `EASYUBUNTU_REF`:

```bash
curl -fsSL "https://raw.githubusercontent.com/dbilgin/easyubuntu/master/install.sh" | EASYUBUNTU_REF="master" bash
```

To install from a fork, set `EASYUBUNTU_REPO`:

```bash
curl -fsSL "https://raw.githubusercontent.com/dbilgin/easyubuntu/master/install.sh" | EASYUBUNTU_REPO="owner/repo" bash
```

### Install from a local clone

```bash
./install.sh
```

## Run

```bash
easyubuntu
```

If your shell can’t find it, ensure `~/.local/bin` is on your `PATH` (the installer prints the exact snippet).

## Uninstall

```bash
./uninstall.sh
```

Or if you no longer have the repo:

```bash
curl -fsSL "https://raw.githubusercontent.com/dbilgin/easyubuntu/master/uninstall.sh" | bash
```

## What it manages

- Installs `easyubuntu` to `~/.local/bin/easyubuntu`
- Stores app data under `~/.local/share/easyubuntu/`
- Manages user launcher entries under `~/.local/share/applications/`
