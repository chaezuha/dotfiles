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

The script installs the needed packages (git, stow, neovim, zsh, fzf, zoxide, git-delta, starship, ...) with the platform's package manager, installs the JetBrainsMono Nerd Font, then stows the packages. Where starship isn't packaged (RHEL, older Debian/Ubuntu) it falls back to the [official installer](https://starship.rs/guide/), which puts the binary in `~/.local/bin`. Supported platforms:

- **macOS** (Homebrew, must already be installed). Also installs Ghostty
- **Fedora** / RHEL-family (dnf). On RHEL clones the script tries to enable EPEL first. Packages that still aren't available get skipped with a warning instead of failing the run: tree-sitter-cli is installed through npm instead, and for gh it prints the GitHub repo to add
- **Ubuntu** (apt, with Neovim from `ppa:neovim-ppa/unstable`)
- **Debian** (apt)
- **Arch** (pacman)

Since Debian and Ubuntu name the fd binary `fdfind`, the script symlinks it to `~/.local/bin/fd` (and the shell config aliases it) so `fd` works everywhere.

Ghostty is only installed (and its config only stowed) on macOS. On Linux, the font is installed to `~/.local/share/fonts` and, if [Ptyxis](https://gitlab.gnome.org/chergert/ptyxis) is present, its font is set via gsettings. Zsh is the shell everywhere: the plugins (`zsh-autosuggestions`, `zsh-syntax-highlighting`) come from Homebrew on macOS and from the distro packages on Linux, where the script also installs zsh itself and switches the login shell to it (`sudo chsh`).

Any existing config file that would conflict with a symlink is backed up to `<file>.bak`. The script is safe to re-run.

### Manual setup

1. Install Stow
2. Clone this repo to the desired folder
3. Run `stow <foldername>` for each desired package (skip `ghostty` on Linux)

## Packages

- **`gitconfig`**: shared `~/.gitconfig` (delta as pager, nvim as editor)
- **`gitignore`**: global git ignore at `~/.config/git/ignore` (OS/editor junk)
- **`nvim`**: LazyVim-based Neovim config
- **`starship`**: [starship](https://starship.rs) prompt config at `~/.config/starship.toml` (gruvbox-rainbow preset). The zsh config only inits starship when the binary exists and falls back to a plain prompt otherwise
- **`shell`**: `~/.zshrc` plus the shared POSIX pieces (`env.sh`, `aliases.sh`) in `~/.config/shell/`. Bash is intentionally unmanaged and stays the distro default
- **`ghostty`**: Ghostty terminal config (macOS only)

## Machine-specific overrides

`~/.gitconfig.local` is included from the shared `.gitconfig` but not tracked in this repo. The install script creates it with the platform-appropriate credential helper:

- macOS → `osxkeychain`
- Linux with libsecret available → `libsecret`
- other Linux (e.g. headless servers) → `cache`

It's also the place for any other per-machine overrides (work email, etc.).

The shell config works the same way: `~/.zshrc.local` is sourced last (if it exists) and never tracked in the repo.

## Adding your own shell config

- **Every machine**: edit `shell/.zshrc` (or the shared `shell/.config/shell/*.sh`) in the repo and commit.
- **Just this machine**: put it in `~/.zshrc.local`. Sourced last, never tracked.

Because `~/.zshrc` is a symlink into the repo, installers that append to it (rustup, nvm, conda, ...) write into the repo file, so `git diff` shows exactly what they added. Commit it if it belongs everywhere, or move it to the `.local` file if not. Common ones are already handled: the repo config sources `~/.cargo/env` when it exists, so rustup leaves the file alone.

When the install script backs up a pre-existing `.zshrc` to `.bak`, it also copies the contents into `~/.zshrc.local` with every line commented out. Review it and uncomment anything personal you want to keep; the repo config already covers the basics (prompt, completion, history, PATH). It never overwrites an existing `.local` file.

## Notes

To remove a package's symlinks:

```sh
stow -D <foldername>
```
