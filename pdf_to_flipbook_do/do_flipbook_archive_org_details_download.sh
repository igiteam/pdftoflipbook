#!/bin/bash

# PC Zone Magazine Pipeline - Single Link Mode
# Takes ONE Archive.org details URL and finds all PDFs
# EMBEDDED Python script (like the DO Spaces uploader)

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
echo "║     PC Zone Magazine Pipeline - Single Link Mode             ║"
echo "║     Archives.org → FlipBook Converter                        ║"
echo "║                                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check for Python3
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python3 not found. Please install Python3 first.${NC}"
    exit 1
fi

# Check for pip
if ! command -v pip3 &> /dev/null; then
    echo -e "${YELLOW}⚠️ pip3 not found, installing...${NC}"
    apt-get install -y python3-pip 2>/dev/null || \
    yum install -y python3-pip 2>/dev/null || \
    echo -e "${RED}❌ Could not install pip. Please install manually.${NC}"
    exit 1
fi

# Install required packages with proper error handling
echo -e "\n${CYAN}📦 Installing required Python packages...${NC}"

# Try apt first (Ubuntu/Debian way)
if command -v apt-get &> /dev/null; then
    echo -e "${CYAN}   Using apt (system packages)...${NC}"
    apt-get install -y python3-requests python3-dotenv 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Packages installed via apt${NC}"
    else
        echo -e "${YELLOW}⚠️ Apt install failed, trying pip...${NC}"
        pip3 install requests python-dotenv --break-system-packages 2>/dev/null || \
        pip3 install --user requests python-dotenv 2>/dev/null || \
        pip3 install requests python-dotenv
        echo -e "${GREEN}✅ Packages installed via pip${NC}"
    fi
else
    # Fallback to pip
    echo -e "${CYAN}   Using pip...${NC}"
    pip3 install requests python-dotenv --break-system-packages 2>/dev/null || \
    pip3 install --user requests python-dotenv 2>/dev/null || \
    pip3 install requests python-dotenv
    echo -e "${GREEN}✅ Packages installed via pip${NC}"
fi

# Check if .env exists
if [ ! -f ".env" ]; then
    echo -e "\n${CYAN}📝 Creating .env file with FlipBook credentials${NC}"
    echo -e "${YELLOW}You need your FlipBook API credentials.${NC}"
    echo ""
    
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
URL=""
MAX_PDFS=""
SAVE_SCRIPT_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --max)
            MAX_PDFS="$2"
            shift 2
            ;;
        --save-script)
            SAVE_SCRIPT_ONLY=true
            shift
            ;;
        --help|-h)
            echo -e "\n${YELLOW}Usage:${NC}"
            echo "  $0 <archive.org-url> [options]"
            echo ""
            echo -e "${YELLOW}Options:${NC}"
            echo "  --max N          Maximum number of PDFs to process"
            echo "  --save-script    Only save the download script, don't upload"
            echo "  --help           Show this help message"
            echo ""
            echo -e "${YELLOW}Examples:${NC}"
            echo "  $0 https://archive.org/details/Tekken3PrimasOfficialStrategyGuide1998"
            echo "  $0 https://archive.org/details/Tekken3PrimasOfficialStrategyGuide1998 --max 5"
            echo "  $0 https://archive.org/details/Tekken3PrimasOfficialStrategyGuide1998 --save-script"
            echo ""
            exit 0
            ;;
        *)
            URL="$1"
            shift
            ;;
    esac
done

if [ -z "$URL" ]; then
    echo -e "${RED}❌ No URL provided!${NC}"
    echo -e "${YELLOW}Usage: $0 <archive.org-url> [--max N] [--save-script]${NC}"
    exit 1
fi

echo -e "\n${CYAN}📋 Configuration:${NC}"
echo "   FlipBook Domain: $DOMAIN"
if [ -n "$TOKEN_API" ]; then
    echo "   API Token: ✅ Set"
