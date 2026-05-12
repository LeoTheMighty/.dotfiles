editcommit=$1

dir="$HOME/.dotfiles"

# Nested paths (relative to $dir / $HOME) to mirror. Each entry is
# either a directory (every file inside it is synced — non-recursive)
# or a single file path. Top-level dotfiles are still globbed; this
# list covers nested locations the top-level glob misses.
tracked_paths=(
    ".claude/commands"
    ".claude/hooks"
    ".oh-my-zsh/custom/themes/cobalt2.zsh-theme"
    ".config/starship.toml"
    ".config/git/ignore"
    ".config/gh/config.yml"
    ".ssh/config"
)
# Note: Brewfile lives at repo root but isn't in tracked_paths — it's a
# one-way artifact, regenerate with `brew bundle dump --force` from
# inside ~/.dotfiles when you want to refresh, then commit.

# Files that exist in the repo with secrets redacted (e.g. PATs replaced
# by <REPLACE_WITH_NEW_GITHUB_PAT>). The local ~/ version has the real
# secret, so naïve sync would publish it. Skip them entirely — on a
# fresh machine, copy once manually and substitute the real secret.
skip_sync=(
    ".gitconfig"
    ".npmrc"
    ".gemrc"
)

cd $dir

# Sync a single tracked file (path is relative to $dir and $HOME).
sync_file() {
    local relpath="$1"
    # NB: variable was previously named `local`, which shadowed the zsh
    # `local` keyword and silently broke this function for any relpath
    # containing a slash (i.e. all nested files). Don't rename back.
    local home_file="$HOME/$relpath"
    local repo="$dir/$relpath"
    local backup="$dir/backup/$relpath"

    for skip in "${skip_sync[@]}"; do
        if [ "$relpath" = "$skip" ]; then
            return
        fi
    done

    if [ ! -e "$home_file" ]; then
        echo "Skipping $relpath: missing in ~/"
        return
    fi

    git diff -s --exit-code "$repo"
    local gitdiff="$?"
    diff -q "$home_file" "$repo"
    # `localdiff="$status"` was a long-standing bug under zsh: $status
    # is a read-only special parameter (mirrors $?) that can't be
    # assigned to, so this assignment silently failed and localdiff was
    # always empty, making the "local differs" branches dead code.
    local localdiff="$?"

    local place=""
    if [[ "$localdiff" == "1" ]]; then
        if [[ "$gitdiff" == "1" ]]; then
            mkdir -p "$(dirname "$backup")"
            cp "$home_file" "$backup"
            local tmp="$dir/tmp"
            cp "$repo" "$tmp"
            cp "$home_file" "$repo"
            git diff -s --exit-code "$repo"
            local localtogitdiff="$?"
            echo "Updating $home_file from $repo:"
            cp "$tmp" "$repo"
            rm "$tmp"
            cp "$repo" "$home_file"
            if [[ "$localtogitdiff" == "1" ]]; then
                echo "!!!CHANGES IN BOTH REPO AND LOCAL!!!"
                echo "This probably means you updated both files."
                echo "Check the local backup in $backup"
                echo "The version in $repo was saved to $home_file"
            fi
            place="repo"
        else
            echo "Updating $home_file from $repo"
            cp "$home_file" "$repo"
            place="local"
        fi
    fi

    if [[ "$localdiff" == "1" ]] || [[ "$gitdiff" == "1" ]]; then
        echo "Updating git repo from $place changes"
        echo "-------------------------------------"
        git add "$repo"
        git commit -m "Update $relpath from $place changes"
        if [[ "$editcommit" != "" ]]; then
            git commit --amend
        fi
        git push
    fi
}

# Top-level dotfiles in ~/.dotfiles
for file in $dir/.*;
do
    [ -e "$file" ] || continue
    [ -d "$file" ] && continue  # subdirs handled explicitly below
    file=$(basename $file)
    if [ "$file" != ".git" ] && [ "$file" != ".gitignore" ]; then
        sync_file "$file"
    fi
done

# Tracked nested paths — directory entries are walked (non-recursive),
# file entries are synced directly.
# NB: do not name the loop var `path` — in zsh, $path is a special
# array tied to $PATH, and assigning to it wipes the executable search
# path mid-loop, causing later `git`/`diff` calls to fail with
# "command not found".
for tracked in "${tracked_paths[@]}"; do
    if [ -d "$dir/$tracked" ]; then
        for f in "$dir/$tracked"/*; do
            [ -f "$f" ] || continue
            sync_file "${f#$dir/}"
        done
    elif [ -f "$dir/$tracked" ]; then
        sync_file "$tracked"
    fi
done

cd ~-
