realpath () {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}
cd "$(dirname "$(realpath "$0")")"; # cd into script directory

# Keep in sync with update.sh
tracked_paths=(
    ".claude/commands"
    ".claude/hooks"
    ".oh-my-zsh/custom/themes/cobalt2.zsh-theme"
    ".config/starship.toml"
    ".config/git/ignore"
    ".config/gh/config.yml"
    ".ssh/config"
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
    # NB: do not name the loop var `path` — see comment in update.sh.
    for tracked in "${tracked_paths[@]}"; do
        if [ -d "$tracked" ]; then
            for f in "$tracked"/*; do
                [ -f "$f" ] || continue
                check_file "$f" || break 2
            done
        elif [ -f "$tracked" ]; then
            check_file "$tracked" || break
        fi
    done
fi

cd -
exit $exit_code
