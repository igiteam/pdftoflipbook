#!/usr/bin/env python3
import os
import time
import shutil
import json
import threading
import re
from datetime import datetime
from pathlib import Path
import queue
import signal
import sys
import subprocess
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

class DownloadHandler(FileSystemEventHandler):
    """Handler for new files in downloads folder"""
    def __init__(self, callback):
        self.callback = callback
        self.processed_files = set()
        self.processing_lock = threading.Lock()
        
    def on_created(self, event):
        if not event.is_directory:
            time.sleep(0.1)
            self.callback(event.src_path)

class MagazineDownloader:
    def __init__(self, magazines_file, downloads_folder, max_concurrent=2):
        with open(magazines_file, 'r') as f:
            self.magazines = json.load(f)
        
        self.downloads_folder = Path(downloads_folder).expanduser()
        self.max_concurrent = max_concurrent
        self.active_processes = []
        self.task_queue = queue.Queue()
        self.results = []
        self.processing_lock = threading.Lock()
        self.completion_events = {}
        self.completion_lock = threading.Lock()
        
        # Setup downloads folder
        self.downloads_folder.mkdir(exist_ok=True)
        
        # Firefox Developer Edition path
        self.firefox_binary = "/Applications/Firefox Developer Edition.app/Contents/MacOS/firefox"
        
        if not os.path.exists(self.firefox_binary):
            print(f"❌ Firefox Developer Edition not found")
            sys.exit(1)
        
        profiles_dir = os.path.expanduser("~/Library/Application Support/Firefox/Profiles/")
        self.profile_path = os.path.join(profiles_dir, "dxe07wpf.dev-edition-default")
        
        if not os.path.exists(self.profile_path):
            print(f"❌ Profile not found: {self.profile_path}")
            sys.exit(1)
        
        print(f"✓ Using Firefox Developer Edition")
        print(f"✓ Using profile: dxe07wpf.dev-edition-default")
        
        # Load progress
        self.progress_file = Path('download_progress.json')
        self.processed_magazines = self.load_progress()
        
        # Setup file monitor
        self.observer = Observer()
        self.handler = DownloadHandler(self.on_new_file)
        self.observer.schedule(self.handler, str(self.downloads_folder), recursive=False)
        self.observer.start()
        
        # Setup signal handler
        signal.signal(signal.SIGINT, self.graceful_shutdown)
        
        # Process existing files
        self.process_existing_files()
    
    def load_progress(self):
        if self.progress_file.exists():
            with open(self.progress_file, 'r') as f:
                return set(json.load(f))
        return set()
    
    def save_progress(self):
        with open(self.progress_file, 'w') as f:
            json.dump(list(self.processed_magazines), f)
    
    def extract_magazine_name(self, filename):
        """Extract magazine name from filename"""
        match = re.search(r'(Official_Xbox_Magazine[^_]*Issue_\d+)', filename)
        if match:
            return match.group(1) 
        
        if '_page_' in filename:
            return filename.split('_page_')[0] 
        elif '_flipbook' in filename:
            return filename.split('_flipbook')[0]
        
        return None
    
    def on_new_file(self, file_path):
        """Called when a new file is detected - move it and signal completion"""
        file_path = Path(file_path)
        extension = file_path.suffix.lower()
        
        if extension not in ['.png', '.html', '.htm']:
            return
        
        # Skip zero-byte files
        try:
            if file_path.stat().st_size == 0:
                return
        except:
            return
        
        with self.processing_lock:
            file_str = str(file_path)
            if file_str in self.handler.processed_files:
                return
            
            self.handler.processed_files.add(file_str)
            
            magazine_name = self.extract_magazine_name(file_path.name)
            
            if magazine_name:
                # Move file immediately
                self.move_file(file_path, magazine_name)
                
                # If HTML file, signal completion
                if extension in ['.html', '.htm']:
                    with self.completion_lock:
                        if magazine_name in self.completion_events:
                            print(f"\n  🎯 HTML DETECTED: {magazine_name}")
                            self.completion_events[magazine_name].set()
    
    def move_file(self, file_path, magazine_name):
        """Move file to magazine folder"""
        try:
            magazine_folder = self.downloads_folder / magazine_name
            magazine_folder.mkdir(exist_ok=True)
            
            destination = magazine_folder / file_path.name
            
            # Handle duplicates
            counter = 1
            while destination.exists():
                stem = file_path.stem
                destination = magazine_folder / f"{stem}_{counter}{file_path.suffix}"
                counter += 1
            
            shutil.move(str(file_path), str(destination))
            print(f"  📄 Moved: {file_path.name[:50]}")
            
        except Exception as e:
            print(f"  ✗ Move failed: {e}")
    
    def process_existing_files(self):
        """Quick scan for existing files"""
        print("\n📁 Checking existing files...")
        for ext in ['*.png', '*.html', '*.htm']:
            for file_path in self.downloads_folder.glob(ext):
                if file_path.stat().st_size > 0:
                    magazine_name = self.extract_magazine_name(file_path.name)
                    if magazine_name:
                        self.move_file(file_path, magazine_name)
    
    def open_firefox_window(self, url, worker_id):
        """Open a new Firefox Developer Edition window"""
        cmd = [
            self.firefox_binary,
            "--no-remote",
            "--profile",
            self.profile_path,
            "--new-window",
            url
        ]
        
        print(f"[Worker {worker_id}] Opening Firefox...")
        process = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return process
    
    def kill_firefox_window(self, process):
        """Force kill Firefox window"""
        try:
            if process and process.poll() is None:
                process.terminate()
                time.sleep(0.3)
                if process.poll() is None:
                    process.kill()
                print(f"  🔪 Firefox closed")
        except:
            pass
    
    def process_magazine(self, magazine_name, magazine_url, worker_id):
        """Process a single magazine - CLOSE WINDOW IMMEDIATELY when done"""
        print(f"\n[Worker {worker_id}] 📘 {magazine_name[:50]}")
        
        firefox_process = None
        completion_event = threading.Event()
        
        # Register completion event for this magazine
        with self.completion_lock:
            self.completion_events[magazine_name] = completion_event
        
        try:
            # Check if already downloaded
            magazine_folder = self.downloads_folder / magazine_name
            if magazine_folder.exists():
                html_files = list(magazine_folder.glob("*.html")) + list(magazine_folder.glob("*.htm"))
                if html_files:
                    print(f"[Worker {worker_id}] ⏭️  Already done")
                    return True
            
            # Open Firefox window
            firefox_process = self.open_firefox_window(magazine_url, worker_id)
            self.active_processes.append(firefox_process)
            
            # Wait for HTML file (max 20 minutes)
            start_time = time.time()
            timeout = 1200  # 20 minutes
            
            while time.time() - start_time < timeout:
                if completion_event.wait(timeout=1):
                    # HTML detected! Close Firefox immediately
                    elapsed = int(time.time() - start_time)
                    print(f"  ✅ Done in {elapsed}s - closing Firefox")
                    self.kill_firefox_window(firefox_process)
                    
                    self.processed_magazines.add(magazine_name)
                    self.save_progress()
                    return True
                
                elapsed = int(time.time() - start_time)
                if elapsed % 60 == 0 and elapsed > 0:
                    print(f"  ⏳ Waiting... {magazine_name[:40]} ({elapsed//60}m)")
            
            # Timeout
            print(f"  ❌ Timeout after 20 minutes")
            self.kill_firefox_window(firefox_process)
            return False
            
        except Exception as e:
            print(f"[Worker {worker_id}] ✗ Error: {e}")
            self.kill_firefox_window(firefox_process)
            return False
        finally:
            with self.completion_lock:
                self.completion_events.pop(magazine_name, None)
            if firefox_process and firefox_process in self.active_processes:
                self.active_processes.remove(firefox_process)
    
    def worker(self, worker_id):
        """Worker thread"""
        while True:
            try:
                magazine_name, magazine_url = self.task_queue.get(timeout=10)
                
                if magazine_name is None:
                    break
                
                success = self.process_magazine(magazine_name, magazine_url, worker_id)
                
                self.results.append({
                    'name': magazine_name,
                    'url': magazine_url,
                    'success': success,
                    'timestamp': datetime.now().isoformat()
                })
                
                self.task_queue.task_done()
                
                # Short pause between magazines
                time.sleep(2)
                
            except queue.Empty:
                break
    
    def start(self):
        """Start the download process"""
        print("\n" + "="*50)
        print(f"🎯 Downloader: {len(self.magazines)} magazines total")
        print(f"✓ Already processed: {len(self.processed_magazines)}")
        print(f"🔄 New magazines: {len(self.magazines) - len(self.processed_magazines)}")
        print(f"⚡ Max concurrent: {self.max_concurrent}")
        print(f"📁 Folder: {self.downloads_folder}")
        print("="*50 + "\n")
        
        # Add unprocessed magazines to queue
        for name, url in self.magazines.items():
            if name not in self.processed_magazines:
                self.task_queue.put((name, url))
        
        total_tasks = self.task_queue.qsize()
        if total_tasks == 0:
            print("✓ All magazines already processed!")
            return
        
        threads = []
        actual_workers = min(self.max_concurrent, total_tasks)
        print(f"Starting {actual_workers} workers...\n")
        
        for i in range(actual_workers):
            thread = threading.Thread(target=self.worker, args=(i+1,))
            thread.daemon = True
            thread.start()
            threads.append(thread)
        
        self.task_queue.join()
        
        for _ in threads:
            self.task_queue.put((None, None))
        
        for thread in threads:
            thread.join()
        
        self.print_summary()
    
    def print_summary(self):
        print("\n" + "="*50)
        successful = [r for r in self.results if r['success']]
        failed = [r for r in self.results if not r['success']]
        print(f"✅ Successful: {len(successful)} | ❌ Failed: {len(failed)}")
        
        if failed:
            print("\n❌ Failed magazines:")
            for f in failed[:10]:
                print(f"  - {f['name'][:60]}")
        
        print(f"\n📁 Downloads saved to: {self.downloads_folder}")
        print("="*50)
    
    def graceful_shutdown(self, signum, frame):
        print("\n\n⚠️ Shutting down...")
        self.observer.stop()
        for process in self.active_processes:
            if process and process.poll() is None:
                self.kill_firefox_window(process)
        sys.exit(0)


def main():
    magazines_file = "magazines.json"
    downloads_folder = "~/Downloads"
    
    if not os.path.exists(magazines_file):
        print(f"❌ Error: {magazines_file} not found!")
        return
    
    downloader = MagazineDownloader(magazines_file, downloads_folder, max_concurrent=3)
    downloader.start()


if __name__ == "__main__":
    main()