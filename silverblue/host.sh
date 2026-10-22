#!/usr/bin/env bash
# One-time host setup for Fedora Silverblue (and other rpm-ostree systems):
# layers distrobox, which is the only package the host needs. Safe to re-run.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail
# shellcheck source=../install.sh
source "$(dirname "${BASH_SOURCE[0]}")/../install.sh"

[ "$(detect_environment)" = ostree-host ] ||
    die "Run this on an rpm-ostree host (e.g. Fedora Silverblue), not inside a container or on a regular distro."

if command -v distrobox >/dev/null 2>&1; then
    info "distrobox already installed"
else
    info "Layering distrobox with rpm-ostree"
    sudo rpm-ostree install --idempotent distrobox
fi

cat <<'STEPS'

Next steps (if you haven't yet, run ./install.sh on the host first: the boxes
skip the font and Ptyxis setup):
  1. Reboot (only needed if distrobox was just layered)
  2. ./silverblue/assemble.sh
  3. distrobox enter main, then: ~/dotfiles/install.sh
  4. distrobox enter dev, then:  "$DISTROBOX_HOST_HOME/dotfiles/install.sh"
STEPS
