PATCH_FILE="patch/columns.patch"

echo "" > $PATCH_FILE

for file in $(find ./patch/osm2pgrouting -type f); do
	echo "Creating patch for" $file...
	touch $file
	diff -u ${file:8} $file >> $PATCH_FILE
done

if [[ $(wc -c $PATCH_FILE | cut -d ' ' -f 1) == 1 ]]; then
	echo "Nothing to patch. Exiting."
	rm $PATCH_FILE
	exit
fi

patch -i $PATCH_FILE -p2
