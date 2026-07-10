# My dotfiles

Some of my configs, managed with [GNU Stow](https://www.gnu.org/software/stow/).

## General structure

The top-level folders are Stow packages that get mirrored into `$HOME`.

For example: `gitconfig/.gitconfig` → `~/.gitconfig`

## Setup

Clone the repo and run the install script:

```sh
git clone <repo-url> ~/dotfiles
cd ~/dotfiles
./install.sh
```

The script installs git, stow, and neovim with the platform's package manager, then stows the packages. Supported platforms:

- **macOS** (Homebrew, must already be installed) — also installs Ghostty
- **Fedora** / RHEL-family (dnf)
- **Ubuntu** (apt, with Neovim from `ppa:neovim-ppa/unstable`)
- **Debian** (apt)
- **Arch** (pacman)

Ghostty is only installed (and its config only stowed) on macOS.

Any existing config file that would conflict with a symlink is backed up to `<file>.bak`. The script is safe to re-run.

### Manual setup

1. Install Stow
2. Clone this repo to the desired folder
3. Run `stow <foldername>` for each desired package (skip `ghostty` on Linux)

## Machine-specific git config

`~/.gitconfig.local` is included from the shared `.gitconfig` but not tracked in this repo. The install script creates it with the platform-appropriate credential helper:

- macOS → `osxkeychain`
- Linux with libsecret available → `libsecret`
- other Linux (e.g. headless servers) → `cache`

It's also the place for any other per-machine overrides (work email, etc.).

## Notes

To remove a package's symlinks:

```sh
stow -D <foldername>
```
