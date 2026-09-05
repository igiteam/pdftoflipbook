#!/bin/bash

# ============================================
# Archive.org Uploader - Strategy Guides
# ============================================

# ========== CONFIGURATION ==========
# Default identifier (change this to your preferred identifier)
DEFAULT_IDENTIFIER="strategy-guides-archive"

# Default collection settings
DEFAULT_TITLE="Strategy Guide Archive - Prima, BradyGames, Nintendo Power & More"
DEFAULT_DESCRIPTION="Massive collection of video game strategy guides from multiple publishers. Includes Prima Official Strategy Guides, BradyGames, Nintendo Power, Piggyback, DoubleJump, Future Press, and many more. Covers NES to PS4 era."
DEFAULT_CREATOR="Strategy Guide Preservation Project"
DEFAULT_COLLECTION="opensource"
DEFAULT_LANGUAGE="eng"
DEFAULT_SUBJECT="video games; strategy guides; walkthroughs; Prima; BradyGames; Nintendo Power; retro gaming; game guides"
DEFAULT_YEAR="1989-2018"
DEFAULT_LICENSE="https://creativecommons.org/publicdomain/zero/1.0/"
DEFAULT_TOTAL_ITEMS="2800+"
DEFAULT_TOTAL_SIZE_GB="107"

# ============================================

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
echo "║     Archive.org Uploader - Strategy Guides                   ║"
echo "║     Uploads PDF and CBZ files to Archive.org                ║"
echo "║                                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Use current directory (where script is run from)
CURRENT_DIR="$(pwd)"
echo -e "${CYAN}📁 Working directory: $CURRENT_DIR${NC}"

# Check for Python3
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python3 not found. Please install Python3 first.${NC}"
    exit 1
fi

# Install internetarchive
echo -e "\n${CYAN}📦 Installing internetarchive module...${NC}"
pip3 install internetarchive python-dotenv --break-system-packages 2>/dev/null || \
pip3 install --user internetarchive python-dotenv 2>/dev/null || \
pip3 install internetarchive python-dotenv

# Check if .env exists
if [ ! -f ".env" ]; then
    echo -e "\n${CYAN}📝 Creating .env file with Archive.org credentials${NC}"
    echo -e "${YELLOW}Get your S3 keys from: https://archive.org/account/s3.php${NC}"
    echo ""
    
    read -p "Enter your Archive.org Access Key: " IA_ACCESS_KEY
    read -p "Enter your Archive.org Secret Key: " IA_SECRET_KEY
    
    echo ""
    echo -e "${CYAN}📁 Archive.org item identifier:${NC}"
    echo -e "${YELLOW}This will be the URL: https://archive.org/details/$DEFAULT_IDENTIFIER${NC}"
    
    ITEM_IDENTIFIER="$DEFAULT_IDENTIFIER"
    read -p "Use this identifier? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        read -p "Enter custom identifier (lowercase, no spaces): " ITEM_IDENTIFIER
    fi
    
    cat > .env << EOF
# Archive.org Credentials
IA_ACCESS_KEY=$IA_ACCESS_KEY
IA_SECRET_KEY=$IA_SECRET_KEY

# Collection Settings
ITEM_IDENTIFIER=$ITEM_IDENTIFIER
ITEM_TITLE=$DEFAULT_TITLE
ITEM_DESCRIPTION=$DEFAULT_DESCRIPTION
ITEM_CREATOR=$DEFAULT_CREATOR
ITEM_COLLECTION=$DEFAULT_COLLECTION
ITEM_LANGUAGE=$DEFAULT_LANGUAGE
ITEM_SUBJECT=$DEFAULT_SUBJECT
ITEM_YEAR=$DEFAULT_YEAR
ITEM_LICENSE=$DEFAULT_LICENSE
TOTAL_ITEMS=$DEFAULT_TOTAL_ITEMS
TOTAL_SIZE_GB=$DEFAULT_TOTAL_SIZE_GB
EOF

    chmod 600 .env
    echo -e "${GREEN}✅ .env file created!${NC}"
else
    echo -e "${GREEN}✅ .env file found${NC}"
    
    # Get current identifier with fallback to default
    CURRENT_IDENTIFIER=$(grep ITEM_IDENTIFIER .env 2>/dev/null | cut -d= -f2)
    if [ -z "$CURRENT_IDENTIFIER" ]; then
        CURRENT_IDENTIFIER="$DEFAULT_IDENTIFIER"
        echo -e "${YELLOW}⚠️ No identifier found in .env, using default: $CURRENT_IDENTIFIER${NC}"
    fi
    
    echo -e "${CYAN}📁 Current identifier: $CURRENT_IDENTIFIER${NC}"
    echo -e "${CYAN}🔗 URL: https://archive.org/details/$CURRENT_IDENTIFIER${NC}"
    
    echo ""
    read -p "Use existing .env file? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        rm -f .env
        echo "Please run the script again to recreate .env"
        exit 0
    fi
