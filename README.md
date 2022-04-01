# Leo's Dotfiles Repo
By Leo Belyi

## Dotfiles
Yeah basically I wanted a place to store a lot of my configurations/aliases so that switching between computers would at least keep some semblance of normalcy. I know that it's a turmulous time for me and I need some sense of solidity right now.

## How to use
You clone the repo to your machine under `~/.dotfiles`. How it works is it maintains both the `.dotfiles` and the `~` versions of the files and when you use the alias `udf` to update your dotfiles. It will handle both updating within `~/.dotfiles` or within `~` but if you update both, then it will always take the `~/.dotfiles` version, but it will store the backup of the `~` version in the `~/.dotfiles/backup/` folder.

## Aliases
I have a whole lot of custom aliases, but the important ones for this repo are these

`alias updatedf="source ~/.dotfiles/update.sh && source ~/.aliases.zsh"

and

`alias udf="vim ~/.aliases.zsh; updatedf"`

Whenever you have an alias you want to add, just use `udf` and you'll be able to pull up vim, add it, and then automatically source and then push it to your repo! Easy peasy.

Then, if you do it manually, just use `updatedf` in order to update it at your leisure.

## Customizing it
Basically whatever files are currently inside the repo, it will try to match that to the local versions outside of the repo, so if you want to fork this repo and make it your own, you would basically first copy all your dotfiles that you want to keep track of onto the repo, and then run the `updatedf` function and it should handle it.

## Ideas
* Use `git check-ignore` to see what's ignored and don't parse it?
* Make a custom file list that will dictate exactly what to track