else
    echo "   API Token: ❌ Not set (public access)"
fi
echo "   Archive URL: $URL"
[ -n "$MAX_PDFS" ] && echo "   Max PDFs: $MAX_PDFS"
[ "$SAVE_SCRIPT_ONLY" = true ] && echo "   Mode: Save script only"
echo ""

# Create the Python pipeline script
echo -e "${CYAN}📄 Creating pipeline script...${NC}"

cat > archive_pipeline.py << 'PYEOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PC Zone Magazine Pipeline - Single Link Mode
Takes ONE Archive.org details URL as input and finds all PDFs
"""

import os
import sys
import time
import json
import re
import requests
from datetime import datetime
from dotenv import load_dotenv

# Load .env file
load_dotenv()

# Configuration from .env
API_TOKEN = os.getenv('TOKEN_API', '')
DOMAIN = os.getenv('DOMAIN', 'https://flipbook.gitgpt.chat').rstrip('/')

# Built-in FlipBook client (no external import)
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
                # Read the file content
                file_content = f.read()
                file_name = os.path.basename(pdf_path)
                
                # Create multipart form data - use 'pdf' as the field name (NOT 'file')
                files = {
                    'pdf': (file_name, file_content, 'application/pdf')
                }
                
                # Make the request with the file
                response = self.session.post(url, files=files, timeout=60)
                
                if response.status_code == 200:
                    try:
                        data = response.json()
                        job_id = data.get('job_id')
                        if job_id:
                            return job_id
                        else:
                            print("Upload response missing job_id: " + str(data))
                            return None
                    except ValueError as e:
                        print("Failed to parse JSON response: " + str(e))
                        print("Response: " + response.text[:200])
                        return None
                else:
                    print("Upload failed: " + str(response.status_code))
                    try:
                        error_data = response.json()
                        print("Error details: " + str(error_data))
                    except:
                        print("Response: " + response.text[:200])
                    return None
        except Exception as e:
            print("Upload error: " + str(e))
            return None

def fetch_item_details(item_url):
    """Fetch item details from Archive.org for a single URL"""
    # Extract identifier from URL
    if 'archive.org/details/' in item_url:
        identifier = item_url.split('/details/')[-1].split('/')[0].split('?')[0]
    elif 'archive.org/download/' in item_url:
        identifier = item_url.split('/download/')[-1].split('/')[0].split('?')[0]
    else:
        identifier = item_url.strip('/')
    
    print("Fetching item: " + identifier)
    
    # Get item metadata
    metadata_url = "https://archive.org/metadata/" + identifier
    try:
        response = requests.get(metadata_url, timeout=30)
        if response.status_code == 200:
            return response.json()
        else:
            print("Failed to fetch metadata: " + str(response.status_code))
            return None
    except Exception as e:
        print("Error fetching metadata: " + str(e))
        return None

def find_pdfs_in_item(item_data):
    """Extract all PDF files from a single Archive.org item"""
    if not item_data or 'files' not in item_data:
        return []
    
    pdf_files = []
    identifier = item_data['metadata']['identifier']
    base_url = "https://archive.org/download/" + identifier
    
    for file_info in item_data['files']:
        file_name = file_info.get('name', '')
        file_ext = os.path.splitext(file_name)[1].lower()
        
        if file_ext == '.pdf':
            # Handle size safely
            file_size = file_info.get('size', 0)
            try:
                if isinstance(file_size, str):
                    file_size = int(file_size) if file_size.isdigit() else 0
                else:
                    file_size = int(file_size) if file_size else 0
            except (ValueError, TypeError):
                file_size = 0
            
            size_mb = file_size / (1024 * 1024) if file_size else 0
            
            pdf_files.append({
                'title': file_name.replace('.pdf', ''),
                'file_url': base_url + "/" + file_name,
                'file_name': file_name,
                'file_type': 'PDF',
                'size_bytes': file_size,
                'size_mb': round(size_mb, 2)
            })
    
    # Sort by file name
    pdf_files.sort(key=lambda x: x['file_name'])
    return pdf_files

def check_queue_status():
    """Check current queue status"""
    api_url = DOMAIN + "/api/jobs"
    try:
        response = requests.get(api_url, timeout=10)
        if response.status_code == 200:
            return response.json()
        return None
    except:
        return None

def wait_for_queue_space(max_waiting=2):
    """Wait until queue has space (waiting < max_waiting)"""
    while True:
        status = check_queue_status()
        if status:
            waiting = status.get('counts', {}).get('waiting', 0)
            active = status.get('counts', {}).get('active', 0)
            print("   Queue status: " + str(waiting) + " waiting, " + str(active) + " active")
            
            if waiting < max_waiting:
                return True
            else:
                print("   Queue full (" + str(waiting) + " waiting). Waiting 10 seconds...")
                time.sleep(10)
        else:
            # If can't check queue, assume it's fine
            return True

def wait_for_job_completion(flipbook_client, job_id, file_name, timeout=600):
    """Wait for a specific job to complete"""
    start_time = time.time()
    last_percent = -1
    last_stage = ''
    
    while time.time() - start_time < timeout:
        try:
            progress_url = flipbook_client.base_url + "/api/progress/" + job_id
            response = flipbook_client.session.get(progress_url, timeout=30)
            
            if response.status_code == 200:
                data = response.json()
                stage = data.get('stage', 'unknown')
                percent = data.get('percent', 0)
                
                # Only print when something changes
                if percent != last_percent or stage != last_stage:
                    if stage == 'converting':
                        current_page = data.get('currentPage', 0)
                        total_pages = data.get('totalPages', 0)
                        # Use \r to update same line
                        print(f"      Converting: {percent}% - Page {current_page}/{total_pages}", end='\r', flush=True)
                    elif stage == 'complete':
                        print("\n      Conversion complete!")  # New line after completion
                        
                        # Fetch the URL from history
                        history_url = flipbook_client.base_url + "/api/history"
                        history_resp = flipbook_client.session.get(history_url, timeout=10)
                        if history_resp.status_code == 200:
                            history_data = history_resp.json()
                            if history_data.get('history') and len(history_data['history']) > 0:
                                latest = history_data['history'][0]
                                print("      URL: " + flipbook_client.base_url + latest.get('html_url', ''))
                                return {
                                    'html_url': latest.get('html_url'),
                                    'zip_url': latest.get('zip_url'),
                                    'title': latest.get('title'),
                                    'page_count': latest.get('page_count')
                                }
                        
                        print("      URL: " + flipbook_client.base_url + "/api/history")
                        return {'html_url': flipbook_client.base_url + "/api/history"}
                        
                    elif stage == 'error':
                        print("\n      Error: " + data.get('error', 'Unknown'))
                        return None
                    
                    last_percent = percent
                    last_stage = stage
        except Exception as e:
            pass  # Silent fail for progress checks
        
        time.sleep(3)
    
    print("\n      Timeout after " + str(timeout) + " seconds")
    return None

def download_pdf_with_progress(url, local_path, display_name):
    """Download PDF with progress bar"""
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
                            print(f"      Download: {percent}%", end='\r', flush=True)
                            last_percent = percent
        
        print()  # New line after download
        return True
    except Exception as e:
        print(f"      Download failed: {str(e)}")
        return False

def sanitize_filename(name):
    """Clean filename for saving"""
    name = re.sub(r'[\\/*?:"<>|]', '', name)
    name = name.replace(' ', '_')
    if len(name) > 100:
        name = name[:100]
    return name

def generate_downloader_script(pdf_files, identifier):
    """Generate a bash script to download all PDFs"""
    if not pdf_files:
        return None
    
    safe_name = sanitize_filename(identifier)
    output_file = safe_name + "_download_pdf.sh"
    
    with open(output_file, 'w') as f:
        f.write("#!/bin/bash\n")
        f.write("# Auto-generated download script for: " + identifier + "\n")
        f.write("# Generated: " + datetime.now().strftime('%Y-%m-%d %H:%M:%S') + "\n")
        f.write("# Total PDFs: " + str(len(pdf_files)) + "\n\n")
        
        folder_name = safe_name + "_pdfs"
        f.write("mkdir -p " + folder_name + "\n\n")
        
        for i, pdf in enumerate(pdf_files, 1):
            filename = safe_name + "_" + str(i).zfill(3) + ".pdf"
            f.write('echo "Downloading ' + filename + '..."\n')
            f.write('wget -O ' + folder_name + '/' + filename + ' "' + pdf["file_url"] + '"\n')
            f.write("sleep 1\n\n")
    
    os.chmod(output_file, 0o755)
    print("Generated download script: " + output_file)
    return output_file

def run_pipeline_single_link(item_url, max_pdfs=None):
    """Complete pipeline for a single Archive.org item"""
    
    print("\n" + "="*80)
    print("MAGAZINE PIPELINE - SINGLE LINK MODE")
    print("="*80)
    print("FlipBook Domain: " + DOMAIN)
    print("API Token: " + ('Set' if API_TOKEN else 'Not set (public access)'))
    print("Archive Link: " + item_url)
    print("Max PDFs: " + (str(max_pdfs) if max_pdfs else 'All'))
    print("="*80 + "\n")
    
    # Step 1: Fetch item details
    print("STEP 1: Fetching item from Archive.org...")
    item_data = fetch_item_details(item_url)
    
    if not item_data:
        print("Failed to fetch item details!")
        return
    
    identifier = item_data['metadata']['identifier']
    title = item_data['metadata'].get('title', identifier)
    print("Found item: " + title)
    
    # Step 2: Find all PDFs
    print("\nSTEP 2: Finding PDF files...")
    pdf_files = find_pdfs_in_item(item_data)
    
    if not pdf_files:
        print("No PDF files found in this item!")
        return
    
    print("\nFound " + str(len(pdf_files)) + " PDF files")
    
    total_size_mb = sum(p['size_mb'] for p in pdf_files)
    print("Total size: " + str(round(total_size_mb, 1)) + " MB")
    
    for i, pdf in enumerate(pdf_files[:5], 1):
        print("   " + str(i) + ". " + pdf['file_name'] + " (" + str(pdf['size_mb']) + " MB)")
    if len(pdf_files) > 5:
        print("   ... and " + str(len(pdf_files) - 5) + " more")
    
    # Limit if specified
    if max_pdfs and max_pdfs < len(pdf_files):
        pdf_files = pdf_files[:max_pdfs]
        print("\nLimited to first " + str(max_pdfs) + " PDFs")
    
    # Step 3: Generate download script
    print("\nSTEP 3: Saving download script...")
    script_file = generate_downloader_script(pdf_files, identifier)
    
    # Step 4: Initialize FlipBook client
    print("\nSTEP 4: Initializing FlipBook API...")
    flipbook = FlipBookClient()
    
    # Create temp folder
    temp_folder = "temp_pdfs"
    if not os.path.exists(temp_folder):
        os.makedirs(temp_folder)
    
    # Step 5: Process each PDF
    print("\nSTEP 5: Processing " + str(len(pdf_files)) + " PDFs (one by one)\n")
    print("="*80)
    
    successful = 0
    failed = 0
    log_file = sanitize_filename(identifier) + "_converted.txt"
    
    for i, pdf_item in enumerate(pdf_files, 1):
        print("\n[" + str(i) + "/" + str(len(pdf_files)) + "] Processing: " + pdf_item['title'][:60] + "...")
        
        wait_for_queue_space()
        
        pdf_url = pdf_item['file_url']
        filename = sanitize_filename(pdf_item['title']) + ".pdf"
        local_path = os.path.join(temp_folder, filename)
        

        print(f"   Downloading PDF ({pdf_item['size_mb']} MB)...")
        if download_pdf_with_progress(pdf_url, local_path, pdf_item['title']):
            size_mb = os.path.getsize(local_path) / (1024 * 1024)
            print(f"      Downloaded ({round(size_mb, 1)} MB)")
        else:
            failed += 1
            continue
        
        print("   Uploading to FlipBook...")
        job_id = flipbook.upload_pdf(local_path)
        
        if job_id:
            print("      Uploaded! Job ID: " + job_id)
            print("   Waiting for conversion...")
            result = wait_for_job_completion(flipbook, job_id, filename)
            
            if result:
                successful += 1
                print("      Flipbook ready!")
                print("      URL: " + str(result.get('html_url')))
                
                with open(log_file, "a") as f:
                    f.write(pdf_item['title'] + "|" + str(result.get('html_url')) + "|" + pdf_url + "\n")
                
                with open("converted_flipbooks.txt", "a") as f:
                    f.write(identifier + "|" + pdf_item['title'] + "|" + str(result.get('html_url')) + "|" + pdf_url + "\n")
            else:
                failed += 1
                print("      Conversion failed or timed out")
        else:
            failed += 1
            print("      Upload failed")
        
        if os.path.exists(local_path):
            os.unlink(local_path)
            print("   Deleted local file")
        
        time.sleep(2)
    
    # Final summary
    print("\n" + "="*80)
    print("PIPELINE COMPLETE!")
    print("="*80)
    print("Results for: " + title)
    print("   Successful conversions: " + str(successful))
    print("   Failed: " + str(failed))
    print("   Log file: " + log_file)
    if script_file:
        print("   Download script: " + script_file)
    print("="*80 + "\n")

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description='Process ALL PDFs from a single Archive.org item')
    parser.add_argument('url', type=str, nargs='?', help='Archive.org details URL')
    parser.add_argument('--max', '-m', type=int, default=None, help='Maximum number of PDFs to process')
    parser.add_argument('--save-script-only', action='store_true', help='Only save the download script')
    
    args = parser.parse_args()
    
    if not args.url:
        print("\nPlease provide an Archive.org details URL")
        print("\nUsage: python3 archive_pipeline.py https://archive.org/details/Tekken3PrimasOfficialStrategyGuide1998")
        sys.exit(1)
    
    if args.save_script_only:
        print("\nSaving download script only...")
        item_data = fetch_item_details(args.url)
        if item_data:
            pdf_files = find_pdfs_in_item(item_data)
            if pdf_files:
                identifier = item_data['metadata']['identifier']
                generate_downloader_script(pdf_files, identifier)
                print("\nSaved " + str(len(pdf_files)) + " PDF links to script")
        sys.exit(0)
    
    run_pipeline_single_link(args.url, max_pdfs=args.max)
PYEOF

chmod +x archive_pipeline.py

# Build command
CMD="python3 -u archive_pipeline.py \"$URL\""

if [ -n "$MAX_PDFS" ]; then
    CMD="$CMD --max $MAX_PDFS"
fi

if [ "$SAVE_SCRIPT_ONLY" = true ]; then
    CMD="$CMD --save-script-only"
fi

# Run the pipeline
echo -e "${CYAN}🚀 Running pipeline...${NC}"
echo -e "${YELLOW}   Press Ctrl+C to cancel${NC}"
echo ""

eval $CMD

# Show next steps
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "\n${GREEN}✅ Pipeline completed successfully!${NC}"
    echo -e "\n${CYAN}💡 Next steps:${NC}"
    echo "  1. Check converted flipbooks in converted_flipbooks.txt"
    echo "  2. Use the download script to get all PDFs"
    echo "  3. Run again with different URL to process more"
else
    echo -e "\n${YELLOW}⚠️ Pipeline exited with code: $EXIT_CODE${NC}"
fi