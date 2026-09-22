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

The script installs the needed packages (git, stow, neovim, zsh, fzf, zoxide, git-delta, starship, ...) with the platform's package manager, installs the JetBrainsMono Nerd Font, then stows the packages. Where a tool isn't packaged (RHEL, older Debian/Ubuntu) the script falls back to installing it under `~/.local`: starship via its [official installer](https://starship.rs/guide/), git-delta from its GitHub release, and Neovim from the official release tarball whenever the packaged build is older than the 0.11.2 LazyVim needs. Supported platforms:

- **macOS** (Homebrew, must already be installed). Also installs Ghostty
- **Fedora** / RHEL-family (dnf). On RHEL-family systems the script enables EPEL first (the `epel-release` package, or on RHEL itself the release RPM from the Fedora project). Only stow is required from it: other packages that still aren't available get skipped with a warning instead of failing the run. Neovim falls back to the release tarball, tree-sitter-cli is installed through npm instead, and for gh it prints the GitHub repo to add
- **Ubuntu** (apt, with Neovim from `ppa:neovim-ppa/unstable`)
- **Debian** (apt)

On Debian and Ubuntu, `git-delta`, `gh` and `zoxide` are skipped with a warning on releases that don't package them (e.g. Debian 11, Ubuntu 20.04).
- **Arch** (pacman)

Since Debian and Ubuntu name the fd binary `fdfind`, the script symlinks it to `~/.local/bin/fd` (and the shell config aliases it) so `fd` works everywhere.

Ghostty is only installed (and its config only stowed) on macOS. On Linux, the font is installed to `~/.local/share/fonts` and, if [Ptyxis](https://gitlab.gnome.org/chergert/ptyxis) is present, its font is set via gsettings. Zsh is the shell everywhere: the plugins (`zsh-autosuggestions`, `zsh-syntax-highlighting`) come from Homebrew on macOS and from the distro packages on Linux, where the script also installs zsh itself and switches the login shell to it (`sudo chsh`).

Conflicting regular config files are backed up to `<file>.bak`, or `<file>.bak.<timestamp>` with a numeric suffix if needed. Existing backups, including dangling symlinks, are never overwritten. Stow is checked before applying changes. On a detected failure, the script restores this run's backups wherever the original path is still absent. If a destination is occupied (including by a symlink), it keeps the backup and prints both paths for manual recovery. Interruptions may also require manual recovery; package installations are not rolled back. Successful installs are safe to re-run.

### Git signing

The shared config enables SSH commit signing with `~/.ssh/id_ed25519.pub`. This requires Git 2.34 or newer and access to the corresponding signing key (normally loaded into your SSH agent). Configure a different key or signing format in `~/.gitconfig.local` when needed.

After installing and seeding the configs, the installer checks signing using a temporary repository. It announces the check because your agent may request a passphrase, security-key touch, or approval. If validation fails, it exits non-zero with **configs installed; signing setup incomplete**: the installed configs remain in place. Follow the diagnostic, make the key available to your agent, and re-run. The installer never generates keys or disables signing automatically; an explicit local `commit.gpgsign = false` skips validation. The SSH Git-version requirement does not apply to an OpenPGP override.

### Manual setup

1. Install Stow
2. Clone this repo to the desired folder
3. Run `stow <foldername>` for each desired package (skip `ghostty` on Linux)

## Packages

- **`gitconfig`**: shared `~/.gitconfig` (delta as pager, nvim as editor)
- **`gitignore`**: global git ignore at `~/.config/git/ignore` (OS/editor junk)
- **`nvim`**: LazyVim-based Neovim config
- **`starship`**: [starship](https://starship.rs) prompt config at `~/.config/starship.toml` (gruvbox-rainbow preset). The zsh config only inits starship when the binary exists and falls back to a plain prompt otherwise
- **`shell`**: `~/.zshrc`, `~/.zprofile`, and the shared POSIX pieces (`env.sh`, `aliases.sh`) in `~/.config/shell/`. `.zprofile` runs `env.sh` (PATH, Homebrew) for login shells, so graphical logins and IDEs that never read `.zshrc` still find `~/.local/bin`. Bash is intentionally unmanaged and stays the distro default
- **`ghostty`**: Ghostty terminal config (macOS only)

## Machine-specific overrides

`~/.gitconfig.local` is included from the shared `.gitconfig` but not tracked in this repo. The install script creates it with the platform-appropriate credential helper:

- macOS → `osxkeychain`
- Linux with `git-credential-libsecret` installed (on PATH or in `git --exec-path`) → `libsecret`
- other Linux (e.g. headless servers) → `cache`

It's also the place for any other per-machine overrides (work email, etc.).

The shell config works the same way: `~/.zshrc.local` and `~/.zprofile.local` are sourced last (if they exist) and never tracked in the repo.

## Adding your own shell config

- **Every machine**: edit `shell/.zshrc` (or the shared `shell/.config/shell/*.sh`) in the repo and commit.
- **Just this machine**: put it in `~/.zshrc.local` (or `~/.zprofile.local` for login-only environment such as PATH additions). Sourced last, never tracked.

Because `~/.zshrc` is a symlink into the repo, installers that append to it (rustup, nvm, conda, Unity, ...) write into the repo file, so `git diff` shows exactly what they added. Commit it if it belongs everywhere, or move it to the `.local` file if not. The repo config already sources `~/.cargo/env` and `~/.unity/env` when present, before local overrides. Review additions from future tool installers for duplicates or machine-specific paths.

After a successful Stow run, the installer copies the `.zshrc` and `.zprofile` backups made by that run into `~/.zshrc.local` and `~/.zprofile.local`, with every line commented out and owner-only (`0600`) permissions. This uses the actual backup path, including a timestamp or suffix; historical backups are never used on reruns. Review it and uncomment anything personal you want to keep. An existing `.local` file, including a dangling symlink, is always preserved.

## Verification

Run `bash tests/install_test.sh` with Git, Stow, and OpenSSH installed. The suite uses temporary homes, fixture packages, and a throwaway SSH agent; it does not install packages or use your signing keys. Neovim and Zsh integration checks are skipped explicitly if those executables are unavailable. On macOS, `/bin/bash tests/install_test.sh` also checks compatibility with Bash 3.2.

## Notes

To remove a package's symlinks:

```sh
stow -D <foldername>
```
