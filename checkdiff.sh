realpath () {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}
cd "$(dirname "$(realpath "$0")")"; # cd into script directory

# Keep in sync with update.sh
tracked_subdirs=(
    ".claude/commands"
    ".claude/hooks"
)
skip_sync=(
    ".gitconfig"
    ".npmrc"
    ".gemrc"
)

exit_code=0

check_file() {
    local relpath="$1"
    for skip in "${skip_sync[@]}"; do
        if [ "$relpath" = "$skip" ]; then
            return 0
        fi
    done
    diff -q "$relpath" "$HOME/$relpath"
    # Same $status zsh bug as update.sh — read $? instead.
    if [[ "$?" == "1" ]]; then
        diff "$relpath" "$HOME/$relpath"
        exit_code=1
        return 1
    fi
}

for file in .*;
do
    [ -e "$file" ] || continue
    [ -d "$file" ] && continue
    if [ "$file" != ".git" ] && [ "$file" != ".gitignore" ]; then
        check_file "$file" || break
    fi
done

if [[ "$exit_code" == "0" ]]; then
    for sub in "${tracked_subdirs[@]}"; do
        [ -d "$sub" ] || continue
        for f in "$sub"/*; do
            [ -f "$f" ] || continue
            check_file "$f" || break 2
        done
    done
fi

cd -
exit $exit_code
