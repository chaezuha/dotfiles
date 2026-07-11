# Interactive zsh configuration. Shared (POSIX) config lives in
# ~/.config/shell/; machine-specific overrides in ~/.zshrc.local.

# --- Shared config (env first: brew shellenv sets HOMEBREW_PREFIX) ---
[ -f "$HOME/.config/shell/env.sh" ] && . "$HOME/.config/shell/env.sh"
[ -f "$HOME/.config/shell/aliases.sh" ] && . "$HOME/.config/shell/aliases.sh"

# --- History ---
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt share_history hist_ignore_dups hist_ignore_space

# --- Completion ---
autoload -Uz compinit && compinit
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' menu select

# --- Plugins ---
# Sourced only if installed (brew on macOS, distro packages on Linux).
_source_first() {
    local f
    for f in "$@"; do
        if [ -f "$f" ]; then
            . "$f"
            return 0
        fi
    done
    return 0
}

_source_first \
    "${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
    /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
    /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

# Syntax highlighting must be the last plugin sourced.
_source_first \
    "${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
    /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

unfunction _source_first

# --- Tools ---
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
if command -v fzf >/dev/null 2>&1; then
    if fzf --zsh >/dev/null 2>&1; then
        source <(fzf --zsh)
    elif [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
        # Older fzf packages (Debian/Ubuntu) predate `fzf --zsh`.
        . /usr/share/doc/fzf/examples/key-bindings.zsh
    fi
fi

# --- Machine-specific overrides, always last ---
if [ -f "$HOME/.zshrc.local" ]; then
    . "$HOME/.zshrc.local"
fi
