source checkdiff.sh

if [[ "$?" == "1" ]]; then
    echo "Differences detected, updating local files!"
    echo "putting backup files into '.dotfiles/backup/'"
    for file in .*;
    do
        if [ "$file" != ".git" ]; then
            mkdir -p backup && cp ../$file backup/$file
            cp $file ../$file
        fi
    done
fi

