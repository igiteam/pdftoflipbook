#!/bin/bash

# DigitalOcean Spaces - Universal Flipbook Uploader
# FIXED: No set -e, proper error handling, retry logic

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
echo "║     DigitalOcean Spaces - Flipbook Uploader                  ║"
echo "║     Uploads ALL flipbooks to a SINGLE flat folder           ║"
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
    apt-get install -y python3-boto3 python3-requests python3-dotenv 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Packages installed via apt${NC}"
    else
        echo -e "${YELLOW}⚠️ Apt install failed, trying pip...${NC}"
        pip3 install boto3 requests python-dotenv --break-system-packages 2>/dev/null || \
        pip3 install --user boto3 requests python-dotenv 2>/dev/null || \
        pip3 install boto3 requests python-dotenv
        echo -e "${GREEN}✅ Packages installed via pip${NC}"
    fi
else
    # Fallback to pip
    echo -e "${CYAN}   Using pip...${NC}"
    pip3 install boto3 requests python-dotenv --break-system-packages 2>/dev/null || \
    pip3 install --user boto3 requests python-dotenv 2>/dev/null || \
    pip3 install boto3 requests python-dotenv
    echo -e "${GREEN}✅ Packages installed via pip${NC}"
fi

# Check if .env exists
if [ ! -f ".env" ]; then
    echo -e "\n${CYAN}📝 Creating .env file with DO Spaces credentials${NC}"
    echo -e "${YELLOW}You need DigitalOcean Spaces credentials.${NC}"
    echo -e "${YELLOW}Get them from: https://cloud.digitalocean.com/account/api/tokens${NC}"
    echo ""
    
    read -p "Enter your DO Spaces Access Key: " DO_ACCESS_KEY
    read -p "Enter your DO Spaces Secret Key: " DO_SECRET_KEY
    read -p "Enter your DO API Token (for CDN purge): " DO_API_TOKEN
    read -p "Enter bucket name [sdappnet-cloud]: " DO_BUCKET
    DO_BUCKET=${DO_BUCKET:-sdappnet-cloud}
    read -p "Enter endpoint [https://fra1.digitaloceanspaces.com]: " DO_ENDPOINT
    DO_ENDPOINT=${DO_ENDPOINT:-https://fra1.digitaloceanspaces.com}
    read -p "Enter region [fra1]: " DO_REGION
    DO_REGION=${DO_REGION:-fra1}
    read -p "Enter CDN endpoint [https://cdn.gitgpt.chat]: " DO_CDN
    DO_CDN=${DO_CDN:-https://cdn.gitgpt.chat}
    read -p "Enter CDN ID (optional, leave blank to auto-detect): " DO_CDN_ID
    
    echo ""
    echo -e "${CYAN}📁 Where should files go on DO Spaces?${NC}"
    echo -e "${YELLOW}Example: rtx/pc-zone, rtx/xbox, rtx/nintendo${NC}"
    read -p "Enter destination folder: " DO_FOLDER
    
    if [ -z "$DO_FOLDER" ]; then
        echo -e "${RED}❌ Folder name is required!${NC}"
        exit 1
    fi
    
    cat > .env << EOF
# DigitalOcean Spaces Credentials
DO_SPACES_ACCESS_KEY=$DO_ACCESS_KEY
DO_SPACES_SECRET_KEY=$DO_SECRET_KEY
DO_API_TOKEN=$DO_API_TOKEN
DO_CDN_ID=$DO_CDN_ID

# Space Configuration
DO_SPACES_BUCKET=$DO_BUCKET
DO_SPACES_ENDPOINT=$DO_ENDPOINT
DO_SPACES_REGION=$DO_REGION
DO_SPACES_CDN_ENDPOINT=$DO_CDN
DO_SPACES_FOLDER=$DO_FOLDER
DO_SPACES_MAKE_PUBLIC=true
EOF

    chmod 600 .env
    echo -e "${GREEN}✅ .env file created!${NC}"
else
    echo -e "${GREEN}✅ .env file found${NC}"
    
    CURRENT_FOLDER=$(grep DO_SPACES_FOLDER .env 2>/dev/null | cut -d= -f2)
    echo -e "${CYAN}📁 Current destination folder: $CURRENT_FOLDER${NC}"
    
    echo ""
    read -p "Change destination folder? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Enter new destination folder (e.g., rtx/pc-zone): " DO_FOLDER
        if [ -n "$DO_FOLDER" ]; then
            sed -i "s/^DO_SPACES_FOLDER=.*/DO_SPACES_FOLDER=$DO_FOLDER/" .env
            echo -e "${GREEN}✅ Updated folder to: $DO_FOLDER${NC}"
        fi
    fi
fi

# Get the folder from .env
DO_FOLDER=$(grep DO_SPACES_FOLDER .env | cut -d= -f2)

# Count flipbook folders
FLIPBOOK_COUNT=$(find . -maxdepth 1 -type d -name "flipbook_*" 2>/dev/null | wc -l)

if [ "$FLIPBOOK_COUNT" -eq 0 ]; then
    echo -e "${RED}❌ No flipbook_* folders found in current directory!${NC}"
    echo -e "${YELLOW}   Make sure you're in the right directory (e.g., /var/www/flipbook/output)${NC}"
    exit 1
fi

echo -e "\n${CYAN}📂 Found $FLIPBOOK_COUNT flipbook folders${NC}"

# Count all files
TOTAL_FILES=$(find flipbook_*/ -type f ! -name "*.zip" 2>/dev/null | wc -l)
HTML_COUNT=$(find flipbook_*/ -name "*.html" -type f 2>/dev/null | wc -l)
PNG_COUNT=$(find flipbook_*/ -name "*.png" -type f 2>/dev/null | wc -l)

# Calculate total size in GB
TOTAL_SIZE_BYTES=$(find flipbook_*/ -type f ! -name "*.zip" -exec du -b {} + 2>/dev/null | awk '{sum+=$1} END {print sum}')
TOTAL_SIZE_GB=$(echo "scale=2; $TOTAL_SIZE_BYTES / 1024 / 1024 / 1024" | bc)

# Get size breakdown
HTML_SIZE_BYTES=$(find flipbook_*/ -name "*.html" -type f -exec du -b {} + 2>/dev/null | awk '{sum+=$1} END {print sum}')
PNG_SIZE_BYTES=$(find flipbook_*/ -name "*.png" -type f -exec du -b {} + 2>/dev/null | awk '{sum+=$1} END {print sum}')

HTML_SIZE_GB=$(echo "scale=2; $HTML_SIZE_BYTES / 1024 / 1024 / 1024" | bc)
PNG_SIZE_GB=$(echo "scale=2; $PNG_SIZE_BYTES / 1024 / 1024 / 1024" | bc)

echo -e "\n${CYAN}📊 Files to upload:${NC}"
echo "   📄 HTML: $HTML_COUNT files ($HTML_SIZE_GB GB)"
echo "   🖼️ PNG: $PNG_COUNT files ($PNG_SIZE_GB GB)"
echo "   📦 Total: $TOTAL_FILES files ($TOTAL_SIZE_GB GB)"
echo "   📁 Destination: $DO_FOLDER/"
echo "   🌐 CDN: $(grep DO_SPACES_CDN_ENDPOINT .env | cut -d= -f2)/$DO_FOLDER/"


# Check upload log
if [ -f ".upload_log.json" ]; then
    UPLOADED=$(grep -o '"total_uploaded": [0-9]*' .upload_log.json 2>/dev/null | cut -d' ' -f2)
    if [ -n "$UPLOADED" ]; then
        echo -e "\n${GREEN}📋 Resume detected: $UPLOADED files already uploaded${NC}"
        REMAINING=$((TOTAL_FILES - UPLOADED))
        echo -e "${YELLOW}   Remaining: $REMAINING files${NC}"
    fi
fi

# Confirm upload
echo -e "\n${YELLOW}⚠️ Will upload $TOTAL_FILES files to DO Spaces${NC}"
echo -e "${CYAN}💡 Press Ctrl+C at any time to pause - you can resume later!${NC}"
echo ""

read -p "Continue with upload? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Upload cancelled."
    exit 0
fi

# Create the Python uploader script
echo -e "\n${CYAN}📄 Creating uploader script...${NC}"

cat > uploader.py << 'PYEOF'
#!/usr/bin/env python3
"""
Flipbook Uploader for DigitalOcean Spaces
Uploads ALL files from flipbook_*/ folders to a SINGLE flat folder
No renaming - keeps original filenames
"""

import os
import sys
import time
import json
import mimetypes
import requests
from pathlib import Path
from typing import List, Tuple, Dict, Any
from datetime import datetime
from dotenv import load_dotenv
import boto3
from botocore.client import Config

load_dotenv()

# Configuration
ACCESS_KEY = os.getenv("DO_SPACES_ACCESS_KEY")
SECRET_KEY = os.getenv("DO_SPACES_SECRET_KEY")
BUCKET = os.getenv("DO_SPACES_BUCKET", "sdappnet-cloud")
ENDPOINT = os.getenv("DO_SPACES_ENDPOINT", "https://fra1.digitaloceanspaces.com")
REGION = os.getenv("DO_SPACES_REGION", "fra1")
CDN_ENDPOINT = os.getenv("DO_SPACES_CDN_ENDPOINT", "https://cdn.gitgpt.chat")
BASE_FOLDER = os.getenv("DO_SPACES_FOLDER", "rtx/magazines")
MAKE_PUBLIC = os.getenv("DO_SPACES_MAKE_PUBLIC", "true").lower() == "true"
API_TOKEN = os.getenv("DO_API_TOKEN")
CDN_ID = os.getenv("DO_CDN_ID")

UPLOAD_LOG = ".upload_log.json"

class Colors:
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    CYAN = '\033[0;36m'
    RED = '\033[0;31m'
    MAGENTA = '\033[0;35m'
    NC = '\033[0m'

def get_content_type(filepath: str) -> str:
    mime_type, _ = mimetypes.guess_type(filepath)
    if mime_type:
        return mime_type
    ext = Path(filepath).suffix.lower()
    content_types = {
        '.html': 'text/html',
        '.png': 'image/png',
        '.jpg': 'image/jpeg',
        '.jpeg': 'image/jpeg',
    }
    return content_types.get(ext, 'application/octet-stream')

def get_all_files() -> List[str]:
    """Get ALL files from ALL flipbook_*/ folders (flattened)"""
    files = []
    for root, dirs, files_in_dir in os.walk('.'):
        if not root.startswith('./flipbook_') and root != '.':
            continue
        for file in files_in_dir:
            if file.endswith('.zip') or file in ['.upload_log.json', '.env', 'uploader.py']:
                continue
            filepath = os.path.join(root, file)
            files.append(filepath)
    return sorted(files)

def load_upload_log() -> Dict[str, Any]:
    if os.path.exists(UPLOAD_LOG):
        try:
            with open(UPLOAD_LOG, 'r', encoding='utf-8') as f:
                log = json.load(f)
                log.setdefault('uploaded_files', {})
                log.setdefault('last_run', None)
                log.setdefault('total_uploaded', 0)
                return log
        except:
            pass
    return {'uploaded_files': {}, 'last_run': None, 'total_uploaded': 0}

def save_upload_log(log: Dict[str, Any]) -> None:
    log['last_run'] = datetime.now().isoformat()
    with open(UPLOAD_LOG, 'w', encoding='utf-8') as f:
        json.dump(log, f, indent=2, ensure_ascii=False)

def get_cdn_id(api_token: str, bucket: str) -> str | None:
    try:
        headers = {"Authorization": f"Bearer {api_token}", "Content-Type": "application/json"}
        response = requests.get("https://api.digitalocean.com/v2/cdn/endpoints", headers=headers)
        if response.status_code == 200:
            endpoints = response.json().get("endpoints", [])
            for endpoint in endpoints:
                origin = endpoint.get("origin", "")
                if bucket in origin:
                    return endpoint.get("id")
        return None
    except Exception as e:
        print(f"{Colors.YELLOW}⚠️ Could not auto-detect CDN ID: {e}{Colors.NC}")
        return None

def purge_single_file(api_token: str, cdn_id: str, file_key: str, max_retries: int = 5) -> Tuple[bool, int]:
    headers = {"Authorization": f"Bearer {api_token}", "Content-Type": "application/json"}
    payload = {"files": [file_key]}
    
    for attempt in range(max_retries):
        try:
            response = requests.delete(
                f"https://api.digitalocean.com/v2/cdn/endpoints/{cdn_id}/cache",
                headers=headers, json=payload, timeout=30
            )
            if response.status_code in [200, 204]:
                return True, attempt + 1
            if attempt < max_retries - 1:
                wait_time = (attempt + 1) * 2
                print(f"     ⏳ Retry {attempt + 1}/{max_retries} in {wait_time}s")
                time.sleep(wait_time)
        except Exception as e:
            if attempt < max_retries - 1:
                wait_time = (attempt + 1) * 2
                print(f"     ⏳ Retry {attempt + 1}/{max_retries} in {wait_time}s")
                time.sleep(wait_time)
    return False, max_retries

def upload_file(s3_client, local_path: str, bucket: str, key: str) -> Tuple[bool, str]:
    try:
        content_type = get_content_type(local_path)
        extra_args = {'ContentType': content_type}
        if MAKE_PUBLIC:
            extra_args['ACL'] = 'public-read'
        with open(local_path, 'rb') as f:
            s3_client.upload_fileobj(f, bucket, key, ExtraArgs=extra_args)
        return True, f"{CDN_ENDPOINT}/{key}"
    except Exception as e:
        return False, str(e)

def main():
    print(f"{Colors.MAGENTA}")
    print("╔═══════════════════════════════════════════════════════════════╗")
    print("║     Flipbook Uploader - DO Spaces                            ║")
    print("║     Uploads ALL files to a SINGLE flat folder               ║")
    print("╚═══════════════════════════════════════════════════════════════╝")
    print(f"{Colors.NC}")
    
    if not ACCESS_KEY or not SECRET_KEY:
        print(f"{Colors.RED}❌ Missing credentials in .env{Colors.NC}")
        sys.exit(1)
    
    all_files = get_all_files()
    
    if not all_files:
        print(f"{Colors.RED}❌ No files found in flipbook_*/ folders!{Colors.NC}")
        sys.exit(1)
    
    upload_log = load_upload_log()
    uploaded_files = set(upload_log['uploaded_files'].keys())
    
    pending_files = []
    for f in all_files:
        filename = os.path.basename(f)
        if filename not in uploaded_files:
            pending_files.append(f)
    
    print(f"{Colors.GREEN}📊 Found:{Colors.NC}")
    print(f"   📁 Total files: {len(all_files)}")
    print(f"   ✅ Already uploaded: {len(all_files) - len(pending_files)}")
    print(f"   📤 Pending: {len(pending_files)}")
    
    if not pending_files:
        print(f"{Colors.GREEN}✅ All files already uploaded!{Colors.NC}")
        sys.exit(0)
    
    s3_client = boto3.client('s3', endpoint_url=ENDPOINT, region_name=REGION,
                            aws_access_key_id=ACCESS_KEY, aws_secret_access_key=SECRET_KEY,
                            config=Config(signature_version='s3v4'))
    
    cdn_id = CDN_ID
    if API_TOKEN and not cdn_id:
        print(f"{Colors.CYAN}🔍 Auto-detecting CDN ID...{Colors.NC}")
        cdn_id = get_cdn_id(API_TOKEN, BUCKET)
        if cdn_id:
            print(f"{Colors.GREEN}✅ Detected CDN ID: {cdn_id}{Colors.NC}")
    
    print(f"\n{Colors.CYAN}☁️ Uploading {len(pending_files)} files to {BASE_FOLDER}/...{Colors.NC}")
    print(f"   {Colors.YELLOW}⚠️ Press Ctrl+C to pause and save progress{Colors.NC}\n")
    
    uploaded_count = 0
    failed_count = 0
    purge_failed = 0
    new_uploads = []
    
    try:
        for idx, local_file in enumerate(pending_files, 1):
            filename = os.path.basename(local_file)
            key = f"{BASE_FOLDER}/{filename}"
            
            ext = Path(filename).suffix.lower()
            icon = "📄" if ext == '.html' else "🖼️"
            
            print(f"  [{idx}/{len(pending_files)}] {icon} {filename}")
            
            success, result = upload_file(s3_client, local_file, BUCKET, key)
            
            if success:
                uploaded_count += 1
                new_uploads.append((filename, key, result))
                print(f"     ✅ Uploaded")
                
                if API_TOKEN and cdn_id:
                    purge_success, attempts = purge_single_file(API_TOKEN, cdn_id, key)
                    if purge_success:
                        print(f"     ✅ CDN cache cleared")
                    else:
                        purge_failed += 1
                        print(f"     ⚠️ CDN purge FAILED")
                    time.sleep(0.3)
                
                if len(new_uploads) % 10 == 0:
                    for fname, fkey, furl in new_uploads:
                        upload_log['uploaded_files'][fname] = {
                            'key': fkey,
                            'url': furl,
                            'uploaded_at': datetime.now().isoformat()
                        }
                    upload_log['total_uploaded'] = len(upload_log['uploaded_files'])
                    save_upload_log(upload_log)
                    print(f"  💾 Progress saved ({upload_log['total_uploaded']} files)")
            else:
                failed_count += 1
                print(f"     ❌ Failed: {result}")
                
    except KeyboardInterrupt:
        print(f"\n\n{Colors.YELLOW}⚠️ Paused! Saving progress...{Colors.NC}")
        for fname, fkey, furl in new_uploads:
            upload_log['uploaded_files'][fname] = {
                'key': fkey,
                'url': furl,
                'uploaded_at': datetime.now().isoformat()
            }
        upload_log['total_uploaded'] = len(upload_log['uploaded_files'])
        save_upload_log(upload_log)
        print(f"{Colors.GREEN}✅ Progress saved! {upload_log['total_uploaded']} files uploaded{Colors.NC}")
        print(f"{Colors.CYAN}💡 Run again to resume where you left off.{Colors.NC}")
        sys.exit(0)
    
    for fname, fkey, furl in new_uploads:
        upload_log['uploaded_files'][fname] = {
            'key': fkey,
            'url': furl,
            'uploaded_at': datetime.now().isoformat()
        }
    upload_log['total_uploaded'] = len(upload_log['uploaded_files'])
    save_upload_log(upload_log)
    
    print(f"\n{Colors.GREEN}{'='*60}{Colors.NC}")
    print(f"{Colors.GREEN}✅ Upload Complete!{Colors.NC}")
    print(f"{Colors.GREEN}{'='*60}{Colors.NC}")
    print(f"📤 Uploaded this session: {uploaded_count}")
    print(f"❌ Failed: {failed_count}")
    print(f"⚠️ CDN purge failed: {purge_failed}")
    print(f"📁 Total uploaded all time: {upload_log['total_uploaded']}")
    print(f"📋 Log: {UPLOAD_LOG}")
    print(f"\n🔗 All files at: {CDN_ENDPOINT}/{BASE_FOLDER}/")

if __name__ == "__main__":
    main()
PYEOF

chmod +x uploader.py

# Run the uploader with proper error handling
echo -e "\n${CYAN}🚀 Starting uploader...${NC}"
echo -e "${YELLOW}   Press Ctrl+C to pause and resume later${NC}"
echo ""

# Run with unbuffered output so we can see everything
python3 -u uploader.py

# Show next steps
echo -e "\n${CYAN}💡 Next steps:${NC}"
echo "  1. Check uploaded files: $(grep DO_SPACES_CDN_ENDPOINT .env 2>/dev/null | cut -d= -f2 2>/dev/null)/$DO_FOLDER/"
echo "  2. Resume if cancelled: ./upload-to-dospaces.sh"
echo "  3. View log: cat .upload_log.json"
echo -e "\n${GREEN}✅ Done!${NC}"