for file in .*;
do
    if [ "$file" != ".git" ]; then
        echo $file
        diff $file ../$file
    fi
done
