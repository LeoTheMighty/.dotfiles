realpath () {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}
cd "$(dirname "$(realpath "$0")")"; # cd into script directory

for file in ".*";
do
    if [ "$file" != ".git" ] && [ "$file" != ".gitignore" ]; then
        rm ../$file
    fi
done
