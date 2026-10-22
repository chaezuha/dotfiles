#!/usr/bin/env bash
# Run with /bin/bash tests/install_test.sh. No package installs or real-home writes.
# Function overrides are called indirectly by the sourced installer, and some
# stub commands the installer only runs through sudo (which is stubbed too).
# shellcheck disable=SC2329,SC2032
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
REAL_GIT="$(command -v git)"
REAL_STOW="$(command -v stow)"
TEST_PATH="$PATH"
# Keep the agent socket below Unix-domain socket path length limits on macOS.
TEST_ROOT="$(mktemp -d /tmp/dotfiles-tests.XXXXXX)"
TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
trap 'rm -rf "$TEST_ROOT"' EXIT
# shellcheck source=../install.sh
source "$REPO/install.sh"

assert() {
    if ! "$@"; then
        printf 'FAIL: %s\n' "$*" >&2
        exit 1
    fi
}

expect_failure() {
    if "$@"; then
        printf 'FAIL: expected failure: %s\n' "$*" >&2
        exit 1
    fi
}

fixture() {
    local name="$1"
    mkdir -p "$TEST_ROOT/$name/home" "$TEST_ROOT/$name/repo/shell" "$TEST_ROOT/$name/tmp"
    cd "$TEST_ROOT/$name/repo"
    export HOME="$TEST_ROOT/$name/home" TMPDIR="$TEST_ROOT/$name/tmp"
    export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
    export XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
    export PATH="$TEST_PATH" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_CONFIG_COUNT
    unset GIT_CONFIG_PARAMETERS SSH_AUTH_SOCK SSH_AGENT_PID NVIM_APPNAME VIMINIT EXINIT
    # Running the suite inside a distrobox must not switch install modes.
    unset CONTAINER_ID DISTROBOX_HOST_HOME
    export GIT_TERMINAL_PROMPT=0 GIT_AUTHOR_NAME=Audit GIT_AUTHOR_EMAIL=audit@example.invalid
    export GIT_COMMITTER_NAME=Audit GIT_COMMITTER_EMAIL=audit@example.invalid
    printf '# repo shell\n' >shell/.zshrc
    printf '# current personal settings\n' >"$HOME/.zshrc"
    STOW_PACKAGES=(shell)
    ZSHRC_BACKUP=""
}

assert_no_probe() {
    local paths=("$TMPDIR"/dotfiles-signing.*)
    assert test "${#paths[@]}" -eq 1
    assert test "${paths[0]}" = "$TMPDIR/dotfiles-signing.*"
}

test_source_helpers() {
    # Also detect accidentally enabling options that the caller had disabled.
    set +e
    set +u
    set +o pipefail
    local cwd="$PWD" options="$-" shellopts="$SHELLOPTS"
    local OS=untouched DELTA_VERSION=untouched STOW_PACKAGES=(untouched)
    source "$REPO/install.sh"
    assert test "$PWD" = "$cwd"
    assert test "$-" = "$options"
    assert test "$SHELLOPTS" = "$shellopts"
    assert test "$OS" = untouched
    assert test "$DELTA_VERSION" = untouched
    assert test "${STOW_PACKAGES[0]}" = untouched
}

test_backup_seed_and_rerun() {
    # Force both the initial and timestamped names to be occupied.
    date() { printf '20000101000000\n'; }
    ln -s "$HOME/missing" "$HOME/.zshrc.bak"
    printf 'older backup\n' >"$HOME/.zshrc.bak.20000101000000"
    mkdir "$HOME/.zshrc.bak.20000101000000.1"
    stow_packages
    assert test "$ZSHRC_BACKUP" = "$HOME/.zshrc.bak.20000101000000.2"
    assert test -L "$HOME/.zshrc.bak"
    assert test -d "$HOME/.zshrc.bak.20000101000000.1"
    assert grep -qx 'older backup' "$HOME/.zshrc.bak.20000101000000"
    assert test -L "$HOME/.zshrc"
    umask 022
    seed_local_from_backup "$ZSHRC_BACKUP" "$HOME/.zshrc.local"
    assert grep -qx '# # current personal settings' "$HOME/.zshrc.local"
    local mode
    mode="$(stat -f %Lp "$HOME/.zshrc.local" 2>/dev/null)" || mode="$(stat -c %a "$HOME/.zshrc.local")"
    assert test "$mode" = 600
    cp "$HOME/.zshrc.local" "$HOME/expected"
    seed_local_from_backup "$ZSHRC_BACKUP" "$HOME/.zshrc.local"
    assert cmp "$HOME/expected" "$HOME/.zshrc.local"
    stow_packages
    assert test -z "$ZSHRC_BACKUP"
    rm "$HOME/.zshrc.local"
    seed_local_from_backup "$ZSHRC_BACKUP" "$HOME/.zshrc.local"
    assert test ! -e "$HOME/.zshrc.local"
}

