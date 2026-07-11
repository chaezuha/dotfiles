# shellcheck shell=sh
# Shared environment for all shells. POSIX sh only.

export EDITOR=nvim
export VISUAL=nvim

# Default to a UTF-8 locale when the environment doesn't provide one
# (common over ssh and in minimal containers).
[ -n "${LANG:-}" ] || export LANG=en_US.UTF-8

# Homebrew (Apple Silicon, then Intel).
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
[ -x /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"

# User-installed binaries take precedence.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
esac
export PATH