fi

# Load .env
export $(grep -v '^#' .env | xargs 2>/dev/null || true)

# Detect PDF and CBZ files in current directory
echo -e "\n${CYAN}🔍 Detecting PDF and CBZ files in current directory...${NC}"
PDF_FILES=($(ls -1 *.pdf 2>/dev/null | sort))
CBZ_FILES=($(ls -1 *.cbz 2>/dev/null | sort))
ALL_FILES=("${PDF_FILES[@]}" "${CBZ_FILES[@]}")
# Sort alphabetically
IFS=$'\n' ALL_FILES=($(sort <<<"${ALL_FILES[*]}"))
unset IFS

TOTAL_FILES=${#ALL_FILES[@]}

if [ "$TOTAL_FILES" -eq 0 ]; then
    echo -e "${RED}❌ No PDF or CBZ files found in current directory!${NC}"
    echo -e "${YELLOW}💡 Current directory: $(pwd)${NC}"
    echo -e "${YELLOW}💡 Make sure you're in the directory with your PDF/CBZ files${NC}"
    exit 1
fi

# Count by type
PDF_COUNT=${#PDF_FILES[@]}
CBZ_COUNT=${#CBZ_FILES[@]}

echo -e "${GREEN}✅ Found $TOTAL_FILES total files${NC}"
echo -e "${CYAN}   📄 PDF files: $PDF_COUNT${NC}"
echo -e "${CYAN}   📦 CBZ files: $CBZ_COUNT${NC}"

# Show first 20 files
echo -e "${CYAN}📁 First 20 files:${NC}"
for i in "${!ALL_FILES[@]}"; do
    if [ $i -lt 20 ]; then
        size=$(ls -lh "${ALL_FILES[$i]}" | awk '{print $5}')
        ext="${ALL_FILES[$i]##*.}"
        echo "   $((i+1)). ${ALL_FILES[$i]} ($size) [$ext]"
    fi
done
if [ "$TOTAL_FILES" -gt 20 ]; then
    echo "   ... and $((TOTAL_FILES - 20)) more"
fi

# Calculate total size
total_size=0
for file in "${ALL_FILES[@]}"; do
    size_bytes=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
    total_size=$((total_size + size_bytes))
done
total_size_gb=$(echo "scale=2; $total_size / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "Unknown")
echo -e "\n${CYAN}📊 Total size: $total_size_gb GB${NC}"

# Ask for confirmation before starting
echo ""
read -p "Continue with upload? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Delete old progress file
rm -f upload_progress.json

# Create the Python uploader script
echo -e "\n${CYAN}📄 Creating uploader script...${NC}"

cat > archive_uploader.py << 'PYEOF'
#!/usr/bin/env python3
"""
Archive.org Uploader - Strategy Guides (PDF & CBZ)
"""

import os, sys, json, time, re, tempfile
from datetime import datetime
from typing import List, Dict, Tuple
from dotenv import load_dotenv

load_dotenv()

try:
    import internetarchive as ia
except ImportError:
    print("❌ internetarchive not installed. Run: pip install internetarchive")
    sys.exit(1)

# --- Load ALL config from .env ---
ITEM_IDENTIFIER = os.getenv("ITEM_IDENTIFIER", "strategy-guides-archive")
ITEM_TITLE = os.getenv("ITEM_TITLE", "Strategy Guide Archive")
ITEM_DESCRIPTION = os.getenv("ITEM_DESCRIPTION", "Strategy Guide Archive")
ITEM_CREATOR = os.getenv("ITEM_CREATOR", "Strategy Guide Preservation Project")
ITEM_COLLECTION = os.getenv("ITEM_COLLECTION", "opensource")
ITEM_LANGUAGE = os.getenv("ITEM_LANGUAGE", "eng")
ITEM_SUBJECT = os.getenv("ITEM_SUBJECT", "video games; strategy guides")
ITEM_YEAR = os.getenv("ITEM_YEAR", "1989-2018")
ITEM_LICENSE = os.getenv("ITEM_LICENSE", "https://creativecommons.org/publicdomain/zero/1.0/")

UPLOAD_RETRY_COUNT = 5
LOG_FILE = "upload_progress.json"

class Colors:
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    CYAN = '\033[0;36m'
    RED = '\033[0;31m'
    MAGENTA = '\033[0;35m'
    BOLD = '\033[1m'
    NC = '\033[0m'

def load_progress() -> Dict:
    if os.path.exists(LOG_FILE):
        try:
            with open(LOG_FILE, 'r') as f:
                p = json.load(f)
                p.setdefault('uploaded', [])
                p.setdefault('failed', [])
                p.setdefault('item_created', False)
                return p
        except: pass
    return {'uploaded': [], 'failed': [], 'item_created': False, 'last_run': None}

def save_progress(p):
    p['last_run'] = datetime.now().isoformat()
    with open(LOG_FILE, 'w') as f:
        json.dump(p, f, indent=2)

def create_item() -> bool:
    print(f"\n{Colors.CYAN}📝 Creating Archive.org item: {ITEM_IDENTIFIER}{Colors.NC}")
    
    try:
        item = ia.get_item(ITEM_IDENTIFIER)
        if item.exists:
            print(f"{Colors.GREEN}✅ Item already exists{Colors.NC}")
            return True
        
        metadata = {
            'collection': ITEM_COLLECTION,
            'mediatype': 'texts',
            'title': ITEM_TITLE,
            'description': ITEM_DESCRIPTION,
            'creator': ITEM_CREATOR,
            'language': ITEM_LANGUAGE,
            'subject': ITEM_SUBJECT,
            'date': ITEM_YEAR,
            'licenseurl': ITEM_LICENSE
        }
        
        manifest = {
            "identifier": ITEM_IDENTIFIER,
            "title": ITEM_TITLE,
            "description": ITEM_DESCRIPTION,
            "creator": ITEM_CREATOR,
            "collection": ITEM_COLLECTION,
            "mediatype": "texts",
            "language": ITEM_LANGUAGE,
            "subject": ITEM_SUBJECT,
            "date": ITEM_YEAR,
            "licenseurl": ITEM_LICENSE,
            "created": datetime.now().isoformat()
        }
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', prefix='ia_', delete=False) as f:
            json.dump(manifest, f, indent=2)
            manifest_path = f.name
        
        try:
            ia.upload(
                ITEM_IDENTIFIER,
                files={"manifest.json": manifest_path},
                metadata=metadata,
                queue_derive=False,
                retries=UPLOAD_RETRY_COUNT
            )
            print(f"{Colors.GREEN}✅ Item created successfully!{Colors.NC}")
            print(f"   URL: https://archive.org/details/{ITEM_IDENTIFIER}")
            return True
        finally:
            if os.path.exists(manifest_path):
                os.unlink(manifest_path)
        
    except Exception as e:
        print(f"{Colors.RED}❌ Error creating item: {e}{Colors.NC}")
        return False

def upload_to_archive(file_path: str, retry_count: int = 3) -> Tuple[bool, str]:
    import sys
    filename = os.path.basename(file_path)
    file_size = os.path.getsize(file_path) / (1024**3)
    file_ext = filename.split('.')[-1].upper()
    
    print(f"  📤 Uploading: {filename} ({file_size:.2f} GB) [{file_ext}]")
    sys.stdout.flush()
    
    for attempt in range(retry_count):
        try:
            session = ia.get_session(
                config={
                    's3': {
                        'access': os.getenv("IA_ACCESS_KEY"),
                        'secret': os.getenv("IA_SECRET_KEY")
                    }
                }
            )
            item = session.get_item(ITEM_IDENTIFIER)
            item.upload(
                files={filename: file_path},
                metadata={'collection': ITEM_COLLECTION, 'mediatype': 'texts'},
                queue_derive=False,
                retries=1,
                verbose=True
            )
            print(f"\n  ✅ Upload complete! ({file_size:.2f} GB)")
            return True, f"https://archive.org/download/{ITEM_IDENTIFIER}/{filename}"
        except Exception as e:
            print(f"  ❌ Upload failed: {str(e)}")
            if attempt < retry_count - 1:
                wait = 5 * (attempt + 1)
                print(f"  ⏳ Retry {attempt+1}/{retry_count} in {wait}s...")
                time.sleep(wait)
                continue
            return False, str(e)
    return False, "Max retries exceeded"

def get_files() -> List[str]:
    """Get all PDF and CBZ files in current directory"""
    files = []
    for ext in ['.pdf', '.cbz']:
        files.extend([f for f in os.listdir('.') if f.lower().endswith(ext) and os.path.isfile(f)])
    return sorted(files)

def main():
    print(f"{Colors.MAGENTA}")
    print("╔═══════════════════════════════════════════════════════════════╗")
    print("║     Archive.org Uploader - Strategy Guides                   ║")
    print("║     Uploads PDF & CBZ files to Archive.org                  ║")
    print("║                                                               ║")
    print("║   ✅ Uses official internetarchive library                    ║")
    print("║   ✅ Uploads ONE BY ONE                                       ║")
    print("║   ✅ Resume support if interrupted                            ║")
    print("║   ✅ All config from .env                                     ║")
    print("║   ✅ Supports PDF and CBZ files                              ║")
    print("╚═══════════════════════════════════════════════════════════════╝")
    print(f"{Colors.NC}")
    
    ia_access_key = os.getenv("IA_ACCESS_KEY")
    ia_secret_key = os.getenv("IA_SECRET_KEY")
    if not ia_access_key or not ia_secret_key:
        print(f"{Colors.RED}❌ Missing credentials in .env{Colors.NC}")
        sys.exit(1)
    
    files = get_files()
    if not files:
        print(f"{Colors.RED}❌ No PDF or CBZ files found in current directory!{Colors.NC}")
        print(f"{Colors.YELLOW}💡 Current directory: {os.getcwd()}{Colors.NC}")
        sys.exit(1)
    
    # Count by type
    pdf_count = len([f for f in files if f.lower().endswith('.pdf')])
    cbz_count = len([f for f in files if f.lower().endswith('.cbz')])
    
    print(f"{Colors.GREEN}📊 Found {len(files)} files in current directory{Colors.NC}")
    print(f"   📄 PDF: {pdf_count}")
    print(f"   📦 CBZ: {cbz_count}")
    
    total_size = sum(os.path.getsize(f) for f in files)
    print(f"   Total size: {total_size / (1024**3):.2f} GB")
    
    progress = load_progress()
    
    if not progress.get('item_created', False):
        print(f"\n{Colors.YELLOW}⚠️ Archive.org item not created yet!{Colors.NC}")
        confirm = input(f"{Colors.CYAN}Create item '{ITEM_IDENTIFIER}'? (y/N): {Colors.NC}")
        if confirm.lower() != 'y':
            print("Cancelled.")
            sys.exit(0)
        if create_item():
            progress['item_created'] = True
            save_progress(progress)
        else:
            print(f"{Colors.RED}❌ Failed to create item. Exiting.{Colors.NC}")
            sys.exit(1)
    else:
        print(f"{Colors.GREEN}✅ Item exists: https://archive.org/details/{ITEM_IDENTIFIER}{Colors.NC}")
    
    uploaded_set = set(progress['uploaded'])
    pending = [f for f in files if f not in uploaded_set]
    if not pending:
        print(f"{Colors.GREEN}✅ All uploaded!{Colors.NC}")
        sys.exit(0)
    
    print(f"\n{Colors.GREEN}📊 Already uploaded: {len(uploaded_set)}{Colors.NC}")
    print(f"{Colors.YELLOW}📊 Pending uploads: {len(pending)}{Colors.NC}")
    confirm = input(f"\n{Colors.CYAN}Continue? (y/N): {Colors.NC}")
    if confirm.lower() != 'y':
        sys.exit(0)
    
    print(f"\n{Colors.CYAN}📤 Uploading {len(pending)} files...{Colors.NC}")
    print(f"   {Colors.YELLOW}⚠️ Press Ctrl+C to pause{Colors.NC}\n")
    
    try:
        for idx, file in enumerate(pending, 1):
            file_ext = file.split('.')[-1].upper()
            print(f"\n{Colors.BOLD}[{idx}/{len(pending)}] {Colors.NC}{file} [{file_ext}]")
            success, result = upload_to_archive(file, UPLOAD_RETRY_COUNT)
            if success:
                progress['uploaded'].append(file)
                print(f"  {Colors.GREEN}✅ Upload complete!{Colors.NC}")
                print(f"  🔗 {result}")
            else:
                progress['failed'].append(file)
                print(f"  {Colors.RED}❌ Upload failed: {result}{Colors.NC}")
            save_progress(progress)
            time.sleep(2)
    except KeyboardInterrupt:
        print(f"\n\n{Colors.YELLOW}⚠️ Paused!{Colors.NC}")
        save_progress(progress)
        sys.exit(0)
    
    print(f"\n{Colors.GREEN}{'='*60}{Colors.NC}")
    print(f"{Colors.GREEN}✅ UPLOAD COMPLETE!{Colors.NC}")
    print(f"📁 Total uploaded: {len(progress['uploaded'])}/{len(files)}")
    print(f"🔗 Archive URL: https://archive.org/details/{ITEM_IDENTIFIER}")
    print(f"{Colors.GREEN}🏛️ Strategy Guide Archive is preserved forever!{Colors.NC}")

if __name__ == "__main__":
    main()
PYEOF

chmod +x archive_uploader.py
echo -e "${GREEN}✅ Uploader script created{NC}"

# Run the uploader
echo -e "\n${CYAN}🚀 Starting uploader...${NC}"
echo -e "${YELLOW}   Press Ctrl+C to pause and resume later${NC}\n"

python3 -u archive_uploader.py

echo -e "\n${GREEN}✅ Done!${NC}"