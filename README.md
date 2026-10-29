# dotfiles

My configs for zsh, git, neovim, starship and ghostty. Managed with [GNU Stow](https://www.gnu.org/software/stow/), plus an install script so I can get a new machine (Mac or Linux) set up without thinking about it.

## Setup

```sh
git clone https://github.com/chaezuha/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

Then open a new terminal (on Linux, log out and back in so zsh becomes the login shell) and run `nvim` once to let LazyVim pull its plugins.

The script installs everything with whatever package manager the system has (Homebrew, dnf, apt or pacman), grabs JetBrainsMono Nerd Font, and stows the configs. It's fine to run again whenever. Anything already sitting where a symlink needs to go gets moved to `<file>.bak` first, so nothing gets clobbered.

You need git, Homebrew on a Mac, `sudo` on Linux, and an SSH key at `~/.ssh/id_ed25519` loaded into your agent.

On Fedora Silverblue it works differently (everything lives in distroboxes), see [Fedora Silverblue](#fedora-silverblue).

### If it says "signing setup incomplete"

I sign commits with my SSH key, and the script does a test signature at the end. If that fails the configs are still installed, git just can't sign yet. Usually `ssh-add ~/.ssh/id_ed25519` and re-running fixes it. If you don't want signing, put `commit.gpgsign = false` in `~/.gitconfig.local`.

## What's in here

Each top-level folder (except `silverblue/` and `tests/`) is a stow package, and whatever's inside it gets symlinked into `~` at the same path. So `nvim/.config/nvim/init.lua` ends up at `~/.config/nvim/init.lua`. `.stowrc` points stow at `~`, so it works from wherever the repo is cloned.

To add a new one, make a folder that mirrors the home-dir path (e.g. `tmux/.config/tmux/tmux.conf`), then `stow tmux`. Add it to `STOW_PACKAGES` in `install.sh` so the installer picks it up too.

| Package | Goes to | |
| --- | --- | --- |
| `shell` | `~/.zshrc`, `~/.zprofile`, `~/.config/shell/` | zsh with autosuggestions, syntax highlighting, fzf, zoxide |
| `starship` | `~/.config/starship.toml` | gruvbox-rainbow prompt |
| `nvim` | `~/.config/nvim/` | LazyVim, Catppuccin Mocha, format on save |
| `gitconfig` | `~/.gitconfig` | delta pager, nvim editor, SSH signing, rebase on pull |
| `gitignore` | `~/.config/git/ignore` | global ignores for OS/editor junk |
| `ghostty` | `~/.config/ghostty/config` | Mac only |

Bash isn't touched.

## Per-machine stuff

Anything that only belongs on one machine (work email, extra PATH entries, etc.) goes in a `.local` file. These aren't tracked and get sourced last:

- `~/.gitconfig.local`
- `~/.zshrc.local`
- `~/.zprofile.local` (PATH and other login-shell env)

If the installer had to move an old `.zshrc` or `.zprofile` out of the way, it copies it into the matching `.local` file with everything commented out, so I can pick out what I still want.

Shell changes for every machine go in `shell/.zshrc` (or `shell/.config/shell/*.sh`) and get committed. Changes for just this machine go in the `.local` files.

**Heads up:** `~/.zshrc` is a symlink into this repo, so tools that append to it (rustup, nvm, conda...) end up editing the repo. Check `git diff` before committing and move anything machine-specific into `~/.zshrc.local`. `~/.cargo/env` is already sourced, so the line rustup adds can just be deleted.

## Distro quirks

- **RHEL family:** turns on EPEL to get stow.
- **Ubuntu:** neovim comes from the unstable PPA, since LazyVim wants 0.11.2+.
- **Debian/Ubuntu:** `fd` is called `fdfind`, so it gets symlinked to `~/.local/bin/fd`. Older releases without `git-delta`, `gh` or `zoxide` packages just skip them.
- **Any Linux:** if the distro doesn't package starship, delta or a new enough neovim, they get installed under `~/.local` instead.

## Fedora Silverblue

The host is immutable, so I keep it nearly bare (bash, distrobox, the font) and do everything else in two [distroboxes](https://distrobox.it/), defined in `distrobox.ini`:

- **`main`** is the daily driver. It shares the real home, so it behaves like a normal install.
- **`dev`** is for programming languages. It gets its own home at `~/distrobox/dev`, so all the `~/.cargo`, `~/.npm`, `~/.gradle` junk stays out of the real one. Deleting the box and that folder wipes it completely.

Setting it up goes:

1. On the host, run `./install.sh` (it only does the font and Ptyxis here), then `./silverblue/host.sh` to layer distrobox, then reboot.
2. Run `./silverblue/assemble.sh` to create both boxes.
3. In `main`, run `~/dotfiles/install.sh`. This also exports `nvim` to the host, so it works from a plain terminal.
4. In `dev`, run `"$DISTROBOX_HOST_HOME/dotfiles/install.sh"`, because `~/dotfiles` isn't linked into `dev` until that first run.
5. In Ptyxis, make profiles with the custom commands `distrobox enter main` and `distrobox enter dev`. Ptyxis's own container menu can open a non-login shell, which skips the config.

To move the boxes to a new Fedora release, rebuild them instead of upgrading in place: `./silverblue/assemble.sh --replace`, then re-run `install.sh` in each one. A rebuild keeps the home (and `~/distrobox/dev`) but wipes every package, including ones you installed yourself with `dnf install`. To keep one, add it to the box's `additional_packages` in `distrobox.ini` or reinstall it after (`dnf history list` shows what you installed).

Toolchains (rustup, Node, uv...) go in `dev`, not `main`, and projects go in `~/Dev`. The `.local` files and shell history are per home, so `dev` has its own. `dev`'s separate home is about clutter, not security, since the real home is still mounted in it.

**Heads up:** host git uses the same `.gitconfig`, which pages through delta, and delta only exists in the boxes. To make git work from a plain host terminal, add this to the host's `~/.bashrc`:

```bash
if [ -z "${CONTAINER_ID:-}" ] && ! command -v delta >/dev/null 2>&1; then
    git() { command git -c core.pager=less -c interactive.diffFilter=cat "$@"; }
fi
```

## Doing it by hand

On a distro the script doesn't know, install these first: stow, git, neovim, node, ripgrep, fd, tree-sitter, gh, python3, starship, zsh (plus zsh-autosuggestions and zsh-syntax-highlighting), and a C compiler.

Then stow whatever you want (this also works for just grabbing a few configs):

```sh
cd ~/dotfiles
stow shell starship nvim gitconfig gitignore
stow ghostty   # mac only
```

`stow -D <package>` removes one again.

## Updating

```sh
cd ~/dotfiles && git pull && ./install.sh
```

The configs are symlinks, so most changes apply right after the pull. `exec zsh` to reload the shell.

## Stuff I'll forget

- `.zprofile` exists so login shells and IDEs (which never read `.zshrc`) still get PATH.
- `~/.gitconfig.local` gets a credential helper: `osxkeychain` on Mac, `libsecret` on Linux if it's installed, `cache` otherwise.
- If delta can't be installed, the pager falls back to `less` in `~/.gitconfig.local`.
- SSH signing needs Git 2.34+. The installer never makes keys or turns signing off.
- If `<file>.bak` already exists, the backup gets a timestamp instead. Package installs are never rolled back.

## Tests

```sh
bash tests/install_test.sh
/bin/bash tests/install_test.sh   # on macOS, checks it still works on Bash 3.2
```

They run in throwaway home dirs with a fake SSH agent, so they won't touch the real setup. The Silverblue and distrobox paths are tested with stubs, so they run on any machine.
