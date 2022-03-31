
# for file in ~/.dotfiles/*
# do
    # base=$(basename $file)
    # echo $base
# done


while IFS="" read -r p || [ -n "$p" ]
do
    if [[ "$p" != "" ]]; then
        printf '%s\n' "$p"
    fi
done < test