test_stale_regular_backup() {
    printf 'stale settings\n' >"$HOME/.zshrc.bak"
    stow_packages
    seed_local_from_backup "$ZSHRC_BACKUP" "$HOME/.zshrc.local"
    assert grep -qx 'stale settings' "$HOME/.zshrc.bak"
    assert grep -qx '# # current personal settings' "$HOME/.zshrc.local"
}

test_seed_destinations_and_failure() {
    ln -s "$HOME/nonexistent" "$HOME/.zshrc.local"
    seed_local_from_backup "$HOME/.zshrc" "$HOME/.zshrc.local"
    assert test -L "$HOME/.zshrc.local"
    assert test ! -e "$HOME/nonexistent"
    rm "$HOME/.zshrc.local"
    # Bypass the preliminary occupancy check to exercise noclobber itself.
    path_exists() { return 1; }
    ln -s "$HOME/nonexistent" "$HOME/.zshrc.local"
    expect_failure seed_local_from_backup "$HOME/.zshrc" "$HOME/.zshrc.local"
    assert test -L "$HOME/.zshrc.local"
    assert test ! -e "$HOME/nonexistent"
    rm "$HOME/.zshrc.local"
    sed() { printf 'partial output\n'; return 1; }
    expect_failure seed_local_from_backup "$HOME/.zshrc" "$HOME/.zshrc.local"
    assert test ! -e "$HOME/.zshrc.local"
    assert test -f "$HOME/.zshrc"
}

test_no_clobber_results() {
    local skipped_status
    for skipped_status in 0 1; do
        mv() { return "$skipped_status"; }
        printf 'existing\n' >"$HOME/destination"
        expect_failure move_without_clobbering "$HOME/.zshrc" "$HOME/destination"
        assert grep -qx 'existing' "$HOME/destination"
        assert test -f "$HOME/.zshrc"
    done
    mv() { command mv "$@"; return 1; }
    move_without_clobbering "$HOME/.zshrc" "$HOME/new-backup"
    assert test ! -e "$HOME/.zshrc"
    assert test -f "$HOME/new-backup"
}

test_unresolved_conflict() {
    printf 'repo\n' >shell/.other
    printf 'external\n' >"$HOME/external"
    ln -s "$HOME/external" "$HOME/.other"
    expect_failure stow_packages
    assert test -f "$HOME/.zshrc"
    assert test ! -L "$HOME/.zshrc"
    assert test ! -e "$HOME/.zshrc.bak"
    assert test -z "$ZSHRC_BACKUP"
    assert test -L "$HOME/.other"
}

test_backup_failure_rollback() {
    printf 'second\n' >shell/.other
    printf 'second original\n' >"$HOME/.other"
    local move_count=0
    mv() {
        move_count=$((move_count+1))
        if [ "$move_count" -eq 2 ]; then return 0; fi
        command mv "$@"
    }
    expect_failure stow_packages
    assert test -f "$HOME/.zshrc"
    assert test ! -L "$HOME/.zshrc"
    assert grep -qx 'second original' "$HOME/.other"
    assert test ! -e "$HOME/.zshrc.bak"
    assert test ! -e "$HOME/.other.bak"
    assert test -z "$ZSHRC_BACKUP"
}

test_apply_failure_rollback() {
    stow() {
        case " $* " in
            *' --simulate '*) "$REAL_STOW" "$@" ;;
            *) return 1 ;;
        esac
    }
    expect_failure stow_packages
    assert test -f "$HOME/.zshrc"
    assert test ! -L "$HOME/.zshrc"
    assert test ! -e "$HOME/.zshrc.bak"
    assert test -z "$ZSHRC_BACKUP"
}

