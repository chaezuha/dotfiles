# shellcheck shell=sh
# Shared aliases for all shells. POSIX sh only.
# Aliases for optional tools are guarded so a missing tool never breaks a shell.

command -v nvim >/dev/null 2>&1 && alias vim='nvim'

alias ..='cd ..'
alias ...='cd ../..'

alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# BSD ls (macOS) colors with -G, GNU ls with --color.
if [ "$(uname -s)" = "Darwin" ]; then
    alias ls='ls -G'
else
    alias ls='ls --color=auto'
fi
alias ll='ls -lh'
alias la='ls -lha'

# Debian/Ubuntu package bat's binary as batcat, and fd's as fdfind.
# (install.sh also symlinks fdfind to ~/.local/bin/fd for non-shell tools.)
if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
    alias bat='batcat'
fi
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
    alias fd='fdfind'
fi
