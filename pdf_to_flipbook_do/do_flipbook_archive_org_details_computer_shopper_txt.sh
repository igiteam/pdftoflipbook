#!/bin/bash

# Computer Shopper Magazine Pipeline - Batch Mode
# Takes a TXT file with direct Archive.org URLs and processes each one
# Downloads and converts each PDF/CBZ to FlipBook automatically

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${MAGENTA}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                                                               ║"
echo "║     Computer Shopper Magazine Pipeline - Batch Mode          ║"
echo "║     Takes URL list → Downloads → Converts to FlipBook        ║"
echo "║                                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check for Python3
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python3 not found. Please install Python3 first.${NC}"
    exit 1
fi

# Install required packages
echo -e "\n${CYAN}📦 Installing required Python packages...${NC}"
pip3 install requests --break-system-packages 2>/dev/null || \
pip3 install --user requests 2>/dev/null || \
pip3 install requests 2>/dev/null || true

# Check if .env exists
if [ ! -f ".env" ]; then
    echo -e "\n${CYAN}📝 Creating .env file with FlipBook credentials${NC}"
    read -p "Enter your FlipBook API Token (optional): " TOKEN_API
    read -p "Enter FlipBook Domain [https://flipbook.gitgpt.chat]: " DOMAIN
    DOMAIN=${DOMAIN:-https://flipbook.gitgpt.chat}
    
    cat > .env << EOF
# FlipBook Configuration
TOKEN_API=$TOKEN_API
DOMAIN=$DOMAIN
EOF

    chmod 600 .env
    echo -e "${GREEN}✅ .env file created!${NC}"
else
    echo -e "${GREEN}✅ .env file found${NC}"
fi

# Load .env
export $(grep -v '^#' .env | xargs 2>/dev/null || true)
DOMAIN="${DOMAIN:-https://flipbook.gitgpt.chat}"

# Parse arguments
URL_LIST=""
MAX_FILES=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --max)
            MAX_FILES="$2"
            shift 2
            ;;
        --help|-h)
            echo -e "\n${YELLOW}Usage:${NC}"
            echo "  $0 <url-list.txt> [options]"
            echo ""
            echo -e "${YELLOW}Options:${NC}"
            echo "  --max N          Maximum number of files to process"
            echo "  --help           Show this help message"
            echo ""
            echo -e "${YELLOW}Example URL list format:${NC}"
            echo "  https://archive.org/download/ComputerShopper_2001-12/ComputerShopper_December2001.pdf"
            echo "  https://archive.org/download/computer-shopper-august-1994-images.zip/Computer%20Shopper%20August%201994.pdf"
            echo "  https://archive.org/download/computer_shopper-2000-12/ComputerShopper_2000_December.cbz"
            echo ""
            echo -e "${YELLOW}Example:${NC}"
            echo "  $0 https://cdn.gitgpt.chat/rtx/computer_shopper.txt"
            echo "  $0 computer_shopper.txt --max 5"
            exit 0
            ;;
        *)
            URL_LIST="$1"
            shift
            ;;
    esac
done

if [ -z "$URL_LIST" ]; then
    echo -e "${RED}❌ No URL list provided!${NC}"
    echo -e "${YELLOW}Usage: $0 <url-list.txt> [--max N]${NC}"
    exit 1
fi

echo -e "\n${CYAN}📋 Configuration:${NC}"
echo "   FlipBook Domain: $DOMAIN"
if [ -n "$TOKEN_API" ]; then
    echo "   API Token: ✅ Set"
else
    echo "   API Token: ❌ Not set (public access)"
fi
echo "   URL List: $URL_LIST"
[ -n "$MAX_FILES" ] && echo "   Max Files: $MAX_FILES"
echo ""

# Create the Python batch processor
echo -e "${CYAN}📄 Creating batch processor script...${NC}"

