#!/bin/bash

# Strategy Guide Unpacker Script
# Unzips all ZIP files, extracts PDFs, moves them to root, and cleans up

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GUIDES_DIR="/mnt/data/Strategy_Guides/Strategy Guides"
LOG_FILE="/mnt/data/unpack_log.txt"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to print colored messages
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log_message "INFO: $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log_message "SUCCESS: $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log_message "WARNING: $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log_message "ERROR: $1"
}

# Function to check if we're in the right directory
check_directory() {
    if [ ! -d "$GUIDES_DIR" ]; then
        print_error "Directory $GUIDES_DIR does not exist!"
        exit 1
    fi
    
    cd "$GUIDES_DIR" || exit 1
    print_status "Working in: $(pwd)"
}

# Function to count files
count_files() {
    local zip_count=$(find . -maxdepth 1 -name "*.zip" -type f | wc -l)
    local pdf_count=$(find . -maxdepth 1 -name "*.pdf" -type f | wc -l)
    
    echo "📊 Current counts:"
    echo "   ZIP files: $zip_count"
    echo "   PDF files: $pdf_count"
    echo ""
}

# Function to unzip and extract PDFs
unzip_and_extract() {
    local zip_file="$1"
    local temp_dir="${zip_file%.zip}_temp"
    
    print_status "Processing: $zip_file"
    
    # Create temporary directory
    mkdir -p "$temp_dir"
    
    # Try to unzip
    if unzip -o -q "$zip_file" -d "$temp_dir" 2>/dev/null; then
        # Find PDFs in the extracted content (including subdirectories)
        local pdf_files=$(find "$temp_dir" -name "*.pdf" -type f)
        local pdf_count=$(echo "$pdf_files" | wc -l)
        
        if [ "$pdf_count" -gt 0 ] && [ -n "$pdf_files" ]; then
            # Move PDFs to root directory
            echo "$pdf_files" | while read -r pdf; do
                if [ -f "$pdf" ]; then
                    local pdf_name=$(basename "$pdf")
                    local new_name="${zip_file%.zip}_${pdf_name}"
                    
                    # Handle duplicate filenames
                    if [ -f "$new_name" ]; then
                        local counter=1
                        while [ -f "${zip_file%.zip}_${pdf_name%.pdf}_${counter}.pdf" ]; do
                            counter=$((counter + 1))
                        done
                        new_name="${zip_file%.zip}_${pdf_name%.pdf}_${counter}.pdf"
                    fi
                    
                    mv "$pdf" "$new_name" 2>/dev/null
                    print_success "Extracted: $pdf_name → $new_name"
                fi
            done
        else
            print_warning "No PDFs found in: $zip_file"
        fi
        
        # Clean up temporary directory
        rm -rf "$temp_dir"
        
        # Remove the original ZIP file
        rm -f "$zip_file"
        print_status "Removed: $zip_file"
        
        return 0
    else
        print_error "Failed to unzip: $zip_file"
        rm -rf "$temp_dir"
        return 1
    fi
}

# Function to process CBZ and CBR files (optional)
process_cbz_cbr() {
    local file="$1"
    local ext="${file##*.}"
    local temp_dir="${file%.*}_temp"
    
    print_status "Processing: $file"
    
    mkdir -p "$temp_dir"
    
    if [ "$ext" = "cbz" ]; then
        unzip -o -q "$file" -d "$temp_dir" 2>/dev/null
    elif [ "$ext" = "cbr" ]; then
        # For CBR, use unrar if available
        if command -v unrar &> /dev/null; then
            unrar x -o+ "$file" "$temp_dir/" > /dev/null 2>&1
        else
            print_warning "unrar not installed, skipping: $file"
            rm -rf "$temp_dir"
            return 1
        fi
    fi
    
    # Look for PDFs
    local pdf_files=$(find "$temp_dir" -name "*.pdf" -type f)
    if [ -n "$pdf_files" ]; then
        echo "$pdf_files" | while read -r pdf; do
            local pdf_name=$(basename "$pdf")
            mv "$pdf" "./${file%.*}_${pdf_name}" 2>/dev/null
            print_success "Extracted PDF from: $file"
        done
    fi
    
    rm -rf "$temp_dir"
    rm -f "$file"
    print_status "Removed: $file"
}