test_partial_apply_retains_backup() {
    stow() {
        case " $* " in
            *' --simulate '*) "$REAL_STOW" "$@" ;;
            *) ln -s "$PWD/shell/.zshrc" "$HOME/.zshrc"; return 1 ;;
        esac
    }
    expect_failure stow_packages 2>"$HOME/recovery.log"
    assert test -L "$HOME/.zshrc"
    assert grep -qx '# current personal settings' "$HOME/.zshrc.bak"
    assert grep -F "$HOME/.zshrc.bak" "$HOME/recovery.log"
    assert grep -F "remove the symlink at $HOME/.zshrc" "$HOME/recovery.log"
    assert test -z "$ZSHRC_BACKUP"
}

test_zprofile_backup() {
    printf '# repo profile\n' >shell/.zprofile
    printf 'export LOGIN_ONLY=1\n' >"$HOME/.zprofile"
    stow_packages
    assert test -L "$HOME/.zprofile"
    assert test "$ZPROFILE_BACKUP" = "$HOME/.zprofile.bak"
    assert test "$ZSHRC_BACKUP" = "$HOME/.zshrc.bak"
    seed_local_from_backup "$ZPROFILE_BACKUP" "$HOME/.zprofile.local"
    assert grep -qx '# export LOGIN_ONLY=1' "$HOME/.zprofile.local"
    expect_failure grep -q 'current personal settings' "$HOME/.zprofile.local"
}

test_stow_ignored_not_backed_up() {
    # Stow's default ignore list never links .gitignore, so backing it up
    # would leave nothing in its place.
    printf 'repo ignore\n' >shell/.gitignore
    printf 'personal ignore\n' >"$HOME/.gitignore"
    stow_packages
    assert test -L "$HOME/.zshrc"
    assert test ! -L "$HOME/.gitignore"
    assert grep -qx 'personal ignore' "$HOME/.gitignore"
    assert test ! -e "$HOME/.gitignore.bak"
}

test_credential_helper() {
    local OS=Linux exec_dir="$HOME/git-core"
    mkdir "$exec_dir"
    git() {
        if [ "$1" = --exec-path ]; then printf '%s\n' "$exec_dir"; return; fi
        "$REAL_GIT" "$@"
    }
    # A hand-edited file without a trailing newline must stay valid.
    printf '[user]\n\temail = me@example.invalid' >"$HOME/.gitconfig.local"
    setup_git_credential_helper
    assert test "$(git config --file "$HOME/.gitconfig.local" credential.helper)" = cache
    assert test "$(git config --file "$HOME/.gitconfig.local" user.email)" = me@example.invalid
    rm "$HOME/.gitconfig.local"
    printf '#!/bin/sh\n' >"$exec_dir/git-credential-libsecret"
    chmod +x "$exec_dir/git-credential-libsecret"
    setup_git_credential_helper
    assert test "$(git config --file "$HOME/.gitconfig.local" credential.helper)" = libsecret
}

test_nvim_isolation() {
    if ! command -v nvim >/dev/null 2>&1; then
        printf 'SKIP: Neovim integration (nvim unavailable)\n'
        return
    fi
    mkdir -p "$XDG_CONFIG_HOME/nvim"
    printf 'vim.fn.writefile({"ran"}, vim.env.HOME .. "/nvim-marker")\n' >"$XDG_CONFIG_HOME/nvim/init.lua"
    local expected=0 actual=0
    nvim --headless -u NONE -i NONE -n -c 'if has("nvim-0.11.2") | q | else | cq | endif' || expected=$?
    nvim_is_current "$(command -v nvim)" || actual=$?
    assert test "$actual" -eq "$expected"
    assert test ! -e "$HOME/nvim-marker"
}

signing_config() {
    cp "$REPO/gitconfig/.gitconfig" "$HOME/.gitconfig"
}

test_signing_disabled_and_old_git() {
    signing_config
    mkdir "$HOME/bin"
    export AUDIT_REAL_GIT="$REAL_GIT" AUDIT_GIT_LOG="$HOME/git.log"
    cat >"$HOME/bin/git" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = --version ]; then echo 'git version 2.30.2'; exit; fi
