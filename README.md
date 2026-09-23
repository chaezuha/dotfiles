# My dotfiles

My shell, Git, Neovim, and terminal configs, managed with [GNU Stow](https://www.gnu.org/software/stow/). One script installs the tools and links the configs into your home directory on macOS and the major Linux distros.

## Features

- **One-command setup:** `./install.sh` installs the packages, a Nerd Font, and the configs on macOS, Fedora/RHEL, Ubuntu, Debian, and Arch. It's safe to re-run.
- **Zsh everywhere:** Shared history, case-insensitive completion, autosuggestions, syntax highlighting, fzf key bindings, and zoxide. On Linux, zsh becomes your login shell.
- **Starship prompt:** The gruvbox-rainbow preset, with a plain prompt as a fallback when starship isn't installed.
- **Neovim with LazyVim:** Catppuccin Mocha, language support for C/C++, Python, Rust, Java, TypeScript, and more, format-on-save, and Diffview.
- **Git defaults:** delta as the pager, Neovim as the editor, SSH commit signing, rebase on pull, and pruning on fetch.
- **Terminal and font:** JetBrainsMono Nerd Font everywhere. Ghostty on macOS, and the Ptyxis font is set on Linux if you use it.
- **Per-machine overrides:** Untracked `.local` files for anything that belongs to one machine only, such as a work email or extra PATH entries.
- **Your old configs are kept:** Existing files that would be replaced are backed up first, and your old `.zshrc` and `.zprofile` are copied into the `.local` files for review.

## Quick start

Prerequisites: Git, Homebrew on macOS, `sudo` on Linux, and an SSH key at `~/.ssh/id_ed25519` loaded into your SSH agent (used for [commit signing](#git-signing)).

1. Clone the repo and run the installer:

   ```sh
   git clone https://github.com/chaezuha/dotfiles.git ~/dotfiles  # clone the repo
   cd ~/dotfiles                                                  # enter it
   ./install.sh                                                   # install packages and link the configs
   ```

2. Open a new terminal. On Linux, log out and back in so zsh becomes your login shell.

That's it. Run `nvim` next: LazyVim installs its plugins on the first launch.

> If the installer ends with **configs installed; signing setup incomplete**, your configs are in place but Git can't sign with your key. Load the key into your agent (`ssh-add ~/.ssh/id_ed25519`), or set a different key in `~/.gitconfig.local`, then re-run `./install.sh`. See [Git signing](#git-signing).

## Usage

### Project structure

```
dotfiles/
├── install.sh    # the installer
├── tests/        # installer tests
├── .stowrc       # makes stow target your home directory
├── gitconfig/    # Stow packages: each one is mirrored into ~
├── gitignore/
├── ghostty/
├── nvim/
├── shell/
└── starship/
```

### Packages

Each package's files are linked into `~` at the same relative path. For example, `gitconfig/.gitconfig` becomes `~/.gitconfig`.

| Package | Links to | What's in it |
| --- | --- | --- |
| `gitconfig` | `~/.gitconfig` | Shared Git config (delta as pager, nvim as editor, SSH signing). |
| `gitignore` | `~/.config/git/ignore` | Global Git ignore for OS and editor junk. |
| `nvim` | `~/.config/nvim/` | LazyVim-based Neovim config. |
| `starship` | `~/.config/starship.toml` | [Starship](https://starship.rs) prompt config (gruvbox-rainbow preset). |
| `shell` | `~/.zshrc`, `~/.zprofile`, `~/.config/shell/` | Zsh config plus shared POSIX pieces (`env.sh`, `aliases.sh`). `.zprofile` sets PATH for login shells and IDEs that never read `.zshrc`. |
| `ghostty` | `~/.config/ghostty/config` | Ghostty terminal config. macOS only. |

Bash is intentionally unmanaged and stays the distro default.

### What the installer does

The installer installs the needed packages (git, stow, neovim, zsh, fzf, zoxide, git-delta, starship, and more) with your platform's package manager, installs the JetBrainsMono Nerd Font, then stows the packages.

| Platform | Package manager | Differences |
| --- | --- | --- |
| macOS | Homebrew | Homebrew must already be installed. Also installs Ghostty and stows its config. |
| Fedora / RHEL family | dnf | On RHEL-family systems, EPEL is enabled first (the `epel-release` package, or on RHEL itself the release RPM from the Fedora project). Only stow is required from it. Other missing packages are skipped with a warning. tree-sitter-cli comes from npm, and for gh the script prints the GitHub repo to add. |
| Ubuntu | apt | Neovim comes from `ppa:neovim-ppa/unstable`. |
| Debian | apt | |
| Arch | pacman | |

On every Linux distro, the installer also:

- Installs zsh and switches your login shell to it (`sudo chsh`). The zsh plugins (`zsh-autosuggestions`, `zsh-syntax-highlighting`) come from the distro packages. On macOS they come from Homebrew.
- Installs the font to `~/.local/share/fonts` and, if [Ptyxis](https://gitlab.gnome.org/chergert/ptyxis) is present, sets its font with gsettings.
- Installs tools under `~/.local` when the distro doesn't package them: starship with its [official installer](https://starship.rs/guide/), git-delta from its GitHub release, and Neovim from the official release tarball whenever the packaged build is older than the 0.11.2 that LazyVim needs. If delta can't be installed at all, Git's pager is set back to `less` in `~/.gitconfig.local`.

On Debian and Ubuntu:

- `git-delta`, `gh`, and `zoxide` are skipped with a warning on releases that don't package them (for example Debian 11 or Ubuntu 20.04).
- The fd binary is named `fdfind`, so the script symlinks it to `~/.local/bin/fd` (and the shell config aliases it) so `fd` works everywhere.

## Configuration

Machine-specific settings live in `.local` files, which are never tracked in the repo.

| File | What it does |
| --- | --- |
| `~/.gitconfig.local` | Per-machine Git settings, included last so it overrides the shared config. Use it for a different signing key or your own name and email. The installer creates it with a credential helper: `osxkeychain` on macOS, `libsecret` on Linux when `git-credential-libsecret` is installed (on PATH or in `git --exec-path`), and `cache` otherwise (for example on headless servers). |
| `~/.zshrc.local` | Per-machine interactive shell config, sourced last. Not created by default. |
| `~/.zprofile.local` | Per-machine login environment, such as PATH additions, sourced last. Not created by default. |

### Git signing

Commits are signed with SSH using `~/.ssh/id_ed25519.pub`. This requires Git 2.34 or newer (not needed if you switch to OpenPGP) and the matching private key, normally loaded into your SSH agent.

At the end of a run, the installer makes a test signature, so your agent may ask for a passphrase, a security-key touch, or an approval. If it fails, the installer exits with **configs installed; signing setup incomplete**. Your configs stay in place: make the key available to your agent and re-run. The installer never generates keys or turns signing off. To skip the check, set `commit.gpgsign = false` in `~/.gitconfig.local`.

### Adding your own shell config

- **Every machine:** edit `shell/.zshrc` (or the shared `shell/.config/shell/*.sh`) in the repo and commit.
- **Just this machine:** put it in `~/.zshrc.local`, or in `~/.zprofile.local` for login-only environment such as PATH additions.

Because `~/.zshrc` is a symlink into the repo, installers that append to it (rustup, nvm, conda, Unity, and so on) write into the repo file. Check `git diff` before committing: commit what belongs on every machine, and move machine-specific paths or tokens to the `.local` file. The repo config already sources `~/.cargo/env` and `~/.unity/env` when present, so you can drop duplicate lines those installers add.

If the installer had to back up an existing `.zshrc` or `.zprofile`, it copies that backup into `~/.zshrc.local` or `~/.zprofile.local` with every line commented out and owner-only (`0600`) permissions. Review it and uncomment anything you want to keep. An existing `.local` file is never overwritten.

## Other ways to run

### Manual setup with Stow

Use this to pick individual packages, or on a distro the installer doesn't support.

1. Install Stow. On an unsupported distro, also install git, neovim, node, ripgrep, fd, tree-sitter, gh, python3, starship, zsh (plus zsh-autosuggestions and zsh-syntax-highlighting), and a C compiler.
2. Clone the repo and stow the packages you want. The repo's `.stowrc` targets your home directory, so this works from any clone location. Skip `ghostty` on Linux.

```sh
git clone https://github.com/chaezuha/dotfiles.git ~/dotfiles  # clone the repo
cd ~/dotfiles                                                  # enter it
stow gitconfig gitignore nvim shell starship                   # link the packages you want
stow ghostty                                                   # macOS only
```

## Running it long-term

### Updating

```sh
cd ~/dotfiles   # enter the repo
git pull        # get the latest configs
./install.sh    # install any new packages and links
```

The configs are symlinks, so changes to existing files apply as soon as you pull. Open a new shell (or run `exec zsh`) to load shell changes.

### Backups

When a regular file is in the way of a link, the installer moves it to `<file>.bak` (or `<file>.bak.<timestamp>` if that name is taken) and never overwrites an existing backup. If linking fails, it puts this run's backups back, or keeps them and prints both paths so you can recover by hand. Package installs are not rolled back, and an interrupted run may need manual recovery.

### Removing a package

```sh
cd ~/dotfiles        # enter the repo
stow -D nvim         # remove the links for one package (here, nvim)
```

## Development

Run the test suite with Git, Stow, and OpenSSH installed:

```sh
bash tests/install_test.sh       # run the installer tests
/bin/bash tests/install_test.sh  # macOS: also check Bash 3.2 compatibility
```

The suite uses temporary home directories, fixture packages, and a throwaway SSH agent. It doesn't install packages or use your signing keys. The Neovim and Zsh checks are skipped, with a message, if those programs aren't installed.
