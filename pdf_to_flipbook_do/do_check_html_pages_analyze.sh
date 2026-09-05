#!/bin/bash

# Flipbook Folder Health Check
# Checks: HTML files + Page images

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Function to check a single folder
check_folder() {
    local folder="$1"
    local issues=()
    local html_files=()
    local png_files=()
    
    # Find HTML files
    while IFS= read -r -d '' file; do
        html_files+=("$file")
    done < <(find "$folder" -maxdepth 1 -name "*.html" -print0 2>/dev/null)
    
    # Find PNG files
    while IFS= read -r -d '' file; do
        png_files+=("$file")
    done < <(find "$folder" -maxdepth 1 -name "*.png" -print0 2>/dev/null)
    
    # Check HTML
    if [ ${#html_files[@]} -eq 0 ]; then
        issues+=("${RED}❌ No HTML file found${NC}")
    elif [ ${#html_files[@]} -gt 1 ]; then
        issues+=("${YELLOW}⚠️ Multiple HTML files: ${#html_files[@]}${NC}")
    else
        html_size=$(stat -f%z "${html_files[0]}" 2>/dev/null || stat -c%s "${html_files[0]}" 2>/dev/null)
        html_size_kb=$((html_size / 1024))
        if [ $html_size_kb -lt 5 ]; then
            issues+=("${YELLOW}⚠️ HTML file too small: ${html_size_kb}KB${NC}")
        fi
    fi
    
    # Check PNGs
    if [ ${#png_files[@]} -eq 0 ]; then
        issues+=("${RED}❌ No page images (PNG) found${NC}")
    else
        # Check naming pattern and page numbers
        page_numbers=()
        for png in "${png_files[@]}"; do
            filename=$(basename "$png")
            if [[ $filename =~ page_([0-9]+)\.png$ ]]; then
                page_numbers+=("${BASH_REMATCH[1]}")
            fi
        done
        
        if [ ${#page_numbers[@]} -gt 0 ]; then
            # Sort page numbers
            IFS=$'\n' sorted=($(sort -n <<<"${page_numbers[*]}"))
            unset IFS
            
            # Check for missing pages
            max_page=${sorted[-1]}
            missing=()
            for ((i=1; i<=max_page; i++)); do
                found=0
                for num in "${sorted[@]}"; do
                    if [ "$num" -eq "$i" ]; then
                        found=1
                        break
                    fi
                done
                if [ $found -eq 0 ]; then
                    missing+=("$i")
                fi
            done
            
            if [ ${#missing[@]} -gt 0 ]; then
                missing_str=$(printf "%s, " "${missing[@]}")
                missing_str="${missing_str%, }"
                if [ ${#missing[@]} -gt 10 ]; then
                    missing_str="${missing_str:0:50}..."
                fi
                issues+=("${YELLOW}⚠️ Missing pages: $missing_str${NC}")
            fi
            
            # Check if page 1 exists
            if [[ ! " ${sorted[@]} " =~ " 1 " ]]; then
                issues+=("${RED}❌ Missing page 1${NC}")
            fi
        fi
        
        # Check average file size
        total_size=0
        for png in "${png_files[@]}"; do
            size=$(stat -f%z "$png" 2>/dev/null || stat -c%s "$png" 2>/dev/null)
            total_size=$((total_size + size))
        done
        
        total_size_mb=$(echo "scale=2; $total_size / (1024*1024)" | bc 2>/dev/null || echo "0")
        avg_size=$(echo "scale=2; $total_size_mb / ${#png_files[@]}" | bc 2>/dev/null || echo "0")
        
        if [ $(echo "$avg_size < 0.1" | bc 2>/dev/null || echo "0") -eq 1 ]; then
            issues+=("${YELLOW}⚠️ Very small images: ${avg_size}MB average${NC}")
        fi
    fi
    
    # Return results
    echo "${#html_files[@]}|${#png_files[@]}|${#issues[@]}|$(IFS='|'; echo "${issues[*]}")"
}

# Main
echo -e "${MAGENTA}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     Flipbook Folder Health Check                             ║"
echo "║     Checks: HTML files + Page images                        ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Get current directory
cwd=$(pwd)
echo "📁 Checking: $cwd"
echo ""

# Find all flipbook folders
folders=()
while IFS= read -r -d '' folder; do
    folders+=("$folder")
done < <(find . -maxdepth 1 -type d -name "flipbook_*" -print0 | sort -z)

if [ ${#folders[@]} -eq 0 ]; then
    echo -e "${RED}❌ No flipbook folders found!${NC}"
    exit 1
fi

echo "📂 Found ${#folders[@]} flipbook folders"
echo "============================================================"
echo ""

# Check each folder
issues_found=0
total_html=0
total_pngs=0
declare -a issue_folders
declare -a issue_details

for i in "${!folders[@]}"; do
    folder="${folders[$i]}"
    folder_name=$(basename "$folder")
    index=$((i + 1))
    
    # Run check
    result=$(check_folder "$folder")
    IFS='|' read -r html_count png_count issue_count issues <<< "$result"
    
    # Update totals
    total_html=$((total_html + html_count))
    total_pngs=$((total_pngs + png_count))
    
    # Print status
    if [ "$issue_count" -eq 0 ]; then
        echo -e "[$index/${#folders[@]}] ${GREEN}✅${NC} $folder_name (HTML: $html_count, PNGs: $png_count)"
    else
        echo -e "[$index/${#folders[@]}] ${RED}⚠️${NC} $folder_name (HTML: $html_count, PNGs: $png_count)"
        issues_found=$((issues_found + 1))
        issue_folders+=("$folder_name")
        issue_details+=("$issues")
        
        # Print issues
        IFS='|' read -ra issue_array <<< "$issues"
        for issue in "${issue_array[@]}"; do
            echo -e "        $issue"
        done
    fi
done

# Summary
echo ""
echo "============================================================"
echo -e "${GREEN}✅ COMPLETE!${NC}"
echo "============================================================"
echo "📊 Summary:"
echo "   📂 Total folders: ${#folders[@]}"
echo "   📄 HTML files: $total_html"
echo "   🖼️ PNG files: $total_pngs"
echo "   ⚠️ Folders with issues: $issues_found"

if [ $issues_found -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}📋 Folders with issues:${NC}"
    for i in "${!issue_folders[@]}"; do
        echo "   $((i+1)). ${issue_folders[$i]}"
        IFS='|' read -ra issue_array <<< "${issue_details[$i]}"
        for issue in "${issue_array[@]}"; do
            echo "      $issue"
        done
    done
fi

echo ""
echo "💡 All good? Check a random folder:"

# Show sample of first folder
if [ ${#folders[@]} -gt 0 ]; then
    sample="${folders[0]}"
    sample_name=$(basename "$sample")
    echo "   📂 $sample_name"
    
    # Find HTML files
    html_files=()
    while IFS= read -r -d '' file; do
        html_files+=("$file")
    done < <(find "$sample" -maxdepth 1 -name "*.html" -print0 2>/dev/null)
    
    if [ ${#html_files[@]} -gt 0 ]; then
        html_size=$(stat -f%z "${html_files[0]}" 2>/dev/null || stat -c%s "${html_files[0]}" 2>/dev/null)
        html_size_kb=$((html_size / 1024))
        html_name=$(basename "${html_files[0]}")
        echo "      📄 HTML: $html_name (${html_size_kb}KB)"
    fi
    
    # Find PNG files
    png_files=()
    while IFS= read -r -d '' file; do
        png_files+=("$file")
    done < <(find "$sample" -maxdepth 1 -name "*.png" -print0 2>/dev/null)
    
    if [ ${#png_files[@]} -gt 0 ]; then
        echo "      🖼️ Pages: ${#png_files[@]} PNGs"
        total_size=0
        for png in "${png_files[@]}"; do
            size=$(stat -f%z "$png" 2>/dev/null || stat -c%s "$png" 2>/dev/null)
            total_size=$((total_size + size))
        done
        total_size_mb=$(echo "scale=1; $total_size / (1024*1024)" | bc 2>/dev/null || echo "0")
        echo "      📏 Size: ${total_size_mb}MB total"
    fi
fi

echo ""
echo -e "${GREEN}✨ Done!${NC}"