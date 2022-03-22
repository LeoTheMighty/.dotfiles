realpath () {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}
cd "$(dirname "$(realpath "$0")")"; # cd into script directory

source checkdiff.sh

if [[ "$?" == "1" ]]; then
    echo "Differences detected, updating local files!"
    echo "putting backup files into '.dotfiles/backup/'"

    dir="~/.dotfiles"
    for file in "$dir/.*";
    do
        if [ "$file" != ".git" ] && [ "$file" != ".gitignore" ]; then
            mkdir -p "$dir/backup" && cp "~/$file" "$dir/backup/$file"
            # cp "$dir/$file" "~/$file"
        fi
    done
fi

