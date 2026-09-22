# Login-shell environment. Login sessions that never read .zshrc (graphical
# logins on Linux, IDEs, `zsh -l -c ...`) still get PATH and Homebrew here.
# .zshrc sources the same env.sh for interactive non-login shells.
[ -f "$HOME/.config/shell/env.sh" ] && . "$HOME/.config/shell/env.sh"

# --- Machine-specific overrides, always last ---
if [ -f "$HOME/.zprofile.local" ]; then
    . "$HOME/.zprofile.local"
fi
