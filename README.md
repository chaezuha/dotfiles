# My dotfiles

Some of my configs, managed with [GNU Stow](https://www.gnu.org/software/stow/).

## General structure

The top-level folders are Stow packages that get mirrored into `$HOME`.

For example: `gitconfig/.gitconfig` → `~/.gitconfig`

## Setup

1. Install Stow
2. Clone this repo to the desired folder:
```sh
   git clone <repo-url> ~/dotfiles
   cd ~/dotfiles
```
3. Run `stow <foldername>` for each desired package

## Notes

To remove a package's symlinks:

```sh
stow -D <foldername>
```
