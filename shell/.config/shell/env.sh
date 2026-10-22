# shellcheck shell=sh
# Shared environment for all shells. POSIX sh only.

export EDITOR=nvim
export VISUAL=nvim

# Default to a UTF-8 locale when the environment doesn't provide one
# (common over ssh and in minimal containers).
[ -n "${LANG:-}" ] || export LANG=en_US.UTF-8

# Homebrew (Apple Silicon, then Intel).
# Only one: each shellenv prepends to PATH, so a second call would win.
if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# In a distrobox with its own home, PATH still carries the host's real
# ~/.local/bin, whose exported launchers forward to other boxes (main's nvim).
# Drop it so this box's own binaries win. Split by hand: zsh doesn't
# word-split $PATH.
if [ -n "${DISTROBOX_HOST_HOME:-}" ]; then
    _rest="$PATH:"
    _path=
    while [ -n "$_rest" ]; do
        _dir="${_rest%%:*}"
        _rest="${_rest#*:}"
        case "$_dir" in
            "$DISTROBOX_HOST_HOME/.local/bin" | "") ;;
            *) _path="${_path:+$_path:}$_dir" ;;
        esac
    done
    PATH="$_path"
    unset _rest _dir _path
fi

# User-installed binaries take precedence.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
esac
case ":$PATH:" in
    *":$HOME/bin:"*) ;;
    *) PATH="$HOME/bin:$PATH" ;;
esac
export PATH
