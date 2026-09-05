#!/bin/bash

# ============================================
# Generate Download Links from Directory Listing
# Scrapes https://flip5.gitgpt.chat/guides/ and creates links.txt
# ============================================

DOMAIN="https://flip5.gitgpt.chat"
GUIDES_URL="$DOMAIN/guides/"
OUTPUT_FILE="download_files.txt"

echo "📥 Fetching directory listing from $GUIDES_URL..."

# Fetch the HTML and extract PDF links
curl -s "$GUIDES_URL" | \
    grep -o 'href="[^"]*\.pdf"' | \
    sed 's/href="//;s/"//' | \
    while read -r file; do
        echo "$DOMAIN/guides/$file"
    done > "$OUTPUT_FILE"

# Count the links
TOTAL=$(wc -l < "$OUTPUT_FILE")

echo "✅ Created $OUTPUT_FILE with $TOTAL direct download links"
echo "📋 Preview:"
head -5 "$OUTPUT_FILE"