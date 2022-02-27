for file in .*;
do
    if [ "$file" != ".git" ]; then
        cp $file ../$file
    fi
done