printf '%s\n' "$*" >>"$AUDIT_GIT_LOG"
exec "$AUDIT_REAL_GIT" "$@"
STUB
    chmod +x "$HOME/bin/git"
    export PATH="$HOME/bin:$TEST_PATH"
    expect_failure validate_git_signing 2>"$HOME/error.log"
    assert grep -F 'requires Git 2.34' "$HOME/error.log"
    assert_no_probe
    git config --file "$HOME/.gitconfig.local" gpg.format openpgp
    git config --file "$HOME/.gitconfig.local" gpg.program "$HOME/missing-gpg"
    expect_failure validate_git_signing 2>"$HOME/error.log"
    assert grep -F 'commit-tree' "$HOME/git.log"
    expect_failure grep -F 'requires Git 2.34' "$HOME/error.log"
    assert_no_probe
    git config --file "$HOME/.gitconfig.local" commit.gpgsign false
    validate_git_signing
    assert_no_probe
}

test_real_signing() {
    signing_config
    expect_failure validate_git_signing
    assert_no_probe
    mkdir "$HOME/.ssh"
    ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/id_ed25519"
    local agent_env
    agent_env="$(ssh-agent -a "$TEST_ROOT/agent.sock" -s)"
    eval "$agent_env" >/dev/null
    trap 'ssh-agent -k >/dev/null 2>&1 || :' EXIT
    ssh-add "$HOME/.ssh/id_ed25519"
    validate_git_signing
    assert_no_probe
}

test_probe_setup_failure() {
    git() { return 1; }
    expect_failure validate_git_signing
    assert_no_probe
}

test_main_order() {
    # Test orchestration without package installation or touching the real repo.
    local events="$HOME/events" fixture_repo="$PWD"
    uname() { printf 'Darwin\n'; }
    install_macos() { cd "$fixture_repo"; STOW_PACKAGES=(shell); }
    setup_git_credential_helper() { printf 'credentials\n' >>"$events"; }
    validate_git_signing() {
        assert test -L "$HOME/.zshrc"
        assert grep -qx '# # current personal settings' "$HOME/.zshrc.local"
        printf 'signing\n' >>"$events"
        return 1
    }
    expect_failure main
    printf 'credentials\nsigning\n' >"$HOME/expected"
    assert cmp "$HOME/expected" "$events"
}

