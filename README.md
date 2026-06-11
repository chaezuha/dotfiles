# My dotfiles
Some of my configs, managed with stow

## General Structure
The top-level folders are stow packages that will get mirrored into Home
  e.g: gitconfig/.gitconfig -> ~./gitconfig

## Setup 
  Install stow
  git clone this repo to the desired folder
  `stow foldername` for each desired package

## Notes
  To remove a package's links:
  `stow -D foldername`
