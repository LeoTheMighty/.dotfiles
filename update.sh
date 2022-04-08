# realpath () {
  # [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
# }
# cd "$(dirname "$(realpath "$0")")"; # cd into script directory

editcommit=$1

dir="$HOME/.dotfiles"

cd $dir
for file in $dir/.*;
do
    [ -e "$file" ] || continue
    file=$(basename $file)
    if [ "$file" != ".git" ] && [ "$file" != ".gitignore" ]; then
        local="$HOME/$file"
        repo="$dir/$file"
        git diff -s --exit-code $repo
        gitdiff="$?"
        diff -q $local $repo
        localdiff="$status"
        backup="$dir/backup/$file"
        if [[ "$localdiff" == "1" ]]; then
            if [[ "$gitdiff" == "1" ]]; then
                cp $local $backup
                tmp="$dir/tmp"
                cp $repo $tmp
                cp $local $repo
                git diff -s --exit-code $repo
                localtogitdiff="$?"
                echo "Updating $local from $repo:"
                cp $tmp $repo
                rm $tmp
                cp $repo $local
                if [[ "$localtogitdiff" == "1" ]]; then
                    echo "!!!CHANGES IN BOTH REPO AND LOCAL!!!"
                    echo "This probably means you updated both files."
                    echo "Check the local backup in $backup"
                    echo "The version in $repo was saved to $local"
                fi
                place="repo"
            else
                echo "Updating $local from $repo"
                cp $local $repo
                place="local"
            fi
        fi

        if [[ "$localdiff" == "1" ]] || [[ "$gitdiff" == "1" ]]; then
            echo "Updating git repo from $place changes"
            echo "-------------------------------------"
            git add $repo
            git commit -m "Update $file from $place changes"
            if [[ "$editcommit" != "" ]]; then
                git commit --amend
            fi
            git push
        fi
    fi
done
cd ~-

# For each file

# Git is the source of truth!

# git diff -s --exit-code $file
# gitdiff="$?"

# diff -q $file1 $file2
# localdiff="$status"

# change between repo and git = $gitdiff
#       want to add to git (but keep track of this) = ga $repo; gcm -m "Update $file from repo changes"; git push origin main

# change between repo and local and not with git = $localdiff && !$gitdiff
#       update repo with local = cp $local $repo
#       then update git with repo = ga $repo; gcm -m "Update $file from local changes"; git push origin main
# and change in git = $localdiff && $gitdiff
#       update local with repo and save local in backup = cp $local $backup; cp $repo $local

# git diff -s --exit-code $file
# gitdiff="$?"
# diff -q $file1 $file2
# localdiff="$status"

# if $localdiff
#   if !$gitdiff
#     cp $local $repo
#     place="local"
#   else
#     echo "Updating backup
#     cp $local $backup #because not in the git repo
#     cp $repo $local
#     place="repo"
#   fi
# fi

# if $gitdiff || $localdiff
#   ga $repo; gcm "Update $file from $place changes"; gp
# fi

# cd ~-