test_zshrc_sources_local() {
    if ! command -v zsh >/dev/null 2>&1; then
        printf 'SKIP: zshrc load check (zsh unavailable)\n'
        return
    fi
    # Isolate the tools/plugins outside the config under test.
    cat >"$HOME/check.zsh" <<'ZSH'
function command() { return 1; }
function autoload() { return 1; }
function test() { builtin test "$@"; }
function '['() {
    if [[ "$2" == /opt/homebrew/* || "$2" == /usr/share/* ]]; then return 1; fi
    builtin [ "$@"
}
source "$1"
[[ "$LOCAL_TEST" == local ]] || exit 1
ZSH
    printf 'LOCAL_TEST=local\n' >"$HOME/.zshrc.local"
    zsh -f "$HOME/check.zsh" "$REPO/shell/.zshrc" 2>"$HOME/zsh.log"
    assert test ! -s "$HOME/zsh.log"
}

# Stubs for commands a mode must never run: record the call and fail.
forbidden() {
    printf 'forbidden: %s\n' "$*" >>"$HOME/forbidden"
    return 1
}

# Print a PATH holding only the named commands, so "not found" checks can't
# reach whatever is installed on the machine running the suite.
bare_path() {
    local cmd
    mkdir -p "$HOME/bare"
    for cmd in "$@"; do
        ln -sf "$(command -v "$cmd")" "$HOME/bare/$cmd"
    done
    printf '%s\n' "$HOME/bare"
}

test_detect_environment() {
    local ostree=1
    is_ostree_booted() { return "$ostree"; }
    assert test "$(detect_environment)" = normal
    ostree=0
    assert test "$(detect_environment)" = ostree-host
    # A box wins over the host check, whatever is visible from inside it.
    export CONTAINER_ID=main
    assert test "$(detect_environment)" = distrobox-shared
    export DISTROBOX_HOST_HOME=/var/home/me
    assert test "$(detect_environment)" = distrobox-own
    ostree=1
    assert test "$(detect_environment)" = distrobox-own
}

test_ostree_host_main() {
    local events="$HOME/events"
    uname() { printf 'Linux\n'; }
    is_ostree_booted() { return 0; }
    sudo() { forbidden sudo "$@"; }
    dnf() { forbidden dnf "$@"; }
    rpm-ostree() { forbidden rpm-ostree "$@"; }
    stow() { forbidden stow "$@"; }
    chsh() { forbidden chsh "$@"; }
    install_linux() { forbidden install_linux; }
    set_default_shell_zsh() { forbidden set_default_shell_zsh; }
    setup_git_credential_helper() { forbidden setup_git_credential_helper; }
    stow_packages() { forbidden stow_packages; }
    validate_git_signing() { forbidden validate_git_signing; }
    export_nvim_to_host() { forbidden export_nvim_to_host; }
    unzip() { :; }
    fc-list() { :; }
    install_nerd_font_linux() { printf 'font\n' >>"$events"; }
    configure_ptyxis() { printf 'ptyxis\n' >>"$events"; }
    main >"$HOME/out.log"
    assert test ! -e "$HOME/forbidden"
    printf 'font\nptyxis\n' >"$HOME/expected"
    assert cmp "$HOME/expected" "$events"
    assert grep -F 'silverblue/host.sh' "$HOME/out.log"
    assert grep -F 'silverblue/assemble.sh' "$HOME/out.log"
    assert grep -F 'git() { command git -c core.pager=less -c interactive.diffFilter=cat "$@"; }' "$HOME/out.log"
    # Without unzip the font is skipped with a warning; Ptyxis still runs.
    rm "$events"
    unset -f unzip
    PATH="$(bare_path cat dirname)" main >/dev/null 2>"$HOME/err.log"
    assert grep -F 'skipping JetBrainsMono' "$HOME/err.log"
    printf 'ptyxis\n' >"$HOME/expected"
    assert cmp "$HOME/expected" "$events"
}

test_nerd_font_prunes_extra_faces() {
    local fontdir="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
    mkdir -p "$fontdir"
    touch "$fontdir/JetBrainsMonoNerdFont-Regular.ttf" \
        "$fontdir/JetBrainsMonoNerdFont-ThinItalic.ttf" \
        "$fontdir/JetBrainsMonoNerdFontMono-Regular.ttf"
    fc-list() { printf '%s: JetBrainsMono Nerd Font:style=Regular\n' "$fontdir/JetBrainsMonoNerdFont-Regular.ttf"; }
    fc-cache() { printf 'cache %s\n' "$*" >>"$HOME/events"; }
    curl() { forbidden curl "$@"; }
    install_nerd_font_linux >/dev/null
    assert test ! -e "$HOME/forbidden"
    assert test "$(ls "$fontdir")" = JetBrainsMonoNerdFont-Regular.ttf
    printf 'cache -f %s\n' "$fontdir" >"$HOME/expected"
    assert cmp "$HOME/expected" "$HOME/events"
}

test_nerd_font_installs_four_faces() {
    local fontdir="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
    fc-list() { :; }
    fc-cache() { :; }
    curl() { touch "$3"; }
    unzip() { printf '%s\n' "$@" >"$HOME/unzip-args"; }
    install_nerd_font_linux >/dev/null
    printf '%s\n' -oq JetBrainsMono.zip \
        JetBrainsMonoNerdFont-Regular.ttf JetBrainsMonoNerdFont-Bold.ttf \
        JetBrainsMonoNerdFont-Italic.ttf JetBrainsMonoNerdFont-BoldItalic.ttf \
        -d "$fontdir" >"$HOME/expected"
    sed 's|^.*/JetBrainsMono.zip$|JetBrainsMono.zip|' "$HOME/unzip-args" >"$HOME/actual"
    assert cmp "$HOME/expected" "$HOME/actual"
}

test_distrobox_main_modes() {
    local events="$HOME/events"
    uname() { printf 'Linux\n'; }
    is_ostree_booted() { return 1; }
    install_linux() { printf 'install\n' >>"$events"; }
    install_neovim_fallback() { :; }
    install_delta_fallback() { :; }
    set_default_shell_zsh() { printf 'shell\n' >>"$events"; }
    install_nerd_font_linux() { forbidden install_nerd_font_linux; }
    configure_ptyxis() { forbidden configure_ptyxis; }
    setup_git_credential_helper() { :; }
    stow_packages() { printf 'stow\n' >>"$events"; }
    link_box_home_paths() { printf 'links\n' >>"$events"; }
    export_nvim_to_host() { printf 'export\n' >>"$events"; }
    validate_git_signing() { printf 'signing\n' >>"$events"; }

    export CONTAINER_ID=main
    main >/dev/null
    printf 'install\nshell\nstow\nexport\nsigning\n' >"$HOME/expected"
    assert cmp "$HOME/expected" "$events"

    rm "$events"
    export CONTAINER_ID=dev DISTROBOX_HOST_HOME="$HOME/host"
    main >/dev/null
    printf 'links\ninstall\nshell\nstow\nsigning\n' >"$HOME/expected"
    assert cmp "$HOME/expected" "$events"
    assert test ! -e "$HOME/forbidden"
}

test_box_home_links() {
    local host repo
    host="$(cd "$HOME/.." && pwd -P)/host"
    repo="$(pwd -P)"
    mkdir -p "$host/.ssh"
    export DISTROBOX_HOST_HOME="$host"

    # The host has no Dev yet: warn and skip it.
    link_box_home_paths >/dev/null 2>"$HOME/err.log"
    assert test "$(readlink "$HOME/.ssh")" = "$host/.ssh"
    assert test "$(readlink "$HOME/dotfiles")" = "$repo"
    assert test ! -e "$HOME/Dev"
    assert test ! -L "$HOME/Dev"
    assert grep -F "$host/Dev does not exist" "$HOME/err.log"

    # Re-running changes nothing.
    link_box_home_paths >/dev/null 2>&1
    assert test "$(readlink "$HOME/.ssh")" = "$host/.ssh"
    assert test "$(readlink "$HOME/dotfiles")" = "$repo"
    assert test ! -L "$HOME/Dev"

    # Existing paths, even a dangling symlink, are never replaced.
    mkdir "$host/Dev"
    rm "$HOME/.ssh" "$HOME/dotfiles"
    ln -s "$HOME/nowhere" "$HOME/.ssh"
    mkdir "$HOME/Dev"
    printf 'mine\n' >"$HOME/Dev/marker"
    printf 'mine\n' >"$HOME/dotfiles"
    link_box_home_paths >/dev/null 2>&1
    assert test "$(readlink "$HOME/.ssh")" = "$HOME/nowhere"
    assert test ! -L "$HOME/Dev"
    assert grep -qx mine "$HOME/Dev/marker"
    assert grep -qx mine "$HOME/dotfiles"
}

test_export_nvim() {
    local dest="$HOME/.local/bin/nvim" log="$HOME/export.log"
    export CONTAINER_ID=main
    mkdir -p "$HOME/.local/bin" "$HOME/usr/bin" "$HOME/.local/opt/nvim/bin"
    printf '#!/bin/sh\necho real\n' >"$HOME/usr/bin/nvim"
    printf '#!/bin/sh\necho fallback\n' >"$HOME/.local/opt/nvim/bin/nvim"
    chmod +x "$HOME/usr/bin/nvim" "$HOME/.local/opt/nvim/bin/nvim"
    cp "$HOME/.local/opt/nvim/bin/nvim" "$HOME/fallback.orig"
    distrobox-export() { printf '%s\n' "$*" >>"$log"; }
    launcher() {
        printf '#!/bin/sh\n# distrobox_binary\n# name: %s\nexec /usr/bin/nvim "$@"\n' "$1" >"$dest"
        chmod +x "$dest"
    }

    # This box's own launcher comes first on PATH: skip it, export the real
    # binary to the explicit destination.
    launcher main
    export PATH="$HOME/.local/bin:$HOME/usr/bin:$TEST_PATH"
    export_nvim_to_host >/dev/null
    printf -- '--bin %s --export-path %s\n' "$HOME/usr/bin/nvim" "$HOME/.local/bin" >"$HOME/expected"
    assert cmp "$HOME/expected" "$log"

    # A fallback symlink at the destination is refused even though a
    # different nvim comes first on PATH, and its target is left alone.
    rm "$log" "$dest"
    ln -s "$HOME/.local/opt/nvim/bin/nvim" "$dest"
    export PATH="$HOME/usr/bin:$HOME/.local/bin:$TEST_PATH"
    export_nvim_to_host >/dev/null 2>"$HOME/err.log"
    assert test ! -e "$log"
    assert grep -F "not this box's nvim launcher" "$HOME/err.log"
    assert cmp "$HOME/fallback.orig" "$HOME/.local/opt/nvim/bin/nvim"

    # A dangling symlink is refused too.
    rm "$dest"
    ln -s "$HOME/missing" "$dest"
    export_nvim_to_host >/dev/null 2>&1
    assert test ! -e "$log"
    assert test ! -e "$HOME/missing"

    # So is a symlink to a valid launcher: distrobox would write through it.
    rm "$dest"
    launcher main
    mv "$dest" "$HOME/real-launcher"
    ln -s "$HOME/real-launcher" "$dest"
    cp "$HOME/real-launcher" "$HOME/launcher.orig"
    export_nvim_to_host >/dev/null 2>&1
    assert test ! -e "$log"
    assert cmp "$HOME/launcher.orig" "$HOME/real-launcher"

    # So are an unrelated file and another box's launcher.
    rm "$dest"
    printf 'not a launcher\n' >"$dest"
    cp "$dest" "$HOME/dest.orig"
    export_nvim_to_host >/dev/null 2>&1
    assert test ! -e "$log"
    assert cmp "$HOME/dest.orig" "$dest"
    launcher dev
    cp "$dest" "$HOME/dest.orig"
    export_nvim_to_host >/dev/null 2>&1
    assert test ! -e "$log"
    assert cmp "$HOME/dest.orig" "$dest"

    # Without distrobox-export it warns and carries on. The bare PATH hides
    # the real one every distrobox has in /usr/bin.
    rm "$dest"
    unset -f distrobox-export
    PATH="$(bare_path)" export_nvim_to_host >/dev/null 2>"$HOME/err.log"
    assert grep -F 'distrobox-export not found' "$HOME/err.log"
}

test_assemble_wrapper() {
    local script="$REPO/silverblue/assemble.sh" manifest="$REPO/distrobox.ini"
    local before home tmp
    mkdir "$HOME/bin"
    export AUDIT_DISTROBOX_LOG="$HOME/distrobox.log" AUDIT_DISTROBOX_COPY="$HOME/distrobox.ini"
    cat >"$HOME/bin/distrobox" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >"$AUDIT_DISTROBOX_LOG"
while [ $# -gt 0 ]; do
    if [ "$1" = --file ]; then cp "$2" "$AUDIT_DISTROBOX_COPY"; fi
    shift
done
STUB
    chmod +x "$HOME/bin/distrobox"
    export PATH="$HOME/bin:$TEST_PATH"
    before="$(cksum <"$manifest")"

    for home in /home/harley /var/home/harley; do
        rm -f "$AUDIT_DISTROBOX_LOG" "$AUDIT_DISTROBOX_COPY"
        HOME="$home" "$BASH" "$script" --replace
        assert grep -qx "home=$home/distrobox/dev" "$AUDIT_DISTROBOX_COPY"
        expect_failure grep -q '@HOME@' "$AUDIT_DISTROBOX_COPY"
        tmp="$(sed -n 's/^assemble create --file \(.*\) --replace$/\1/p' "$AUDIT_DISTROBOX_LOG")"
        assert test -n "$tmp"
        assert test ! -e "$tmp"
    done
    rm -f "$AUDIT_DISTROBOX_LOG"

    # Unsafe homes fail before a manifest is written or distrobox runs.
    # shellcheck disable=SC2016 # literal $ on purpose
    for home in '/home/har ley' '/home/a&b' '/home/$x' '/home/a;b' "/home/a'b" \
                '/home/a"b' 'home/relative' ''; do
        expect_failure env HOME="$home" "$BASH" "$script" 2>"$HOME/err.log"
        assert grep -F 'Unsupported home path' "$HOME/err.log"
    done
    expect_failure env -u HOME "$BASH" "$script" 2>"$HOME/err.log"
    assert grep -F "Unsupported home path '<unset or empty>'" "$HOME/err.log"
    # In a UTF-8 locale A-Za-z can match accented letters; the check must not.
    expect_failure env LC_ALL=en_US.UTF-8 HOME=/home/hárley "$BASH" "$script" 2>"$HOME/err.log"
    assert grep -F 'Unsupported home path' "$HOME/err.log"
    assert test ! -e "$AUDIT_DISTROBOX_LOG"
    assert test -z "$(find "$TMPDIR" -name 'distrobox.*')"

    expect_failure env CONTAINER_ID=main HOME=/home/harley "$BASH" "$script" 2>"$HOME/err.log"
    assert grep -F 'not inside a distrobox' "$HOME/err.log"
    assert test ! -e "$AUDIT_DISTROBOX_LOG"

    # A bare PATH, so a real distrobox on this machine is never run.
    expect_failure env PATH="$(bare_path dirname)" HOME=/home/harley "$BASH" "$script" 2>"$HOME/err.log"
    assert grep -F 'distrobox not found: run silverblue/host.sh and reboot first' "$HOME/err.log"

    assert test "$(cksum <"$manifest")" = "$before"
}

test_env_drops_host_bin_in_own_box() {
    local host="$HOME/host" box="$HOME/box" shell got
    local start="$host/.local/bin:$HOME/boxbin::/usr/bin:/bin"
    mkdir -p "$box"
    # shellcheck disable=SC2016 # expands in the child shell
    local check='. "$1" && printf "%s\n" "$PATH"'

    # Checks PATH entries rather than which nvim wins: env.sh may also put
    # Homebrew first on the machine running the suite.
    for shell in sh zsh; do
        if ! command -v "$shell" >/dev/null 2>&1; then
            printf 'SKIP: env.sh PATH check under %s (unavailable)\n' "$shell"
            continue
        fi
        shell="$(command -v "$shell")"
        # Inside an own-home box, the host's ~/.local/bin (main's launchers)
        # is dropped; the rest of the inherited PATH is kept.
        got=":$(env HOME="$box" DISTROBOX_HOST_HOME="$host" PATH="$start" \
                    "$shell" -c "$check" sh "$REPO/shell/.config/shell/env.sh"):"
        expect_failure grep -qF ":$host/.local/bin:" <<<"$got"
        assert grep -qF ":$box/.local/bin:" <<<"$got"
        assert grep -qF ":$HOME/boxbin:/usr/bin:/bin:" <<<"$got"
        # Outside one (host, shared-home box), ~/.local/bin is left alone.
        got=":$(env -u DISTROBOX_HOST_HOME HOME="$host" PATH="$start" \
                    "$shell" -c "$check" sh "$REPO/shell/.config/shell/env.sh"):"
        assert grep -qF ":$host/.local/bin:$HOME/boxbin:" <<<"$got"
    done
}

test_host_script_refuses() {
    mkdir "$HOME/bin"
    # shellcheck disable=SC2016 # expands in the stub, not here
    printf '#!/bin/sh\necho called >>"$HOME/called"\n' >"$HOME/bin/sudo"
    cp "$HOME/bin/sudo" "$HOME/bin/rpm-ostree"
    chmod +x "$HOME/bin/sudo" "$HOME/bin/rpm-ostree"
    # host.sh can't be made to miss /run/ostree-booted, so the plain refusal
    # is only checkable off an rpm-ostree host.
    if [ ! -e /run/ostree-booted ]; then
        expect_failure env PATH="$HOME/bin:$TEST_PATH" "$BASH" "$REPO/silverblue/host.sh" 2>"$HOME/err.log"
        assert grep -F 'rpm-ostree host' "$HOME/err.log"
    fi
    expect_failure env CONTAINER_ID=main PATH="$HOME/bin:$TEST_PATH" "$BASH" "$REPO/silverblue/host.sh" 2>/dev/null
    assert test ! -e "$HOME/called"
}

for test_name in \
    test_source_helpers test_backup_seed_and_rerun test_stale_regular_backup \
    test_seed_destinations_and_failure test_no_clobber_results \
    test_unresolved_conflict test_backup_failure_rollback test_apply_failure_rollback \
    test_partial_apply_retains_backup test_zprofile_backup \
    test_stow_ignored_not_backed_up test_credential_helper test_nvim_isolation \
    test_signing_disabled_and_old_git test_real_signing test_probe_setup_failure \
    test_main_order test_zshrc_sources_local \
    test_detect_environment test_ostree_host_main \
    test_nerd_font_prunes_extra_faces test_nerd_font_installs_four_faces \
    test_distrobox_main_modes \
    test_box_home_links test_export_nvim test_assemble_wrapper \
    test_env_drops_host_bin_in_own_box test_host_script_refuses; do
    (
        fixture "$test_name"
        "$test_name"
    ) >"$TEST_ROOT/output.log" 2>&1 &
    test_pid=$!
    # Wait explicitly so the test subshell retains errexit semantics.
    if wait "$test_pid"; then
        printf 'PASS: %s\n' "$test_name"
        sed -n '/^SKIP:/p' "$TEST_ROOT/output.log"
    else
        cat "$TEST_ROOT/output.log" >&2
        printf 'FAIL: %s\n' "$test_name" >&2
        exit 1
    fi
done
