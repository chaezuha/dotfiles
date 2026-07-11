# shellcheck shell=bash
# Interactive bash configuration. Shared (POSIX) config lives in
# ~/.config/shell/; machine-specific overrides in ~/.bashrc.local.

# Only run for interactive shells.
case $- in
    *i*) ;;
    *) return ;;
esac

# --- Distro-wide defaults (Fedora/RHEL convention; no-op elsewhere) ---
# Fedora's bash reads no system rc for interactive shells; ~/.bashrc is
# expected to source /etc/bashrc (profile.d hooks, etc.) itself.
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# --- Shared config ---
[ -f "$HOME/.config/shell/env.sh" ] && . "$HOME/.config/shell/env.sh"
[ -f "$HOME/.config/shell/aliases.sh" ] && . "$HOME/.config/shell/aliases.sh"

# Rust toolchain (rustup). Keeping the literal `. "$HOME/.cargo/env"` line
# here also stops rustup's installer from appending its own copy.
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# --- History ---
HISTCONTROL=ignoreboth
HISTSIZE=100000
HISTFILESIZE=100000
shopt -s histappend

# --- Behaviour ---
shopt -s checkwinsize
# globstar needs bash >= 4 (macOS ships 3.2).
shopt -s globstar 2>/dev/null || true

# make less friendlier for non-text input (archives, images, ...)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# LS_COLORS for GNU ls; honors a user ~/.dircolors if present.
if command -v dircolors >/dev/null 2>&1; then
    if [ -r "$HOME/.dircolors" ]; then
        eval "$(dircolors -b "$HOME/.dircolors")"
    else
        eval "$(dircolors -b)"
    fi
fi

# --- Prompt (unified across machines; set after /etc/bashrc so it wins) ---
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi
PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
# Keep the terminal title at user@host:dir.
case "$TERM" in
    xterm*|rxvt*) PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1" ;;
esac

# --- Completion (Debian needs this; elsewhere it's a no-op or already loaded) ---
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

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

# Desktop notification after a long command: `sleep 10; alert`
command -v notify-send >/dev/null 2>&1 &&
    alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# --- Drop-in dirs / user hooks (Fedora and Debian conventions) ---
if [ -d "$HOME/.bashrc.d" ]; then
    for rc in "$HOME/.bashrc.d"/*; do
        # shellcheck source=/dev/null
        [ -f "$rc" ] && . "$rc"
    done
    unset rc
fi
[ -f "$HOME/.bash_aliases" ] && . "$HOME/.bash_aliases"

# --- Machine-specific overrides, always last ---
if [ -f "$HOME/.bashrc.local" ]; then
    . "$HOME/.bashrc.local"
fi
