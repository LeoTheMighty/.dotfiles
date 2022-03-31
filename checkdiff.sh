realpath () {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}
cd "$(dirname "$(realpath "$0")")"; # cd into script directory

exit_code=0
for file in .*;
do
    if [ "$file" != ".git" ] && [ "$file" != ".gitignore" ]; then
        diff -q "$file" "../$file"
        if [[ "$status" == "1" ]]; then
            diff "$file" "../$file"
            exit_code=1
            break
        fi
    fi
done

cd -
