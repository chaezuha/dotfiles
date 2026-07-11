# shellcheck shell=bash
# Interactive bash configuration. Shared (POSIX) config lives in
# ~/.config/shell/; machine-specific overrides in ~/.bashrc.local.

# Only run for interactive shells.
case $- in
    *i*) ;;
    *) return ;;
esac

# --- Shared config ---
[ -f "$HOME/.config/shell/env.sh" ] && . "$HOME/.config/shell/env.sh"
[ -f "$HOME/.config/shell/aliases.sh" ] && . "$HOME/.config/shell/aliases.sh"

# --- History ---
HISTCONTROL=ignoreboth
HISTSIZE=100000
HISTFILESIZE=100000
shopt -s histappend

# --- Behaviour ---
shopt -s checkwinsize
# globstar needs bash >= 4 (macOS ships 3.2).
shopt -s globstar 2>/dev/null || true

# --- Tools ---
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"
if command -v fzf >/dev/null 2>&1; then
    if fzf --bash >/dev/null 2>&1; then
        eval "$(fzf --bash)"
    elif [ -f /usr/share/doc/fzf/examples/key-bindings.bash ]; then
        # Older fzf packages (Debian/Ubuntu) predate `fzf --bash`.
        . /usr/share/doc/fzf/examples/key-bindings.bash
    fi
fi

# --- Machine-specific overrides, always last ---
if [ -f "$HOME/.bashrc.local" ]; then
    . "$HOME/.bashrc.local"
fi
