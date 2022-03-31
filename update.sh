realpath () {
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}
cd "$(dirname "$(realpath "$0")")"; # cd into script directory

dir="$HOME/.dotfiles"

for file in $dir/.*;
do
    [ -e "$file" ] || continue
    file=$(basename $file)
    if [ "$file" != ".git" ] && [ "$file" != ".gitignore" ]; then
        local="$HOME/$file"
        repo="$dir/$file"
        echo "Local = $local, Repo = $repo"
        echo "git diff -s --exit-code $file"
        git diff -s --exit-code $file
        gitdiff="$?"
        echo "diff -q $local $repo"
        diff -q $local $repo
        localdiff="$status"
        echo "localdiff = $localdiff, gitdiff = $gitdiff"
        backup="$dir/backup/$file"
        echo "Backup = $backup"

        if [[ "$localdiff" == "1" ]]; then
            if [[ "$gitdiff" == "1" ]]; then
                cp $local $backup
                tmp="$dir/tmp"
                cp $repo $tmp
                cp $local $repo
                git diff -s --exit-code $file
                localtogitdiff="$?"
                echo "localtogitdiff = $localtogitdiff"
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
                cp $local $repo
                place="local"
            fi
        fi

        if [[ "$localdiff" == "1" ]] || [[ "$gitdiff" == "1" ]]; then
            ga $repo
            gcm "Update $file from $place changes"
            gp
        fi

        # echo "cp $HOME/$file $dir/backup/$file"
        # echo "cp $dir/$file $HOME/$file"
        # mkdir -p "$dir/backup" && cp "~/$file" "$dir/backup/$file"
        # cp "$dir/$file" "~/$file"
    fi
    echo
done

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

cd -

