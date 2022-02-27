for file in .*;
do
    if [ "$file" != ".git" ]; then
	rm ../$file
    fi
done
