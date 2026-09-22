# Interactive zsh configuration. Shared (POSIX) config lives in
# ~/.config/shell/; machine-specific overrides in ~/.zshrc.local.

# --- Shared config (env first: brew shellenv sets HOMEBREW_PREFIX) ---
# Login shells already ran env.sh from .zprofile; running it again would put
# Homebrew back in front of ~/.local/bin.
if [[ ! -o login ]] && [ -f "$HOME/.config/shell/env.sh" ]; then
    . "$HOME/.config/shell/env.sh"
fi
[ -f "$HOME/.config/shell/aliases.sh" ] && . "$HOME/.config/shell/aliases.sh"
# Nested shells (tmux, subshells) inherit PATH and prepend again; keep one copy.
typeset -U path fpath

# Rust toolchain (rustup). Keeping the literal `. "$HOME/.cargo/env"` line
# here also stops rustup's installer from appending its own copy.
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# --- History ---
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt share_history hist_ignore_dups hist_ignore_space

# --- Completion ---
autoload -Uz compinit && compinit
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' menu select

# --- Prompt ---
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
else
    # Apple's /etc/zshrc default, so machines without starship still match.
    PROMPT='%n@%m %1~ %% '
fi

# --- Tools ---
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
if command -v fzf >/dev/null 2>&1; then
    if _fzf_init="$(fzf --zsh 2>/dev/null)"; then
        eval "$_fzf_init"
    elif [ -f /usr/share/fzf/shell/key-bindings.zsh ]; then
        # Older fzf packages predate `fzf --zsh`; Fedora/RHEL keep the
        # bindings here...
        . /usr/share/fzf/shell/key-bindings.zsh
    elif [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
        # ...and Debian/Ubuntu here.
        . /usr/share/doc/fzf/examples/key-bindings.zsh
    fi
    unset _fzf_init
fi

# Unity CLI (optional, like the Rust toolchain above).
[ -f "$HOME/.unity/env" ] && . "$HOME/.unity/env"

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

# Syntax highlighting must come after every other plugin and widget
# (fzf, zoxide, ...), so it can wrap them.
_source_first \
    "${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
    /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

unfunction _source_first

# --- Machine-specific overrides, always last ---
if [ -f "$HOME/.zshrc.local" ]; then
    . "$HOME/.zshrc.local"
fi