cat > batch_processor.py << 'PYEOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Computer Shopper Magazine Batch Processor
Takes a text file with direct Archive.org URLs and processes each one
Downloads and converts each PDF/CBZ to FlipBook automatically
"""

import os
import sys
import time
import re
import requests
from datetime import datetime
from urllib.parse import unquote

# Load .env
try:
    from dotenv import load_dotenv
    load_dotenv()
except:
    pass

API_TOKEN = os.getenv('TOKEN_API', '')
DOMAIN = os.getenv('DOMAIN', 'https://flipbook.gitgpt.chat').rstrip('/')

# Built-in FlipBook client
class FlipBookClient:
    def __init__(self):
        self.base_url = DOMAIN
        self.session = requests.Session()
        if API_TOKEN:
            self.session.headers.update({'Authorization': 'Bearer ' + API_TOKEN})
    
    def upload_pdf(self, pdf_path):
        """Upload PDF to FlipBook API"""
        url = self.base_url + "/api/upload"
        try:
            with open(pdf_path, 'rb') as f:
                file_content = f.read()
                file_name = os.path.basename(pdf_path)
                files = {'pdf': (file_name, file_content, 'application/pdf')}
                response = self.session.post(url, files=files, timeout=60)
                
                if response.status_code == 200:
                    data = response.json()
                    return data.get('job_id')
                else:
                    print(f"      ❌ Upload failed: HTTP {response.status_code}")
                    return None
        except Exception as e:
            print(f"      ❌ Upload error: {str(e)}")
            return None
    
    def check_progress(self, job_id):
        """Check job progress"""
        url = self.base_url + "/api/progress/" + job_id
        try:
            response = self.session.get(url, timeout=10)
            if response.status_code == 200:
                return response.json()
            return None
        except:
            return None

def fetch_metadata(url):
    """Fetch metadata from Archive.org for a direct file URL"""
    # Try to get the item identifier from the URL
    # Format: https://archive.org/download/ITEM_ID/FILE_NAME
    match = re.search(r'archive\.org/download/([^/]+)/', url)
    if not match:
        return None
    
    identifier = match.group(1)
    metadata_url = "https://archive.org/metadata/" + identifier
    
    try:
        response = requests.get(metadata_url, timeout=30)
        if response.status_code == 200:
            return response.json()
        return None
    except:
        return None

def get_filename_from_url(url):
    """Extract filename from URL"""
    # Decode URL encoding
    filename = unquote(url.split('/')[-1].split('?')[0])
    return filename

def download_file(url, local_path, display_name):
    """Download file with progress bar"""
    try:
        response = requests.get(url, stream=True, timeout=300)
        response.raise_for_status()
        
        total_size = int(response.headers.get('content-length', 0))
        downloaded = 0
        last_percent = -1
        
        with open(local_path, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                if chunk:
                    f.write(chunk)
                    downloaded += len(chunk)
                    if total_size > 0:
                        percent = int((downloaded / total_size) * 100)
                        if percent != last_percent and percent % 10 == 0:
                            bar_length = 30
                            filled = int(bar_length * percent / 100)
                            bar = '█' * filled + '░' * (bar_length - filled)
                            print(f"\r      [{bar}] {percent}% ({downloaded/(1024*1024):.1f}/{total_size/(1024*1024):.1f} MB)", end='', flush=True)
                            last_percent = percent
        
        print()
        return True
    except Exception as e:
        print(f"\n      ❌ Download failed: {str(e)}")
        return False

def wait_for_job_completion(flipbook, job_id, timeout=1800):
    """Wait for job to complete"""
    start_time = time.time()
    last_percent = -1
    last_stage = ''
    
    while time.time() - start_time < timeout:
        progress = flipbook.check_progress(job_id)
        
        if progress:
            stage = progress.get('stage', 'unknown')
            percent = progress.get('percent', 0)
            
            if percent != last_percent or stage != last_stage:
                if stage == 'converting':
                    current_page = progress.get('currentPage', 0)
                    total_pages = progress.get('totalPages', 0)
                    print(f"\r      Converting: {percent}% - Page {current_page}/{total_pages}", end='', flush=True)
                elif stage == 'complete':
                    print("\n      ✅ Conversion complete!")
                    return {'success': True, 'percent': 100}
                elif stage == 'error':
                    print(f"\n      ❌ Error: {progress.get('error', 'Unknown')}")
                    return {'success': False, 'error': progress.get('error', 'Unknown')}
                
                last_percent = percent
                last_stage = stage
        
        time.sleep(3)
    
    print("\n      ⏰ Timeout after " + str(timeout) + " seconds")
    return {'success': False, 'error': 'Timeout'}

def process_url(url, flipbook, temp_folder):
    """Process a single URL: download and convert"""
    filename = get_filename_from_url(url)
    file_ext = os.path.splitext(filename)[1].lower()
    
    if file_ext not in ['.pdf', '.cbz']:
        print(f"   ⏭️  Skipping: {filename} (not PDF or CBZ)")
        return {'success': False, 'skipped': True, 'reason': 'Not PDF/CBZ'}
    
    print(f"\n📄 File: {filename}")
    
    # Download
    local_path = os.path.join(temp_folder, filename)
    print(f"   ⬇️  Downloading...")
    
    if not download_file(url, local_path, filename):
        return {'success': False, 'error': 'Download failed'}
    
    # Get file size
    size_mb = os.path.getsize(local_path) / (1024 * 1024)
    print(f"   ✅ Downloaded ({size_mb:.1f} MB)")
    
    # Upload
    print(f"   📤 Uploading to FlipBook...")
    job_id = flipbook.upload_pdf(local_path)
    
    if not job_id:
        return {'success': False, 'error': 'Upload failed'}
    
    print(f"   ✅ Uploaded! Job ID: {job_id}")
    
    # Wait for conversion
    print(f"   ⏳ Waiting for conversion...")
    result = wait_for_job_completion(flipbook, job_id, 1800)
    
    # Clean up temp file
    if os.path.exists(local_path):
        os.unlink(local_path)
        print(f"   🗑️  Deleted local file")
    
    if result.get('success'):
        return {'success': True, 'job_id': job_id, 'filename': filename}
    else:
        return {'success': False, 'error': result.get('error', 'Unknown')}

def main():
    url_file = sys.argv[1] if len(sys.argv) > 1 else None
    max_files = int(sys.argv[2]) if len(sys.argv) > 2 else None
    
    if not url_file:
        print("❌ No URL list provided!")
        sys.exit(1)
    
    # Read URLs
    if url_file.startswith('http://') or url_file.startswith('https://'):
        print(f"📥 Downloading URL list from: {url_file}")
        response = requests.get(url_file, timeout=30)
        if response.status_code != 200:
            print(f"❌ Failed to download URL list: HTTP {response.status_code}")
            sys.exit(1)
        urls = response.text.strip().split('\n')
    else:
        with open(url_file, 'r') as f:
            urls = f.read().strip().split('\n')
    
    # Filter and clean URLs
    urls = [u.strip() for u in urls if u.strip() and not u.startswith('#')]
    urls = [u for u in urls if 'archive.org' in u]
    
    if max_files:
        urls = urls[:max_files]
    
    print(f"\n📊 Found {len(urls)} files to process")
    
    # Create temp folder
    temp_folder = "temp_downloads"
    os.makedirs(temp_folder, exist_ok=True)
    
    # Initialize FlipBook
    flipbook = FlipBookClient()
    
    # Process each URL
    successful = 0
    failed = 0
    skipped = 0
    results_file = "converted_flipbooks.txt"
    
    for i, url in enumerate(urls, 1):
        print("\n" + "="*80)
        print(f"[{i}/{len(urls)}] Processing: {url[:80]}...")
        print("="*80)
        
        result = process_url(url, flipbook, temp_folder)
        
        if result.get('skipped'):
            skipped += 1
        elif result.get('success'):
            successful += 1
            with open(results_file, "a") as f:
                f.write(f"{result.get('filename')}|{url}|{DOMAIN}/api/history\n")
        else:
            failed += 1
            print(f"   ❌ Failed: {result.get('error', 'Unknown error')}")
        
        # Save progress
        print(f"\n📊 Progress: {i}/{len(urls)} - Success: {successful}, Failed: {failed}, Skipped: {skipped}")
        
        # Small delay between files
        if i < len(urls):
            time.sleep(2)
    
    # Final summary
    print("\n" + "="*80)
    print("✅ BATCH PROCESSING COMPLETE!")
    print("="*80)
    print(f"📊 Total files: {len(urls)}")
    print(f"✅ Successful: {successful}")
    print(f"❌ Failed: {failed}")
    print(f"⏭️  Skipped: {skipped}")
    print(f"📁 Results: {results_file}")
    print("="*80)

if __name__ == "__main__":
    main()
PYEOF

chmod +x batch_processor.py

# Build command
CMD="python3 -u batch_processor.py \"$URL_LIST\""

if [ -n "$MAX_FILES" ]; then
    CMD="$CMD $MAX_FILES"
fi

# Run the batch processor
echo -e "${CYAN}🚀 Running batch processor...${NC}"
echo -e "${YELLOW}   Press Ctrl+C to cancel${NC}"
echo ""

eval $CMD

# Show next steps
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "\n${GREEN}✅ Batch processing completed successfully!${NC}"
    echo -e "\n${CYAN}💡 Next steps:${NC}"
    echo "  1. Check converted flipbooks in converted_flipbooks.txt"
    echo "  2. View them at: $DOMAIN/api/history"
    echo "  3. Or browse: $DOMAIN/"
else
    echo -e "\n${YELLOW}⚠️ Batch processor exited with code: $EXIT_CODE${NC}"
fi