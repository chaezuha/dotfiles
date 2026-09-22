#!/usr/bin/env bash
# Run with /bin/bash tests/install_test.sh. No package installs or real-home writes.
# Function overrides are called indirectly by the sourced installer.
# shellcheck disable=SC2329
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

test_unity_optional_and_local_last() {
    if ! command -v zsh >/dev/null 2>&1; then
        printf 'SKIP: Unity integration (zsh unavailable)\n'
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
[[ "$UNITY_TEST" == local ]] || exit 1
ZSH
    printf 'UNITY_TEST=local\n' >"$HOME/.zshrc.local"
    zsh -f "$HOME/check.zsh" "$REPO/shell/.zshrc" 2>"$HOME/zsh.log"
    assert test ! -s "$HOME/zsh.log"
    mkdir "$HOME/.unity"
    cat >"$HOME/.unity/env" <<'UNITY'
UNITY_TEST=unity
printf loaded >"$HOME/unity-marker"
UNITY
    zsh -f "$HOME/check.zsh" "$REPO/shell/.zshrc" 2>"$HOME/zsh.log"
    assert test ! -s "$HOME/zsh.log"
    assert test -f "$HOME/unity-marker"
}

for test_name in \
    test_source_helpers test_backup_seed_and_rerun test_stale_regular_backup \
    test_seed_destinations_and_failure test_no_clobber_results \
    test_unresolved_conflict test_backup_failure_rollback test_apply_failure_rollback \
    test_partial_apply_retains_backup test_zprofile_backup \
    test_stow_ignored_not_backed_up test_credential_helper test_nvim_isolation \
    test_signing_disabled_and_old_git test_real_signing test_probe_setup_failure \
    test_main_order test_unity_optional_and_local_last; do
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
