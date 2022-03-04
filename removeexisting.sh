for file in "~/.dotfiles/.*";
do
    if [ "$file" != ".git" ] && [ "$file" != ".gitignore" ]; then
	rm ~/$file
    fi
done
