for file in .*;
do
    if [ "$file" != ".git" ] && [ "$file" != ".gitignore" ]; then
	rm ../$file
    fi
done
