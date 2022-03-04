exit_code=0

cd "${0%/*}" # cd into script directory

for file in .*;
do
    if [ "$file" != ".git" ] && [ "$file" != ".gitignore" ]; then
        diff -q "$file" "~/$file"
        if [[ "$status" == "1" ]]; then
            exit_code=1
            break
        fi
    fi
done
(exit $exit_code)

cd -
