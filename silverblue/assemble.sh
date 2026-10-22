#!/usr/bin/env bash
# Create the distroboxes from distrobox.ini. Fills in @HOME@ (distrobox 2.0 no
# longer expands $HOME in manifests) in a temporary copy, then runs
# `distrobox assemble create`. Extra arguments pass through, e.g. --replace.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail
SILVERBLUE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../install.sh
source "$SILVERBLUE_DIR/../install.sh"

# distrobox 1.x sources manifest values and evals the resulting command, so
# rather than escape the home path for several shell parsers, only allow a
# plain one. LC_ALL=C (scoped by the subshell) keeps the ranges ASCII-only.
home_path_is_safe() (
    LC_ALL=C
    case "$1" in
        "" | *[!A-Za-z0-9/._-]*) return 1 ;;
        /*) return 0 ;;
        *) return 1 ;;
    esac
)

assemble() {
    local manifest="$SILVERBLUE_DIR/../distrobox.ini" home="${HOME:-}"

    case "$(detect_environment)" in
        distrobox-*) die "Run this on the host, not inside a distrobox." ;;
    esac
    command -v distrobox >/dev/null 2>&1 ||
        die "distrobox not found: run silverblue/host.sh and reboot first."
    home_path_is_safe "$home" ||
        die "Unsupported home path '${home:-<unset or empty>}': it must be absolute and" \
            "contain only ASCII letters, digits, '/', '.', '_' and '-'."

    ASSEMBLE_TMP="$(mktemp "${TMPDIR:-/tmp}/distrobox.XXXXXX")"
    trap 'rm -f "$ASSEMBLE_TMP"' EXIT
    sed "s|@HOME@|$home|g" "$manifest" >"$ASSEMBLE_TMP"
    distrobox assemble create --file "$ASSEMBLE_TMP" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    assemble "$@"
fi