# Function to process all ZIP files
process_all_zips() {
    print_status "Starting ZIP processing..."
    
    local zip_files=$(find . -maxdepth 1 -name "*.zip" -type f)
    local total_zips=$(echo "$zip_files" | wc -l)
    
    if [ "$total_zips" -eq 0 ]; then
        print_warning "No ZIP files found!"
        return
    fi
    
    print_status "Found $total_zips ZIP files to process"
    
    local processed=0
    local failed=0
    
    echo "$zip_files" | while read -r zip_file; do
        if [ -f "$zip_file" ]; then
            if unzip_and_extract "$zip_file"; then
                processed=$((processed + 1))
            else
                failed=$((failed + 1))
            fi
        fi
    done
    
    print_success "Processing complete: $processed processed, $failed failed"
}

# Function to process CBZ/CBR files (optional)
process_all_cbz_cbr() {
    print_status "Checking for CBZ/CBR files..."
    
    if ! command -v unrar &> /dev/null; then
        print_warning "unrar not installed. Install with: apt install unrar"
        print_warning "Skipping CBR files (CBZ will still work)"
    fi
    
    local cbz_files=$(find . -maxdepth 1 -name "*.cbz" -type f 2>/dev/null)
    local cbr_files=$(find . -maxdepth 1 -name "*.cbr" -type f 2>/dev/null)
    local total=$(echo "$cbz_files $cbr_files" | wc -w)
    
    if [ "$total" -eq 0 ]; then
        print_status "No CBZ/CBR files found"
        return
    fi
    
    print_status "Found $total CBZ/CBR files"
    
    find . -maxdepth 1 \( -name "*.cbz" -o -name "*.cbr" \) -type f | while read -r file; do
        process_cbz_cbr "$file"
    done
}

# Function to clean up empty directories
cleanup_directories() {
    print_status "Cleaning up empty directories..."
    find . -type d -empty -delete 2>/dev/null
    print_success "Cleanup complete"
}

# Function to show final stats
show_final_stats() {
    echo ""
    echo "=================================================="
    echo "📊 FINAL STATISTICS"
    echo "=================================================="
    
    local final_pdf_count=$(find . -maxdepth 1 -name "*.pdf" -type f | wc -l)
    local final_zip_count=$(find . -maxdepth 1 -name "*.zip" -type f | wc -l)
    local final_cbz_count=$(find . -maxdepth 1 -name "*.cbz" -type f | wc -l)
    local final_cbr_count=$(find . -maxdepth 1 -name "*.cbr" -type f | wc -l)
    
    echo "   PDF files: $final_pdf_count"
    echo "   ZIP files: $final_zip_count"
    echo "   CBZ files: $final_cbz_count"
    echo "   CBR files: $final_cbr_count"
    echo "   Total size: $(du -sh . | cut -f1)"
    echo "=================================================="
}

# Main execution
main() {
    print_status "=== Strategy Guide Unpacker Started ==="
    print_status "Log file: $LOG_FILE"
    
    check_directory
    
    echo ""
    count_files
    
    # Ask for confirmation
    read -p "Continue with unpacking? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_status "Cancelled by user"
        exit 0
    fi
    
    # Process files
    process_all_zips
    
    # Optional: Process CBZ/CBR files (uncomment if you want this)
    # process_all_cbz_cbr
    
    cleanup_directories
    
    show_final_stats
    
    print_success "=== Unpacking Complete! ==="
    print_status "All PDFs are now in: $(pwd)"
}

# Run the script
main