for file in .*;
do
    if [ "$file" != ".git" ]; then
        # echo $file
        diff -q $file ../$file
        # echo "'$status'"
        if [[ "$status" == "1" ]]; then
            false
            break
        fi
    fi
done

true
