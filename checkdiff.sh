for file in .*;
do
    if [ "$file" != ".git" ]; then
        echo $file
        diff -q $file ../$file
        echo $status
        if [[ "$status" -eq 1 ]]; then
            exit 1
        fi
    fi
done

exit 0
