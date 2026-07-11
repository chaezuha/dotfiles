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

The script installs the needed packages (git, stow, neovim, fzf, zoxide, git-delta, …) with the platform's package manager, installs the JetBrainsMono Nerd Font, then stows the packages. Supported platforms:

- **macOS** (Homebrew, must already be installed) — also installs Ghostty
- **Fedora** / RHEL-family (dnf)
- **Ubuntu** (apt, with Neovim from `ppa:neovim-ppa/unstable`)
- **Debian** (apt)
- **Arch** (pacman)

Ghostty is only installed (and its config only stowed) on macOS. On Linux, the font is installed to `~/.local/share/fonts` and, if [Ptyxis](https://gitlab.gnome.org/chergert/ptyxis) is present, its font is set via gsettings. The zsh plugins (`zsh-autosuggestions`, `zsh-syntax-highlighting`) are installed via Homebrew on macOS; on Linux the `.zshrc` picks them up automatically if the distro packages are installed.

Any existing config file that would conflict with a symlink is backed up to `<file>.bak`. The script is safe to re-run.

### Manual setup

1. Install Stow
2. Clone this repo to the desired folder
3. Run `stow <foldername>` for each desired package (skip `ghostty` on Linux)

## Packages

- **`gitconfig`** — shared `~/.gitconfig` (delta as pager, nvim as editor)
- **`gitignore`** — global git ignore at `~/.config/git/ignore` (OS/editor junk)
- **`nvim`** — LazyVim-based Neovim config
- **`shell`** — `~/.zshrc`, `~/.bashrc`, and `~/.bash_profile`; the shared POSIX pieces (`env.sh`, `aliases.sh`) live in `~/.config/shell/` and are sourced by both shells
- **`ghostty`** — Ghostty terminal config (macOS only)

## Machine-specific overrides

`~/.gitconfig.local` is included from the shared `.gitconfig` but not tracked in this repo. The install script creates it with the platform-appropriate credential helper:

- macOS → `osxkeychain`
- Linux with libsecret available → `libsecret`
- other Linux (e.g. headless servers) → `cache`

It's also the place for any other per-machine overrides (work email, etc.).

The shell configs work the same way: `~/.zshrc.local` and `~/.bashrc.local` are sourced last (if they exist) and are never tracked in the repo.

## Notes

To remove a package's symlinks:

```sh
stow -D <foldername>
```
