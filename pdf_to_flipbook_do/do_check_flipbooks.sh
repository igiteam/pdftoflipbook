#!/bin/bash

cd /var/www/flipbook/output

echo "🔍 Checking PC Zone issues coverage..."
echo "============================================================"
echo ""

# Extract all issue numbers from HTML files
ISSUES=$(find . -maxdepth 2 -name "*.html" -type f | grep -o "PC_Zone_Issue_[0-9]*" | sed 's/PC_Zone_Issue_//' | sort -n)

# Get min and max
MIN_ISSUE=$(echo "$ISSUES" | head -1)
MAX_ISSUE=$(echo "$ISSUES" | tail -1)

echo "📊 PC Zone Issues found:"
echo "  📄 First issue: $MIN_ISSUE"
echo "  📄 Last issue: $MAX_ISSUE"
echo "  📄 Total issues found: $(echo "$ISSUES" | wc -l)"
echo ""

# Check for missing issues in range
echo "🔍 Checking for missing issues ($MIN_ISSUE - $MAX_ISSUE)..."
echo ""

MISSING=()
for i in $(seq $MIN_ISSUE $MAX_ISSUE); do
    if ! echo "$ISSUES" | grep -q "^$i$"; then
        MISSING+=("$i")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️ Missing issues:${NC}"
    for issue in "${MISSING[@]}"; do
        echo "  ❌ Issue $issue"
    done
else
    echo -e "${GREEN}✅ All issues from $MIN_ISSUE to $MAX_ISSUE are present!${NC}"
fi

echo ""
echo "============================================================"
echo "📊 Summary:"
echo "  📄 Issues range: $MIN_ISSUE - $MAX_ISSUE"
echo "  📄 Total expected: $(($MAX_ISSUE - $MIN_ISSUE + 1))"
echo "  📄 Found: $(echo "$ISSUES" | wc -l)"
echo "  ❌ Missing: ${#MISSING[@]}"
echo "============================================================"

# Show all issues with their folders
echo ""
echo "📋 Issue to folder mapping (first 20):"
find . -maxdepth 2 -name "*.html" -type f | grep -o "./flipbook_[^/]*/PC_Zone_Issue_[0-9]*" | head -20 | while read line; do
    folder=$(echo "$line" | cut -d'/' -f2)
    issue=$(echo "$line" | grep -o "PC_Zone_Issue_[0-9]*" | sed 's/PC_Zone_Issue_//')
    echo "  📁 $folder → Issue $issue"
done
if [ $(find . -maxdepth 2 -name "*.html" -type f | grep -o "PC_Zone_Issue_[0-9]*" | wc -l) -gt 20 ]; then
    echo "  ... and $(( $(find . -maxdepth 2 -name "*.html" -type f | grep -o "PC_Zone_Issue_[0-9]*" | wc -l) - 20 )) more"
fi