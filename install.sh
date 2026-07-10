#!/usr/bin/env bash
# Install script for these dotfiles.
# Supported: macOS (Homebrew), Fedora/RHEL-family (dnf), Ubuntu (apt + Neovim PPA),
# Debian (apt), Arch (pacman). Safe to re-run.
set -euo pipefail

cd "$(dirname "$0")"

OS="$(uname -s)"
STOW_PACKAGES=(gitconfig nvim)

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

install_macos() {
    command -v brew >/dev/null 2>&1 ||
        die "Homebrew is required on macOS. Install it from https://brew.sh and re-run."

    info "Installing packages with Homebrew"
    local pkg
    for pkg in git stow neovim; do
        brew list "$pkg" >/dev/null 2>&1 || brew install "$pkg"
    done
    brew list --cask ghostty >/dev/null 2>&1 || brew install --cask ghostty

    STOW_PACKAGES+=(ghostty)
}

install_fedora() {
    info "Installing packages with dnf"
    sudo dnf install -y git stow neovim
}

install_ubuntu() {
    info "Installing packages with apt (Neovim from ppa:neovim-ppa/unstable)"
    sudo apt-get update
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y ppa:neovim-ppa/unstable
    sudo apt-get install -y git stow neovim
}

install_debian() {
    info "Installing packages with apt"
    sudo apt-get update
    sudo apt-get install -y git stow neovim
    if ! nvim --headless -c 'if has("nvim-0.10") | q | else | cq | endif' >/dev/null 2>&1; then
        warn "Installed Neovim is older than 0.10; the LazyVim config may not work." \
             "Consider installing a newer release from https://github.com/neovim/neovim/releases"
    fi
}

install_arch() {
    info "Installing packages with pacman"
    sudo pacman -S --needed --noconfirm git stow neovim
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
        *) die "Unsupported distribution '${ID:-unknown}'. Install git, stow, and neovim manually, then run: stow ${STOW_PACKAGES[*]}" ;;
    esac
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
    # Stow refuses to overwrite real files; move any conflicting regular file
    # (e.g. an existing hand-written ~/.gitconfig) out of the way first.
    # A path that resolves into this repo is already stowed (possibly via a
    # symlinked parent directory) and must be left alone — backing it up
    # would rename the repo's own files.
    local repo_dir pkg file target
    repo_dir="$(pwd -P)"
    for pkg in "${STOW_PACKAGES[@]}"; do
        while IFS= read -r file; do
            target="$HOME/${file#"$pkg"/}"
            if [ -f "$target" ] && [ ! -L "$target" ]; then
                case "$(realpath "$target")" in
                    "$repo_dir"/*) continue ;;
                esac
                warn "Backing up existing $target to $target.bak"
                mv "$target" "$target.bak"
            fi
        done < <(cd "$pkg" && find . -type f | sed "s|^\./|$pkg/|")
    done

    info "Stowing: ${STOW_PACKAGES[*]}"
    stow --restow "${STOW_PACKAGES[@]}"
}

case "$OS" in
    Darwin) install_macos ;;
    Linux)  install_linux ;;
    *)      die "Unsupported OS: $OS" ;;
esac

setup_git_credential_helper
stow_packages

info "Done."
