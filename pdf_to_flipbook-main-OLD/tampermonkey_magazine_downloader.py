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
            time.sleep(0.2)
            self.callback(event.src_path)
    
    def on_modified(self, event):
        if not event.is_directory:
            if event.src_path.endswith(('.html', '.htm')):
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
        self.magazine_completed = {}  # Track completion status
        
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
            print(f"❌ Profile not found")
            sys.exit(1)
        
        print(f"✓ Using Firefox Developer Edition")
        print(f"✓ Using profile: {os.path.basename(self.profile_path)}")
        
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
        match = re.search(r'(Official_Xbox_Magazine[^_]*Issue_\d+)', filename)
        if match:
            return match.group(1)
        if '_page_' in filename:
            return filename.split('_page_')[0]
        elif '_flipbook' in filename:
            return filename.split('_flipbook')[0]
        return None
    
    def on_new_file(self, file_path):
        file_path = Path(file_path)
        extension = file_path.suffix.lower()
        
        if extension not in ['.png', '.html', '.htm']:
            return
        
        try:
            if file_path.stat().st_size < 100:  # Skip empty/incomplete files
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
                destination = self.move_file(file_path, magazine_name)
                
                if extension in ['.html', '.htm']:
                    print(f"\n  🎯🎯🎯 HTML FILE COMPLETE: {magazine_name} 🎯🎯🎯")
                    with self.completion_lock:
                        # Mark as completed
                        self.magazine_completed[magazine_name] = True
                        # Signal the event if it exists
                        if magazine_name in self.completion_events:
                            self.completion_events[magazine_name].set()
                            print(f"  ✅ SIGNAL SENT to worker for {magazine_name}")
    
    def move_file(self, file_path, magazine_name):
        try:
            magazine_folder = self.downloads_folder / magazine_name
            magazine_folder.mkdir(exist_ok=True)
            destination = magazine_folder / file_path.name
            
            counter = 1
            while destination.exists():
                stem = file_path.stem
                destination = magazine_folder / f"{stem}_{counter}{file_path.suffix}"
                counter += 1
            
            shutil.move(str(file_path), str(destination))
            
            # If it's an HTML file, print special message
            if file_path.suffix.lower() in ['.html', '.htm']:
                print(f"  📄📚 HTML FILE MOVED: {file_path.name}")
            else:
                print(f"  📄 Moved: {file_path.name}")
            return destination
        except Exception as e:
            print(f"  ✗ Move failed: {e}")
            return None
    
    def process_existing_files(self):
        print("\n📁 Checking existing files...")
        for ext in ['*.png', '*.html', '*.htm']:
            for file_path in self.downloads_folder.glob(ext):
                if file_path.stat().st_size > 0:
                    magazine_name = self.extract_magazine_name(file_path.name)
                    if magazine_name:
                        self.move_file(file_path, magazine_name)
    
    def open_firefox_window(self, url, worker_id):
        cmd = [self.firefox_binary, "--no-remote", "--profile", self.profile_path, "--new-window", url]
        print(f"[Worker {worker_id}] 🌐 Opening Firefox...")
        return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    def kill_firefox_window(self, process, worker_id):
        try:
            if process and process.poll() is None:
                process.terminate()
                time.sleep(0.5)
                if process.poll() is None:
                    process.kill()
                print(f"[Worker {worker_id}] 🔪 Firefox closed")
                return True
        except:
            pass
        return False
    
    def check_for_html_file(self, magazine_name, magazine_folder):
        """Check if HTML file already exists for this magazine"""
        if magazine_folder.exists():
            html_files = list(magazine_folder.glob("*.html")) + list(magazine_folder.glob("*.htm"))
            if html_files:
                return True
        return False
    
    def process_magazine(self, magazine_name, magazine_url, worker_id):
        print(f"\n[Worker {worker_id}] 📘 Starting: {magazine_name}")
        
        magazine_folder = self.downloads_folder / magazine_name
        
        # Check if already downloaded
        if self.check_for_html_file(magazine_name, magazine_folder):
            print(f"[Worker {worker_id}] ⏭️ Already downloaded, skipping")
            with self.processing_lock:
                self.processed_magazines.add(magazine_name)
            self.save_progress()
            return True
        
        firefox_process = None
        completion_event = threading.Event()
        
        # Register completion event
        with self.completion_lock:
            self.completion_events[magazine_name] = completion_event
            self.magazine_completed[magazine_name] = False
        
        try:
            # Open Firefox window
            firefox_process = self.open_firefox_window(magazine_url, worker_id)
            with self.processing_lock:
                self.active_processes.append(firefox_process)
            
            start_time = time.time()
            timeout = 1200  # 20 minutes
            last_png_count = 0
            no_change_count = 0
            
            print(f"[Worker {worker_id}] 💤 Monitoring for completion...")
            
            while time.time() - start_time < timeout:
                # Check 1: Event signal from file monitor
                if completion_event.is_set():
                    elapsed = int(time.time() - start_time)
                    print(f"\n[Worker {worker_id}] ✅ HTML detected via file monitor! Completed in {elapsed}s")
                    self.kill_firefox_window(firefox_process, worker_id)
                    
                    with self.processing_lock:
                        self.processed_magazines.add(magazine_name)
                    self.save_progress()
                    return True
                
                # Check 2: Direct filesystem check for HTML file
                if self.check_for_html_file(magazine_name, magazine_folder):
                    elapsed = int(time.time() - start_time)
                    print(f"\n[Worker {worker_id}] ✅ HTML file found directly! Completed in {elapsed}s")
                    self.kill_firefox_window(firefox_process, worker_id)
                    
                    with self.processing_lock:
                        self.processed_magazines.add(magazine_name)
                    self.save_progress()
                    return True
                
                # Check 3: Monitor PNG count - if no new PNGs for 2 minutes, might be done
                if magazine_folder.exists():
                    current_png_count = len(list(magazine_folder.glob("*.png")))
                    if current_png_count == last_png_count:
                        no_change_count += 1
                    else:
                        no_change_count = 0
                        last_png_count = current_png_count
                    
                    # If no new PNGs for 2 minutes AND we have at least 10 PNGs, consider complete
                    if no_change_count > 24:  # 24 * 5 seconds = 2 minutes
                        if current_png_count > 10:
                            elapsed = int(time.time() - start_time)
                            print(f"\n[Worker {worker_id}] ✅ No new PNGs for 2 minutes ({current_png_count} PNGs) - marking complete")
                            self.kill_firefox_window(firefox_process, worker_id)
                            
                            with self.processing_lock:
                                self.processed_magazines.add(magazine_name)
                            self.save_progress()
                            return True
                else:
                    no_change_count = 0
                
                # Progress update every 30 seconds
                elapsed = int(time.time() - start_time)
                if elapsed > 0 and elapsed % 30 == 0 and elapsed > 0:
                    png_count = len(list(magazine_folder.glob("*.png"))) if magazine_folder.exists() else 0
                    print(f"[Worker {worker_id}] ⏳ Waiting... ({elapsed//60}m {elapsed%60}s) - {png_count} PNGs")
                
                time.sleep(5)  # Check every 5 seconds
            
            # Timeout
            # Check one last time for HTML file before giving up
            if self.check_for_html_file(magazine_name, magazine_folder):
                print(f"\n[Worker {worker_id}] ✅ HTML file found at timeout! Marking success")
                self.kill_firefox_window(firefox_process, worker_id)
                with self.processing_lock:
                    self.processed_magazines.add(magazine_name)
                self.save_progress()
                return True
            
            print(f"[Worker {worker_id}] ❌ Timeout after 20 minutes")
            self.kill_firefox_window(firefox_process, worker_id)
            return False
            
        except Exception as e:
            print(f"[Worker {worker_id}] ✗ Error: {e}")
            import traceback
            traceback.print_exc()
            if firefox_process:
                self.kill_firefox_window(firefox_process, worker_id)
            return False
        finally:
            with self.completion_lock:
                self.completion_events.pop(magazine_name, None)
                self.magazine_completed.pop(magazine_name, None)
            if firefox_process and firefox_process in self.active_processes:
                with self.processing_lock:
                    self.active_processes.remove(firefox_process)
    
    def worker(self, worker_id):
        while True:
            try:
                magazine_name, magazine_url = self.task_queue.get(timeout=5)
                if magazine_name is None:
                    break
                
                print(f"\n[Worker {worker_id}] 🎯 Got task: {magazine_name}")
                success = self.process_magazine(magazine_name, magazine_url, worker_id)
                
                with self.processing_lock:
                    self.results.append({
                        'name': magazine_name,
                        'url': magazine_url,
                        'success': success,
                        'timestamp': datetime.now().isoformat()
                    })
                
                self.task_queue.task_done()
                
                if self.task_queue.qsize() > 0:
                    print(f"[Worker {worker_id}] 📋 Next magazine in queue...")
                    time.sleep(1)
                
            except queue.Empty:
                break
            except Exception as e:
                print(f"[Worker {worker_id}] Worker error: {e}")
                self.task_queue.task_done()
    
    def start(self):
        print("\n" + "="*60)
        print(f"🎯 Magazine Downloader")
        print(f"📚 Total magazines: {len(self.magazines)}")
        print(f"✅ Already processed: {len(self.processed_magazines)}")
        
        unprocessed = {name: url for name, url in self.magazines.items() 
                      if name not in self.processed_magazines}
        
        print(f"🔄 New magazines: {len(unprocessed)}")
        print(f"⚡ Max concurrent: {self.max_concurrent}")
        print(f"📁 Download folder: {self.downloads_folder}")
        print("="*60 + "\n")
        
        for name, url in unprocessed.items():
            self.task_queue.put((name, url))
        
        total_tasks = self.task_queue.qsize()
        if total_tasks == 0:
            print("✓ All magazines already processed!")
            self.cleanup()
            return
        
        actual_workers = min(self.max_concurrent, total_tasks)
        print(f"Starting {actual_workers} worker threads for {total_tasks} magazines...\n")
        
        threads = []
        for i in range(actual_workers):
            thread = threading.Thread(target=self.worker, args=(i+1,))
            thread.daemon = True
            thread.start()
            threads.append(thread)
        
        self.task_queue.join()
        
        for _ in threads:
            self.task_queue.put((None, None))
        
        for thread in threads:
            thread.join(timeout=5)
        
        self.print_summary()
        self.cleanup()
    
    def print_summary(self):
        print("\n" + "="*60)
        successful = [r for r in self.results if r['success']]
        failed = [r for r in self.results if not r['success']]
        print(f"✅ Successful: {len(successful)}")
        print(f"❌ Failed: {len(failed)}")
        
        if failed:
            print("\n⚠️ NOTE: If magazines downloaded but show as failed, check your Downloads folder")
            print("   The files were likely saved correctly but detection timed out")
        
        print(f"\n📁 Downloads saved to: {self.downloads_folder}")
        print("="*60)
    
    def cleanup(self):
        if hasattr(self, 'observer'):
            self.observer.stop()
            self.observer.join()
    
    def graceful_shutdown(self, signum, frame):
        print("\n\n⚠️ Shutting down gracefully...")
        self.cleanup()
        with self.processing_lock:
            for process in self.active_processes:
                if process and process.poll() is None:
                    try:
                        process.terminate()
                    except:
                        pass
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