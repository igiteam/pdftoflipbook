
#!/bin/bash

SOURCE="$HOME/Downloads/pczone_github"
DEST="$HOME/Downloads/pczonemagazines"

cd "$DEST" || exit 1

for folder in "$SOURCE"/*/; do

    [ -d "$folder" ] || continue

    MAGAZINE=$(basename "$folder")

    echo ""
    echo "Uploading folder: $MAGAZINE"

    # Copy the ENTIRE folder, not its contents
    ditto "$folder" "$DEST/$MAGAZINE" || exit 1

    # Stage that folder only
    git add -- "$MAGAZINE" || exit 1

    # Commit
    git commit -m "Add magazine: $MAGAZINE" || exit 1

    # Push
    git push origin main || exit 1

    echo "Uploaded: $MAGAZINE"

done

echo "ALL DONE!"
