editcommit=$1

dir="$HOME/.dotfiles"

# Subdirectory paths (relative to $dir / $HOME) whose files are tracked
# individually. Top-level dotfiles are still globbed; this list is for
# nested locations where a glob would be too coarse.
tracked_subdirs=(
    ".claude/commands"
    ".claude/hooks"
)

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
    local local="$HOME/$relpath"
    local repo="$dir/$relpath"
    local backup="$dir/backup/$relpath"

    for skip in "${skip_sync[@]}"; do
        if [ "$relpath" = "$skip" ]; then
            return
        fi
    done

    if [ ! -e "$local" ]; then
        echo "Skipping $relpath: missing in ~/"
        return
    fi

    git diff -s --exit-code "$repo"
    local gitdiff="$?"
    diff -q "$local" "$repo"
    # `localdiff="$status"` was a long-standing bug under zsh: $status
    # is a read-only special parameter (mirrors $?) that can't be
    # assigned to, so this assignment silently failed and localdiff was
    # always empty, making the "local differs" branches dead code.
    local localdiff="$?"

    local place=""
    if [[ "$localdiff" == "1" ]]; then
        if [[ "$gitdiff" == "1" ]]; then
            mkdir -p "$(dirname "$backup")"
            cp "$local" "$backup"
            local tmp="$dir/tmp"
            cp "$repo" "$tmp"
            cp "$local" "$repo"
            git diff -s --exit-code "$repo"
            local localtogitdiff="$?"
            echo "Updating $local from $repo:"
            cp "$tmp" "$repo"
            rm "$tmp"
            cp "$repo" "$local"
            if [[ "$localtogitdiff" == "1" ]]; then
                echo "!!!CHANGES IN BOTH REPO AND LOCAL!!!"
                echo "This probably means you updated both files."
                echo "Check the local backup in $backup"
                echo "The version in $repo was saved to $local"
            fi
            place="repo"
        else
            echo "Updating $local from $repo"
            cp "$local" "$repo"
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

# Tracked subdirs (file-by-file mirror)
for sub in "${tracked_subdirs[@]}"; do
    [ -d "$dir/$sub" ] || continue
    for f in "$dir/$sub"/*; do
        [ -f "$f" ] || continue
        sync_file "${f#$dir/}"
    done
done

cd ~-
