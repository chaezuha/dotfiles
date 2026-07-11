#!/usr/bin/env bash
# Install script for these dotfiles.
# Supported: macOS (Homebrew), Fedora/RHEL-family (dnf), Ubuntu (apt + Neovim PPA),
# Debian (apt), Arch (pacman). Safe to re-run.
set -euo pipefail

cd "$(dirname "$0")"

OS="$(uname -s)"
STOW_PACKAGES=(gitconfig gitignore nvim shell starship)

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

install_macos() {
    command -v brew >/dev/null 2>&1 ||
        die "Homebrew is required on macOS. Install it from https://brew.sh and re-run."

    info "Installing packages with Homebrew"
    local pkg
    for pkg in git stow neovim node ripgrep fd tree-sitter-cli gh \
               fzf zoxide git-delta starship \
               zsh-autosuggestions zsh-syntax-highlighting; do
        brew list "$pkg" >/dev/null 2>&1 || brew install "$pkg"
    done
    for pkg in ghostty font-jetbrains-mono-nerd-font; do
        brew list --cask "$pkg" >/dev/null 2>&1 || brew install --cask "$pkg"
    done

    STOW_PACKAGES+=(ghostty)
}

install_fedora() {
    info "Installing packages with dnf"

    # RHEL clones need EPEL for fzf, zoxide, git-delta and the zsh plugins.
    # ($ID was set when install_linux sourced /etc/os-release.)
    if [ "${ID:-}" != fedora ]; then
        sudo dnf install -y epel-release 2>/dev/null ||
            warn "Could not enable EPEL; some optional packages may be skipped below."
    fi

    sudo dnf install -y git stow neovim nodejs npm ripgrep fd-find python3 gcc unzip curl zsh

    # These are not packaged everywhere (RHEL/EPEL has no gh or tree-sitter-cli,
    # for example) and one unknown name fails the whole dnf transaction, so
    # install them one at a time and keep going when one is missing.
    local pkg
    for pkg in tree-sitter-cli gh fzf zoxide git-delta \
               zsh-autosuggestions zsh-syntax-highlighting; do
        sudo dnf install -y "$pkg" 2>/dev/null ||
            warn "$pkg is not available from dnf on this system; skipping."
    done

    # In the Fedora repos, but not in RHEL/EPEL.
    sudo dnf install -y starship 2>/dev/null || install_starship_fallback

    if ! command -v tree-sitter >/dev/null 2>&1; then
        info "tree-sitter-cli not packaged here; installing via npm"
        sudo npm install -g tree-sitter-cli
    fi
    command -v gh >/dev/null 2>&1 ||
        warn "gh is not in RHEL/EPEL. To install it, add GitHub's repo:" \
             "https://cli.github.com/packages/rpm/gh-cli.repo"
}

# Some packages (e.g. git-delta) only exist in apt on newer Debian/Ubuntu
# releases; install what's available and warn about the rest.
install_apt_optional() {
    local pkg
    for pkg in "$@"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            sudo apt-get install -y "$pkg"
        else
            warn "$pkg is not available in apt on this release; skipping."
        fi
    done
}

# starship is in the Fedora and Arch repos but not in RHEL/EPEL and only in
# the newest Debian/Ubuntu releases; fall back to the official installer,
# which drops a single binary into ~/.local/bin (already first on PATH).
install_starship_fallback() {
    if command -v starship >/dev/null 2>&1; then
        return
    fi
    info "starship not available from the package manager; using the official installer"
    curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin" ||
        warn "starship install failed; the shell config falls back to a plain prompt."
}

# tree-sitter-cli only exists in apt on the newest Debian/Ubuntu releases;
# fall back to npm (already installed on the apt platforms) elsewhere.
install_treesitter_cli() {
    if command -v tree-sitter >/dev/null 2>&1; then
        return
    fi
    if apt-cache show tree-sitter-cli >/dev/null 2>&1; then
        sudo apt-get install -y tree-sitter-cli
    else
        info "tree-sitter-cli not in apt; installing via npm"
        sudo npm install -g tree-sitter-cli
    fi
}

