#!/bin/bash
# rename-zips-by-html.sh - Rename ZIP files to match HTML filenames

echo -e "\033[0;36m"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     Rename ZIPs to Match HTML Filenames                     ║"
echo "║                                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "\033[0m"

cd /var/www/flipbook/output/

# Count total flipbook folders
TOTAL=$(find . -maxdepth 1 -type d -name "flipbook_*" | wc -l)
echo -e "\033[0;33m📁 Found $TOTAL flipbook folders\033[0m"
echo ""

RENAMED=0
SKIPPED=0
FAILED=0
count=0

# Process each flipbook folder
for dir in flipbook_*/; do
    count=$((count + 1))
    # Remove trailing slash
    dir=${dir%/}
    
    echo -n "[$count/$TOTAL] Processing $(basename "$dir")... "
    
    # Find the HTML file inside the folder
    HTML_FILE=$(find "$dir" -maxdepth 1 -name "*.html" -type f 2>/dev/null | head -1)
    
    if [ -z "$HTML_FILE" ]; then
        echo -e "\033[0;31m❌ No HTML found\033[0m"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    # Get the HTML filename without extension
    HTML_BASENAME=$(basename "$HTML_FILE" .html)
    
    # Check if it's a PC Zone issue
    if [[ "$HTML_BASENAME" != PC_Zone_Issue_* ]]; then
        echo -e "\033[0;33m⚠️ Not a PC Zone issue: $HTML_BASENAME\033[0m"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    
    # The ZIP file is in the parent directory with the same hash name
    # Get the hash from the folder name
    FOLDER_HASH=$(basename "$dir" | sed 's/flipbook_//')
    ZIP_FILE="flipbook_${FOLDER_HASH}.zip"
    
    # Check if the ZIP exists in the parent directory
    if [ ! -f "$ZIP_FILE" ]; then
        echo -e "\033[0;31m❌ ZIP not found: $ZIP_FILE\033[0m"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    # New ZIP name based on HTML filename
    NEW_ZIP_NAME="${HTML_BASENAME}.zip"
    
    # Check if already correctly named
    if [ "$ZIP_FILE" == "$NEW_ZIP_NAME" ]; then
        echo -e "\033[0;33m⏭️ Already correct\033[0m"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    
    # Rename the ZIP file
    if mv "$ZIP_FILE" "$NEW_ZIP_NAME" 2>/dev/null; then
        echo -e "\033[0;32m✅ Renamed: $ZIP_FILE → $NEW_ZIP_NAME\033[0m"
        RENAMED=$((RENAMED + 1))
    else
        echo -e "\033[0;31m❌ Failed to rename\033[0m"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo -e "\033[0;36m═══════════════════════════════════════════════════════════════\033[0m"
echo -e "\033[0;32m✅ Rename Complete!\033[0m"
echo ""
echo "  📦 Renamed: $RENAMED files"
echo "  ⏭️ Skipped: $SKIPPED files"
echo "  ❌ Failed: $FAILED files"
echo ""

if [ $RENAMED -gt 0 ]; then
    echo -e "\033[0;36m📋 Sample of renamed ZIPs:\033[0m"
    ls -1 PC_Zone_Issue_*.zip 2>/dev/null | head -5
    echo ""
    TOTAL_RENAMED=$(ls -1 PC_Zone_Issue_*.zip 2>/dev/null | wc -l)
    echo -e "\033[0;32m✅ Total PC Zone ZIPs: $TOTAL_RENAMED\033[0m"
fi