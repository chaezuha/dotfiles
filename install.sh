#!/usr/bin/env bash
# Install script for these dotfiles.
# Supported: macOS (Homebrew), Fedora/RHEL-family (dnf), Ubuntu (apt + Neovim PPA),
# Debian (apt), Arch (pacman). Safe to re-run.
set -euo pipefail

cd "$(dirname "$0")"

OS="$(uname -s)"
STOW_PACKAGES=(gitconfig gitignore nvim shell)

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

install_macos() {
    command -v brew >/dev/null 2>&1 ||
        die "Homebrew is required on macOS. Install it from https://brew.sh and re-run."

    info "Installing packages with Homebrew"
    local pkg
    for pkg in git stow neovim node ripgrep fd tree-sitter-cli gh \
               fzf zoxide git-delta zsh-autosuggestions zsh-syntax-highlighting; do
        brew list "$pkg" >/dev/null 2>&1 || brew install "$pkg"
    done
    for pkg in ghostty font-jetbrains-mono-nerd-font; do
        brew list --cask "$pkg" >/dev/null 2>&1 || brew install --cask "$pkg"
    done

    STOW_PACKAGES+=(ghostty)
}

install_fedora() {
    info "Installing packages with dnf"
    sudo dnf install -y git stow neovim nodejs ripgrep fd-find python3 gcc unzip curl \
        tree-sitter-cli gh fzf zoxide git-delta
}

# Some packages (e.g. git-delta) only exist in apt on newer Debian/Ubuntu
# releases; install what's available and warn about the rest.
install_apt_optional() {
    local pkg
    for pkg in "$@"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            sudo apt-get install -y "$pkg"
        else
            warn "$pkg is not available in apt on this release; skipping." \
                 "If skipped: git is configured to use delta as its pager," \
                 "so install git-delta manually (https://dandavison.github.io/delta/)."
        fi
    done
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

install_ubuntu() {
    info "Installing packages with apt (Neovim from ppa:neovim-ppa/unstable)"
    sudo apt-get update
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y ppa:neovim-ppa/unstable
    sudo apt-get install -y git stow neovim nodejs npm ripgrep fd-find \
        python3 python3-venv build-essential unzip curl gh fzf zoxide
    install_apt_optional git-delta
    install_treesitter_cli
}

install_debian() {
    info "Installing packages with apt"
    sudo apt-get update
    sudo apt-get install -y git stow neovim nodejs npm ripgrep fd-find \
        python3 python3-venv build-essential unzip curl gh fzf zoxide
    install_apt_optional git-delta
    install_treesitter_cli
    if ! nvim --headless -c 'if has("nvim-0.10") | q | else | cq | endif' >/dev/null 2>&1; then
        warn "Installed Neovim is older than 0.10; the LazyVim config may not work." \
             "Consider installing a newer release from https://github.com/neovim/neovim/releases"
    fi
}

install_arch() {
    info "Installing packages with pacman"
    sudo pacman -S --needed --noconfirm git stow neovim nodejs npm ripgrep fd python gcc unzip curl \
        tree-sitter-cli github-cli fzf zoxide git-delta
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
        *) die "Unsupported distribution '${ID:-unknown}'. Install git, stow, neovim, node, ripgrep, fd, tree-sitter, gh, python3, and a C compiler manually, then run: stow ${STOW_PACKAGES[*]}" ;;
    esac
}

# On macOS the font comes from a Homebrew cask; on Linux, download the
# nerd-fonts release into the user font directory.
install_nerd_font_linux() {
    if ! command -v fc-list >/dev/null 2>&1; then
        warn "fontconfig not installed; skipping JetBrainsMono Nerd Font install."
        return
    fi
    if fc-list | grep -qi 'JetBrainsMono Nerd Font'; then
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

# Point Ptyxis (GNOME's terminal) at the nerd font — only when Ptyxis and its
# gsettings schema actually exist on this machine.
configure_ptyxis() {
    command -v ptyxis >/dev/null 2>&1 || return 0
    command -v gsettings >/dev/null 2>&1 || return 0
    gsettings list-schemas 2>/dev/null | grep -qx 'org.gnome.Ptyxis' || return 0

    info "Setting Ptyxis font to JetBrainsMono Nerd Font 13"
    gsettings set org.gnome.Ptyxis use-system-font false
    gsettings set org.gnome.Ptyxis font-name 'JetBrainsMono Nerd Font 13'
}

# Platform-specific git settings live in ~/.gitconfig.local (included from
# .gitconfig) so the shared config stays portable across macOS and Linux.
setup_git_credential_helper() {
    local localconfig="$HOME/.gitconfig.local"

    if [ -f "$localconfig" ] && grep -q '^\[credential\]' "$localconfig"; then
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
    # Back up a conflicting file only when it is provably foreign: a regular
    # file, not the same inode as the repo's copy, and living at its literal
    # physical path (never reached through a symlinked parent — that could
    # be this repo's own files). Anything ambiguous is left for stow to
    # report as a conflict rather than moved.
    local pkg file target
    for pkg in "${STOW_PACKAGES[@]}"; do
        while IFS= read -r file; do
            target="$HOME/${file#"$pkg"/}"
            if [ -f "$target" ] && [ ! -L "$target" ] &&
               ! [ "$target" -ef "$file" ] &&
               [ "$(realpath "$target")" = "$target" ]; then
                warn "Backing up existing $target to $target.bak"
                mv "$target" "$target.bak"
            fi
        done < <(cd "$pkg" && find . -type f | sed "s|^\./|$pkg/|")
    done

    stow --restow "${STOW_PACKAGES[@]}"
}

# Anything personal in a backed-up shell rc should be easy to recover: copy
# it into the corresponding .local file, fully commented out, for the user to
# review. Never overwrites an existing .local file.
seed_local_from_backup() {
    local bak="$1" localfile="$2"
    [ -f "$bak" ] || return 0
    [ -f "$localfile" ] && return 0

    info "Seeding $localfile from $bak — review it and uncomment what you want to keep"
    {
        printf '# Seeded by install.sh from %s.\n' "$bak"
        printf '# Uncomment anything you want to keep; the repo shell config already\n'
        printf '# covers the distro defaults (prompt, completion, history, cargo, ...).\n\n'
        sed 's/^/# /' "$bak"
    } >"$localfile"
}

case "$OS" in
    Darwin) install_macos ;;
    Linux)  install_linux
            install_nerd_font_linux
            configure_ptyxis ;;
    *)      die "Unsupported OS: $OS" ;;
esac

setup_git_credential_helper
stow_packages
seed_local_from_backup "$HOME/.bashrc.bak" "$HOME/.bashrc.local"
seed_local_from_backup "$HOME/.zshrc.bak" "$HOME/.zshrc.local"

info "Done."