# Debian and Ubuntu install fd's binary as fdfind. Symlink it to ~/.local/bin/fd
# so tools that call the binary directly (Neovim pickers, fzf) can find it too;
# the alias in aliases.sh only covers interactive shells.
link_fdfind() {
    if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
        info "Symlinking fdfind to ~/.local/bin/fd"
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    fi
}

# LazyVim (as locked in lazy-lock.json) needs Neovim 0.11.2+, which not every
# distro repo has caught up to (Debian stable, RHEL/EPEL). When the packaged
# build is too old or missing, fall back to the official release tarball in
# ~/.local/opt/nvim, like the starship fallback. The release binaries need
# glibc 2.31+, so ancient distros still end up with the warning.
nvim_is_current() {
    "$1" --headless -c 'if has("nvim-0.11.2") | q | else | cq | endif' >/dev/null 2>&1
}

install_neovim_fallback() {
    # Accept the packaged nvim or a previously installed fallback copy
    # (~/.local/bin may not be on PATH yet during a first run).
    if command -v nvim >/dev/null 2>&1 && nvim_is_current nvim; then
        return
    fi
    if [ -x "$HOME/.local/bin/nvim" ] && nvim_is_current "$HOME/.local/bin/nvim"; then
        return
    fi

    local arch asset tmp
    arch="$(uname -m)"
    case "$arch" in
        x86_64)        asset=nvim-linux-x86_64.tar.gz ;;
        aarch64|arm64) asset=nvim-linux-arm64.tar.gz ;;
        *)  warn "Packaged Neovim is older than 0.11.2 and there is no release tarball" \
                 "for $arch; the LazyVim config may not work. Build a newer Neovim:" \
                 "https://github.com/neovim/neovim/blob/master/BUILD.md"
            return ;;
    esac

    info "Packaged Neovim is missing or older than 0.11.2; installing the latest release to ~/.local/opt/nvim"
    tmp="$(mktemp -d)"
    if curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/$asset" |
           tar -xzf - -C "$tmp"; then
        rm -rf "$HOME/.local/opt/nvim"
        mkdir -p "$HOME/.local/opt" "$HOME/.local/bin"
        mv "$tmp/${asset%.tar.gz}" "$HOME/.local/opt/nvim"
        ln -sf "$HOME/.local/opt/nvim/bin/nvim" "$HOME/.local/bin/nvim"
    else
        warn "Neovim download failed; the LazyVim config may not work (needs 0.11.2+)." \
             "Install a newer release from https://github.com/neovim/neovim/releases"
    fi
    rm -rf "$tmp"
}

install_starship_apt() {
    if apt-cache show starship >/dev/null 2>&1; then
        sudo apt-get install -y starship
    else
        install_starship_fallback
    fi
}

# .gitconfig points git at delta unconditionally, but delta isn't packaged
# everywhere (older Debian/Ubuntu, RHEL without EPEL). Fall back to a static
# binary from the GitHub release; failing that, override the pager in
# ~/.gitconfig.local (included last, so it wins) so git isn't left invoking
# a missing command.
DELTA_VERSION=0.19.2

install_delta_fallback() {
    if command -v delta >/dev/null 2>&1 || [ -x "$HOME/.local/bin/delta" ]; then
        return
    fi

    local arch target tmp
    arch="$(uname -m)"
    case "$arch" in
        x86_64)        target=x86_64-unknown-linux-musl ;;
        aarch64|arm64) target=aarch64-unknown-linux-gnu ;;
        *)             target="" ;;
    esac

    if [ -n "$target" ]; then
        info "delta not packaged here; installing $DELTA_VERSION from GitHub releases to ~/.local/bin"
        tmp="$(mktemp -d)"
        if curl -fsSL "https://github.com/dandavison/delta/releases/download/$DELTA_VERSION/delta-$DELTA_VERSION-$target.tar.gz" |
               tar -xzf - -C "$tmp"; then
            mkdir -p "$HOME/.local/bin"
            mv "$tmp/delta-$DELTA_VERSION-$target/delta" "$HOME/.local/bin/delta"
        fi
        rm -rf "$tmp"
        [ -x "$HOME/.local/bin/delta" ] && return
    fi

    warn "delta unavailable; pointing git back at less in ~/.gitconfig.local." \
         "Remove the core.pager/interactive.diffFilter overrides there once delta is installed."
    git config --file "$HOME/.gitconfig.local" core.pager less
    git config --file "$HOME/.gitconfig.local" interactive.diffFilter cat
}

