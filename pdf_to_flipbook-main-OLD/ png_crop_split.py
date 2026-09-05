#!/bin/bash
# png_crop_split.py - Python version of your working ImageMagick script

import os
from PIL import Image

# Mask coordinates and dimensions
MASK_X = 734
MASK_Y = 2083
MASK_W = 8516
MASK_H = 2850

# Calculate split point
SPLIT_POINT = MASK_W // 2
LEFT_W = SPLIT_POINT
RIGHT_W = MASK_W - SPLIT_POINT

# Create output directories
os.makedirs("cropped_mask", exist_ok=True)
os.makedirs("split_pages", exist_ok=True)

print("\033[32mProcessing PNG files...\033[0m")
print("-" * 40)

count = 0
for file in os.listdir('.'):
    if not file.endswith('.png'):
        continue
    
    base_name = file[:-4]
    print(f"\033[33mProcessing: {file}\033[0m")
    
    # Step 1: Crop to mask region
    img = Image.open(file)
    cropped = img.crop((MASK_X, MASK_Y, MASK_X + MASK_W, MASK_Y + MASK_H))
    cropped_path = f"cropped_mask/{base_name}_cropped.png"
    cropped.save(cropped_path)
    print(f"  \033[32m✓ Cropped to mask region\033[0m")
    
    # Step 2: Split into left and right pages
    left = cropped.crop((0, 0, LEFT_W, MASK_H))
    right = cropped.crop((SPLIT_POINT, 0, SPLIT_POINT + RIGHT_W, MASK_H))
    
    left_path = f"split_pages/{base_name}_01.png"
    right_path = f"split_pages/{base_name}_02.png"
    left.save(left_path)
    right.save(right_path)
    
    print(f"  \033[32m✓ Split into:\033[0m")
    print(f"    \033[33m{base_name}_01.png\033[0m (left page)")
    print(f"    \033[33m{base_name}_02.png\033[0m (right page)")
    
    count += 1

print("-" * 40)
print(f"\033[32mComplete! Processed {count} file(s)\033[0m")
print(f"  📁 Split pages: \033[33msplit_pages/\033[0m")
 