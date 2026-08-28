#!/usr/bin/env python3
"""
PDF to FlipBook Batch Upload Client
- Reads config from .env file
- Scans for PDFs in current directory
- Moves processed files to /uploaded folder
- Creates upload_logs.txt with all details
- Tracks conversion progress
"""

import os
import sys
import time
import json
import shutil
import logging
import threading  # ← ADD THIS
import requests
from pathlib import Path
from typing import Dict, List, Optional
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from dotenv import load_dotenv

# Load .env file
load_dotenv()

# Configuration from .env
API_TOKEN = os.getenv('TOKEN_API', '')
DOMAIN = os.getenv('DOMAIN', 'https://flipbook.gitgpt.chat').rstrip('/')

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('flipbook_upload.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class FlipBookClient:
    """Client for PDF to FlipBook API"""
    
    def __init__(self):
        self.base_url = DOMAIN
        self.token = API_TOKEN if API_TOKEN else None
        self.session = requests.Session()
        
        # Set headers if token exists
        if self.token:
            self.session.headers.update({'X-API-Token': self.token})
            logger.info(f"Using API token: {self.token[:10]}...")
        else:
            logger.info("No API token (public access)")
        
        # Track jobs
        self.jobs = {}
        self.lock = threading.Lock()
        
        # Create uploaded folder if not exists
        self.uploaded_folder = Path.cwd() / 'uploaded'
        self.uploaded_folder.mkdir(exist_ok=True)
        logger.info(f"Uploaded files will be moved to: {self.uploaded_folder}")
        
        # Log file
        self.log_file = Path.cwd() / 'upload_logs.txt'
        
    def log_result(self, message: str, also_print: bool = True):
        """Write to both log file and console"""
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        log_entry = f"[{timestamp}] {message}"
        
        with open(self.log_file, 'a', encoding='utf-8') as f:
            f.write(log_entry + '\n')
        
        if also_print:
            print(log_entry)
    
    def find_pdfs(self, folder_path: str = None) -> List[Path]:
        """Find all PDF files in the specified folder (default: current directory)"""
        if folder_path is None:
            search_path = Path.cwd()
        else:
            search_path = Path(folder_path)
        
        # Find PDFs (case insensitive)
        pdf_files = list(search_path.glob('*.pdf')) + list(search_path.glob('*.PDF'))
        
        # Filter out already uploaded files (if they have corresponding record)
        uploaded_pdfs = set()
        if self.log_file.exists():
            with open(self.log_file, 'r', encoding='utf-8') as f:
                for line in f:
                    if '[UPLOADED]' in line or '[COMPLETED]' in line:
                        # Extract filename from log
                        for part in line.split():
                            if '.pdf' in part.lower():
                                uploaded_pdfs.add(part.strip())
        
        # Only include PDFs not already processed
        new_pdfs = [pdf for pdf in pdf_files if pdf.name not in uploaded_pdfs]
        
        return new_pdfs
    
    def upload_pdf(self, file_path: Path) -> Optional[str]:
        """Upload a single PDF and return job_id"""
        try:
            file_size = os.path.getsize(file_path) / (1024 * 1024)  # MB
            self.log_result(f"📤 Uploading: {file_path.name} ({file_size:.1f} MB)")
            
            with open(file_path, 'rb') as f:
                files = {'pdf': (file_path.name, f, 'application/pdf')}
                
                response = self.session.post(
                    f"{self.base_url}/api/upload",
                    files=files,
                    timeout=300
                )
            
            if response.status_code == 200:
                result = response.json()
                job_id = result.get('job_id')
                
                if job_id:
                    with self.lock:
                        self.jobs[job_id] = {
                            'file_path': str(file_path),
                            'file_name': file_path.name,
                            'status': 'uploaded',
                            'progress': 0,
                            'start_time': time.time()
                        }
                    
                    self.log_result(f"✅ UPLOADED: {file_path.name} -> Job ID: {job_id}")
                    
                    # Move file to uploaded folder
                    destination = self.uploaded_folder / file_path.name
                    shutil.move(str(file_path), str(destination))
                    self.log_result(f"📁 Moved: {file_path.name} -> uploaded/", also_print=False)
                    
                    return job_id
                else:
                    self.log_result(f"❌ No job_id for {file_path.name}")
                    return None
            else:
                self.log_result(f"❌ Upload failed: {file_path.name} (HTTP {response.status_code})")
                return None
                
        except Exception as e:
            self.log_result(f"❌ Error uploading {file_path.name}: {str(e)}")
            return None
    
    def check_progress(self, job_id: str) -> Dict:
        """Check progress of a specific job"""
        try:
            response = self.session.get(
                f"{self.base_url}/api/progress/{job_id}",
                timeout=30
            )
            
            if response.status_code == 200:
                data = response.json()
                
                with self.lock:
                    if job_id in self.jobs:
                        self.jobs[job_id]['progress'] = data.get('percent', 0)
                        self.jobs[job_id]['stage'] = data.get('stage', 'unknown')
                        self.jobs[job_id]['details'] = data
                
                return data
            else:
                return {'stage': 'unknown', 'percent': 0}
                
        except Exception as e:
            logger.debug(f"Error checking progress for {job_id}: {str(e)}")
            return {'stage': 'unknown', 'percent': 0}
    
    def wait_for_completion(self, job_id: str, file_name: str, timeout: int = 1200) -> Optional[Dict]:
        """Wait for job to complete and return flipbook info"""
        start_time = time.time()
        last_percent = 0
        last_stage = ""
        
        while time.time() - start_time < timeout:
            progress = self.check_progress(job_id)
            stage = progress.get('stage', 'unknown')
            percent = progress.get('percent', 0)
            
            # Log progress changes
            if percent != last_percent or stage != last_stage:
                if stage == 'converting':
                    current_page = progress.get('currentPage', 0)
                    total_pages = progress.get('totalPages', 0)
                    self.log_result(f"  ⏳ {file_name}: {percent}% - Page {current_page}/{total_pages}", also_print=False)
                elif stage == 'complete':
                    self.log_result(f"  ✅ {file_name}: COMPLETE!")
                elif stage == 'error':
                    self.log_result(f"  ❌ {file_name}: Failed - {progress.get('error', 'Unknown error')}")
                elif percent > 0:
                    self.log_result(f"  ⏳ {file_name}: {percent}% - {stage}", also_print=False)
                
                last_percent = percent
                last_stage = stage
            
            if stage == 'complete':
                # Get the flipbook from history
                response = self.session.get(f"{self.base_url}/api/history", timeout=30)
                if response.status_code == 200:
                    history = response.json().get('history', [])
                    # Find matching flipbook by title
                    for item in history:
                        if file_name.replace('.pdf', '') in item.get('original_name', ''):
                            return item
                    
                    # If not found, return the most recent
                    if history:
                        return history[0]
                
                return {'status': 'complete', 'job_id': job_id}
            
            elif stage == 'error':
                return None
            
            time.sleep(2)
        
        self.log_result(f"  ⏰ {file_name}: Timeout after {timeout} seconds")
        return None
    
    def process_all_pdfs(self, folder_path: str = None, wait_for_completion: bool = True, max_workers: int = 3):
        """Main method to process all PDFs"""
        
        # Find all PDFs
        pdf_files = self.find_pdfs(folder_path)
        
        if not pdf_files:
            self.log_result("📭 No new PDF files found to process")
            return []
        
        self.log_result(f"\n{'='*80}")
        self.log_result(f"📚 FOUND {len(pdf_files)} PDF(s) to process")
        self.log_result(f"{'='*80}\n")
        
        results = []
        uploaded_jobs = []
        
        # Upload files (one at a time to avoid overwhelming)
        for pdf_file in pdf_files:
            self.log_result(f"\n--- Processing: {pdf_file.name} ---")
            job_id = self.upload_pdf(pdf_file)
            
            if job_id:
                uploaded_jobs.append({
                    'job_id': job_id,
                    'file_path': str(pdf_file),
                    'file_name': pdf_file.name
                })
                results.append({
                    'file': pdf_file.name,
                    'status': 'uploaded',
                    'job_id': job_id
                })
            else:
                results.append({
                    'file': pdf_file.name,
                    'status': 'failed',
                    'error': 'Upload failed'
                })
        
        self.log_result(f"\n{'='*80}")
        self.log_result(f"📊 UPLOAD SUMMARY: {len(uploaded_jobs)}/{len(pdf_files)} files uploaded")
        self.log_result(f"{'='*80}")
        
        # Wait for conversions if requested
        if wait_for_completion and uploaded_jobs:
            self.log_result(f"\n⏳ WAITING FOR CONVERSIONS TO COMPLETE...\n")
            
            for job_info in uploaded_jobs:
                job_id = job_info['job_id']
                file_name = job_info['file_name']
                
                result = self.wait_for_completion(job_id, file_name)
                
                # Update result
                for res in results:
                    if res.get('job_id') == job_id:
                        if result:
                            res['status'] = 'completed'
                            res['flipbook_url'] = result.get('html_url')
                            res['zip_url'] = result.get('zip_url')
                            res['pages'] = result.get('page_count')
                            res['thumbnail'] = result.get('thumbnail_url')
                            
                            self.log_result(f"\n✅ COMPLETED: {file_name}")
                            self.log_result(f"   📖 Flipbook: {result.get('html_url')}")
                            self.log_result(f"   📦 ZIP: {result.get('zip_url')}")
                            self.log_result(f"   📄 Pages: {result.get('page_count')}")
                        else:
                            res['status'] = 'failed'
                            res['error'] = 'Conversion failed or timed out'
                            self.log_result(f"\n❌ FAILED: {file_name}")
                        break
        
        # Generate final report
        self.generate_report(results)
        
        return results
    
    def generate_report(self, results: List[Dict]):
        """Generate final report"""
        
        self.log_result(f"\n{'='*80}")
        self.log_result(f"📊 FINAL REPORT")
        self.log_result(f"{'='*80}")
        self.log_result(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        self.log_result(f"")
        
        # Statistics
        total = len(results)
        completed = len([r for r in results if r['status'] == 'completed'])
        uploaded = len([r for r in results if r['status'] == 'uploaded'])
        failed = len([r for r in results if r['status'] == 'failed'])
        
        self.log_result(f"📈 STATISTICS:")
        self.log_result(f"   Total files: {total}")
        self.log_result(f"   ✅ Completed: {completed}")
        self.log_result(f"   📤 Uploaded (processing): {uploaded}")
        self.log_result(f"   ❌ Failed: {failed}")
        self.log_result(f"")
        
        # Detailed results
        if completed > 0:
            self.log_result(f"✅ COMPLETED CONVERSIONS:")
            for result in results:
                if result['status'] == 'completed':
                    self.log_result(f"   • {result['file']}")
                    self.log_result(f"     📖 {result.get('flipbook_url')}")
                    self.log_result(f"     📦 {result.get('zip_url')}")
                    self.log_result(f"     📄 {result.get('pages')} pages")
        
        if uploaded > 0:
            self.log_result(f"\n📤 UPLOADED (processing in background):")
            for result in results:
                if result['status'] == 'uploaded':
                    self.log_result(f"   • {result['file']} (Job: {result.get('job_id')})")
        
        if failed > 0:
            self.log_result(f"\n❌ FAILED:")
            for result in results:
                if result['status'] == 'failed':
                    self.log_result(f"   • {result['file']}: {result.get('error', 'Unknown error')}")
        
        self.log_result(f"\n{'='*80}")
        self.log_result(f"📁 Uploaded files moved to: {self.uploaded_folder}/")
        self.log_result(f"📝 Full log saved to: upload_logs.txt")
        self.log_result(f"{'='*80}\n")


def main():
    import argparse
    
    parser = argparse.ArgumentParser(
        description='Batch upload PDFs to FlipBook API',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Process all PDFs in current directory
  python3 flipbook_client.py
  
  # Process PDFs from specific folder
  python3 flipbook_client.py --folder ./my_pdfs
  
  # Upload without waiting for conversion
  python3 flipbook_client.py --no-wait
  
  # Use custom concurrency
  python3 flipbook_client.py --workers 2
        """
    )
    
    parser.add_argument('--folder', '-f', type=str, default=None,
                        help='Folder containing PDFs (default: current directory)')
    parser.add_argument('--no-wait', action='store_true',
                        help='Don\'t wait for conversions to complete')
    parser.add_argument('--workers', '-w', type=int, default=1,
                        help='Number of concurrent uploads (default: 1, max: 3)')
    parser.add_argument('--verbose', '-v', action='store_true',
                        help='Enable verbose logging')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    # Display config
    print(f"\n{'='*80}")
    print(f"📖 PDF TO FLIPBOOK BATCH UPLOADER")
    print(f"{'='*80}")
    print(f"🌐 Domain: {DOMAIN}")
    print(f"🔑 Token: {'Set' if API_TOKEN else 'Not set (public access)'}")
    print(f"📁 Working dir: {Path.cwd()}")
    print(f"📂 Upload folder: {Path.cwd() / 'uploaded'}")
    print(f"{'='*80}\n")
    
    # Create client and process
    client = FlipBookClient()
    
    try:
        results = client.process_all_pdfs(
            folder_path=args.folder,
            wait_for_completion=not args.no_wait,
            max_workers=min(args.workers, 3)
        )
        
        # Exit with appropriate code
        failed = len([r for r in results if r['status'] == 'failed'])
        if failed > 0:
            sys.exit(1)
        else:
            sys.exit(0)
            
    except KeyboardInterrupt:
        print("\n\n⚠️ Interrupted by user")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Fatal error: {str(e)}")
        sys.exit(1)


if __name__ == '__main__':
    main()