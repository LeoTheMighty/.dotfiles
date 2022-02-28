source checkdiff.sh

if [[ "$?" == "1" ]]; then
    echo "Differences detected, updating local files!"
    for file in .*;
    do
        if [ "$file" != ".git" ]; then
            cp $file ../$file
        fi
    done
fi

