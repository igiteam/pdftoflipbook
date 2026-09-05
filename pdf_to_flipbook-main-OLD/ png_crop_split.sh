#!/bin/bash

# PNG Mask, Crop, and Split Script
# Applies mask region, crops, then splits into left/right pages with proper naming

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Mask coordinates and dimensions
MASK_X=732
MASK_Y=2080
MASK_W=8516
MASK_H=2850

# Calculate split point (center of the mask width)
SPLIT_POINT=$((MASK_W / 2))
LEFT_W=$SPLIT_POINT
RIGHT_W=$((MASK_W - SPLIT_POINT))

# Create output directories
mkdir -p cropped_mask split_pages

echo -e "${GREEN}Processing PNG files...${NC}"
echo "----------------------------------------"

# Process each PNG file
count=0
for png in *.png; do
    [ -e "$png" ] || continue
    
    # Remove extension to get base name
    base_name="${png%.png}"
    
    echo -e "Processing: ${YELLOW}$png${NC}"
    
    # Step 1: Crop to the mask region (optional - remove if you don't need the cropped version)
    cropped="cropped_mask/${base_name}_cropped.png"
    convert "$png" -crop ${MASK_W}x${MASK_H}+${MASK_X}+${MASK_Y} "$cropped"
    echo -e "  ${GREEN}✓ Cropped to mask region${NC}"
    
    # Step 2: Split into left and right pages with proper naming
    left="split_pages/${base_name}_01.png"
    right="split_pages/${base_name}_02.png"
    
    # Extract left half (page 1)
    convert "$cropped" -crop ${LEFT_W}x${MASK_H}+0+0 "$left"
    
    # Extract right half (page 2)
    convert "$cropped" -crop ${RIGHT_W}x${MASK_H}+${SPLIT_POINT}+0 "$right"
    
    echo -e "  ${GREEN}✓ Split into:${NC}"
    echo -e "    ${YELLOW}${base_name}_01.png${NC} (left page)"
    echo -e "    ${YELLOW}${base_name}_02.png${NC} (right page)"
    
    ((count++))
done

echo "----------------------------------------"
echo -e "${GREEN}Complete! Processed $count file(s)${NC}"
echo -e "  📁 Split pages: ${YELLOW}split_pages/${NC}"