install_ubuntu() {
    info "Installing packages with apt (Neovim from ppa:neovim-ppa/unstable)"
    sudo apt-get update
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y ppa:neovim-ppa/unstable
    sudo apt-get install -y git stow neovim nodejs npm ripgrep fd-find \
        python3 python3-venv build-essential unzip curl gh fzf zoxide \
        zsh zsh-autosuggestions zsh-syntax-highlighting
    install_apt_optional git-delta
    install_treesitter_cli
    install_starship_apt
    link_fdfind
}

install_debian() {
    info "Installing packages with apt"
    sudo apt-get update
    sudo apt-get install -y git stow neovim nodejs npm ripgrep fd-find \
        python3 python3-venv build-essential unzip curl gh fzf zoxide \
        zsh zsh-autosuggestions zsh-syntax-highlighting
    install_apt_optional git-delta
    install_treesitter_cli
    install_starship_apt
    link_fdfind
}

install_arch() {
    info "Installing packages with pacman"
    sudo pacman -S --needed --noconfirm git stow neovim nodejs npm ripgrep fd python gcc unzip curl \
        tree-sitter-cli github-cli fzf zoxide git-delta starship \
        zsh zsh-autosuggestions zsh-syntax-highlighting
}

install_linux() {
    [ -r /etc/os-release ] || die "Cannot detect Linux distribution (/etc/os-release missing)."
    # shellcheck source=/dev/null
    . /etc/os-release

    case "${ID:-} ${ID_LIKE:-}" in
        *fedora*|*rhel*)   install_fedora ;;
        ubuntu*)           install_ubuntu ;;
        *debian*)          install_debian ;;
        *arch*)            install_arch ;;
        *) die "Unsupported distribution '${ID:-unknown}'. Install git, stow, neovim, node, ripgrep, fd, tree-sitter, gh, python3, starship, zsh (plus zsh-autosuggestions and zsh-syntax-highlighting), and a C compiler manually, then run: stow ${STOW_PACKAGES[*]}" ;;
    esac
}

# On macOS the font comes from a Homebrew cask; on Linux, download the
# nerd-fonts release into the user font directory.
install_nerd_font_linux() {
    if ! command -v fc-list >/dev/null 2>&1; then
        warn "fontconfig not installed; skipping JetBrainsMono Nerd Font install."
        return
    fi
    # Plain grep (not -q) reads all of fc-list's output. grep -q exits at the
    # first match, which can kill fc-list with SIGPIPE and, under pipefail,
    # make the check fail even though the font is installed.
    if fc-list | grep -i 'JetBrainsMono Nerd Font' >/dev/null; then
        info "JetBrainsMono Nerd Font already installed"
        return
    fi

    info "Installing JetBrainsMono Nerd Font to ~/.local/share/fonts"
    local tmp fontdir
    tmp="$(mktemp -d)"
    fontdir="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
    curl -fsSL -o "$tmp/JetBrainsMono.zip" \
        "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
    mkdir -p "$fontdir"
    unzip -oq "$tmp/JetBrainsMono.zip" -d "$fontdir"
    rm -rf "$tmp"
    fc-cache -f "$fontdir"
}

# Point Ptyxis (GNOME's terminal) at the nerd font, but only if Ptyxis and
# its gsettings schema actually exist on this machine.
configure_ptyxis() {
    command -v ptyxis >/dev/null 2>&1 || return 0
    command -v gsettings >/dev/null 2>&1 || return 0
    # Plain grep, not -q: see the SIGPIPE note in install_nerd_font_linux.
    gsettings list-schemas 2>/dev/null | grep -x 'org.gnome.Ptyxis' >/dev/null || return 0

    info "Setting Ptyxis font to JetBrainsMono Nerd Font 13"
    gsettings set org.gnome.Ptyxis use-system-font false
    gsettings set org.gnome.Ptyxis font-name 'JetBrainsMono Nerd Font 13'
}

