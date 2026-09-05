#!/bin/bash

# JP2 to PNG Converter using OpenJPEG
# Converts all .jp2 files to .png format

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if opj_decompress is installed
if ! command -v opj_decompress &> /dev/null; then
    echo -e "${RED}Error: OpenJPEG tools are not installed.${NC}"
    echo "Please install it using:"
    echo "  Ubuntu/Debian: sudo apt-get install openjpeg-tools"
    echo "  MacOS: brew install openjpeg"
    echo "  CentOS/RHEL: sudo yum install openjpeg-tools"
    exit 1
fi

# Check for JP2 files
if ! ls *.jp2 1> /dev/null 2>&1; then
    echo -e "${RED}No .jp2 files found in the current directory.${NC}"
    exit 1
fi

echo -e "${GREEN}Found JP2 files. Starting conversion...${NC}"
echo "----------------------------------------"

count=0
failed=0

for file in *.jp2; do
    [ -e "$file" ] || continue
    output="${file%.jp2}.png"
    
    echo -e "Converting: ${YELLOW}$file${NC} -> ${GREEN}$output${NC}"
    
    if opj_decompress -i "$file" -o "$output" 2>/dev/null; then
        echo -e "  ${GREEN}✓ Success${NC}"
        ((count++))
    else
        echo -e "  ${RED}✗ Failed${NC}"
        ((failed++))
    fi
done

echo "----------------------------------------"
echo -e "${GREEN}Conversion complete!${NC}"
echo -e "Converted: ${GREEN}$count${NC} file(s)"
[ $failed -gt 0 ] && echo -e "Failed: ${RED}$failed${NC} file(s)"