# shellcheck shell=bash
# Login shells (ssh, console) read .bash_profile and skip .bashrc;
# keep everything in .bashrc and just source it from here.
if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