# Make zsh the login shell on Linux, matching macOS (where it is the default).
# sudo chsh avoids the password prompt (sudo is already primed from the
# package install) and behaves the same on every supported distro.
set_default_shell_zsh() {
    local zsh current
    zsh="$(command -v zsh)" || { warn "zsh not found; leaving login shell unchanged."; return 0; }

    current="$(getent passwd "$USER" | cut -d: -f7)" || current=""
    [ "$current" = "$zsh" ] && return 0

    grep -qx "$zsh" /etc/shells 2>/dev/null ||
        warn "$zsh is not listed in /etc/shells; chsh may refuse it."

    info "Changing login shell to $zsh (was ${current:-unknown})"
    if ! sudo chsh -s "$zsh" "$USER"; then
        warn "Could not change the login shell (directory account?)." \
             "Run manually: sudo usermod -s $zsh $USER"
    fi
}

# Platform-specific git settings live in ~/.gitconfig.local (included from
# .gitconfig) so the shared config stays portable across macOS and Linux.
setup_git_credential_helper() {
    local localconfig="$HOME/.gitconfig.local"

    if git config --file "$localconfig" --get credential.helper >/dev/null 2>&1; then
        info "Credential helper already configured in $localconfig"
        return
    fi

    local helper
    if [ "$OS" = "Darwin" ]; then
        helper=osxkeychain
    elif command -v git-credential-libsecret >/dev/null 2>&1; then
        helper=libsecret
    else
        helper=cache
    fi

    info "Setting git credential.helper=$helper in $localconfig"
    printf '[credential]\n\thelper = %s\n' "$helper" >>"$localconfig"
}

stow_packages() {
    info "Stowing: ${STOW_PACKAGES[*]}"

    # No conflicts on an already-set-up machine: stow succeeds and we're done.
    if stow --restow "${STOW_PACKAGES[@]}" 2>/dev/null; then
        return
    fi

    # Stow refused because something real sits where a symlink belongs.
    # Only back up a conflicting file when it is clearly not ours: a regular
    # file, not the same inode as the repo's copy, and sitting at its literal
    # physical path (not reached through a symlinked parent, which could be
    # this repo's own files). Anything ambiguous is left for stow to report
    # as a conflict rather than moved.
    local pkg file target bak
    for pkg in "${STOW_PACKAGES[@]}"; do
        while IFS= read -r file; do
            target="$HOME/${file#"$pkg"/}"
            if [ -f "$target" ] && [ ! -L "$target" ] &&
               ! [ "$target" -ef "$file" ] &&
               [ "$(realpath "$target")" = "$target" ]; then
                # Never clobber an earlier backup: fall back to a
                # timestamped name when .bak is already taken.
                bak="$target.bak"
                [ -e "$bak" ] && bak="$target.bak.$(date +%Y%m%d%H%M%S)"
                warn "Backing up existing $target to $bak"
                mv "$target" "$bak"
            fi
        done < <(cd "$pkg" && find . -type f | sed "s|^\./|$pkg/|")
    done

    stow --restow "${STOW_PACKAGES[@]}"
}

# If a shell rc got backed up, keep whatever personal config was in it easy
# to recover: copy it into the matching .local file with every line commented
# out. Never overwrites an existing .local file.
seed_local_from_backup() {
    local bak="$1" localfile="$2"
    [ -f "$bak" ] || return 0
    [ -f "$localfile" ] && return 0

    info "Seeding $localfile from $bak (review it and uncomment what you want to keep)"
    {
        printf '# Seeded by install.sh from %s.\n' "$bak"
        printf '# Uncomment anything you want to keep; the repo zsh config already\n'
        printf '# covers the basics (prompt, completion, history, cargo, ...).\n\n'
        sed 's/^/# /' "$bak"
    } >"$localfile"
}

case "$OS" in
    Darwin) install_macos ;;
    Linux)  install_linux
            install_neovim_fallback
            install_delta_fallback
            install_nerd_font_linux
            configure_ptyxis
            set_default_shell_zsh ;;
    *)      die "Unsupported OS: $OS" ;;
esac

setup_git_credential_helper
stow_packages
seed_local_from_backup "$HOME/.zshrc.bak" "$HOME/.zshrc.local"

info "Done."
