exit_code=0

for file in .*;
do
    if [ "$file" != ".git" ]; then
        # echo $file
        diff -q $file ../$file
        # echo "'$status'"
        if [[ "$status" == "1" ]]; then
            exit_code=1
            break
        fi
    fi
done

(exit $exit_code)
