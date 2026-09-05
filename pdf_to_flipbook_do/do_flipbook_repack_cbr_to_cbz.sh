#!/bin/bash

# Convert extracted CBR folders to CBZ, then clean up

cd /mnt/data/Strategy_Guides/Strategy\ Guides

echo "📦 Converting extracted folders to CBZ..."

# Check if zip is installed
if ! command -v zip &> /dev/null; then
    echo "📦 Installing zip..."
    apt-get install -y zip 2>/dev/null
fi

# Count folders in cbr_temp
FOLDER_COUNT=$(ls -1 cbr_temp/ 2>/dev/null | wc -l)
if [ "$FOLDER_COUNT" -eq 0 ]; then
    echo "❌ No folders found in cbr_temp/"
    exit 1
fi

echo "📊 Found $FOLDER_COUNT folders to convert"
echo ""

CONVERTED=0
FAILED=0

for folder in cbr_temp/*; do
    if [ -d "$folder" ]; then
        basename=$(basename "$folder")
        echo "🔄 Converting: $basename"
        
        # Check if CBZ already exists
        if [ -f "${basename}.cbz" ]; then
            echo "   ⏭️  CBZ already exists, skipping"
            rm -rf "$folder"
            echo "   🗑️  Deleted folder: $folder"
            continue
        fi
        
        # Create CBZ from folder contents
        cd "$folder"
        
        # Check if there are files
        if [ $(find . -type f | wc -l) -gt 0 ]; then
            echo "   📦 Creating CBZ..."
            zip -r -q "../${basename}.cbz" . 2>/dev/null
            
            if [ -f "../${basename}.cbz" ] && [ -s "../${basename}.cbz" ]; then
                echo "   ✅ Created: ${basename}.cbz ($(du -h "../${basename}.cbz" | cut -f1))"
                CONVERTED=$((CONVERTED + 1))
            else
                echo "   ❌ Failed to create CBZ"
                FAILED=$((FAILED + 1))
            fi
        else
            echo "   ⚠️  No files found in folder"
            FAILED=$((FAILED + 1))
        fi
        
        cd /mnt/data/Strategy_Guides/Strategy\ Guides
        
        # Delete the folder
        rm -rf "$folder"
        echo "   🗑️  Deleted folder: $folder"
        echo ""
    fi
done

# Delete all CBR files
echo "🗑️ Deleting all CBR files..."
rm -f *.cbr

echo "=================================================="
echo "✅ Conversion complete!"
echo "=================================================="
echo "📊 Converted: $CONVERTED"
echo "📊 Failed: $FAILED"
echo "📊 CBZ files now: $(ls -1 *.cbz 2>/dev/null | wc -l)"
echo "📊 Remaining CBR: $(ls -1 *.cbr 2>/dev/null | wc -l)"
echo "=================================================="