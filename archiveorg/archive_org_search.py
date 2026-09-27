#!/usr/bin/env python3.10
"""
Internet Archive Search - Smart Filter
Search ANYTHING and filter results based on your search term
"""

import requests
import re
from datetime import datetime
import time
import os
from pathlib import Path

def sanitize_filename(name: str) -> str:
    """Clean string for use as filename"""
    name = re.sub(r'[\\/*?:"<>|]', '', name)
    name = name.replace(' ', '_')
    if len(name) > 50:
        name = name[:50]
    return name

def search_archive(query: str, limit: int = 500) -> list:
    """Search Internet Archive and return results"""
    
    url = "https://archive.org/advancedsearch.php"
    params = {
        'q': query,
        'fl[]': ['identifier', 'title', 'creator', 'date', 'description', 'mediatype', 'downloads'],
        'rows': limit,
        'page': 1,
        'output': 'json'
    }
    
    print(f"\n🔍 Searching: {query}")
    print(f"📊 Limit: {limit} results")
    print("⏳ Please wait...\n")
    
    try:
        response = requests.get(url, params=params, timeout=60)
        data = response.json()
        
        items = []
        for doc in data.get('response', {}).get('docs', []):
            title = doc.get('title', 'Unknown')
            if isinstance(title, list):
                title = title[0] if title else 'Unknown'
            
            creator = doc.get('creator', 'Unknown')
            if isinstance(creator, list):
                creator = creator[0] if creator else 'Unknown'
            
            date = doc.get('date', 'Unknown')
            if isinstance(date, list):
                date = date[0] if date else 'Unknown'
            
            description = doc.get('description', '')
            if isinstance(description, list):
                description = description[0] if description else ''
            
            items.append({
                'identifier': doc.get('identifier', ''),
                'title': title,
                'creator': creator,
                'date': date,
                'mediatype': doc.get('mediatype', 'Unknown'),
                'downloads': doc.get('downloads', 0),
                'description': description[:300] if description else '',
                'url': f"https://archive.org/details/{doc.get('identifier', '')}",
                'download_url': f"https://archive.org/download/{doc.get('identifier', '')}"
            })
        
        return items
    except Exception as e:
        print(f"❌ Search failed: {e}")
        return []

def get_item_files(identifier: str) -> list:
    """Get list of files in an item using metadata API"""
    try:
        url = f"https://archive.org/metadata/{identifier}"
        response = requests.get(url, timeout=30)
        data = response.json()
        
        files = []
        for file_info in data.get('files', []):
            file_name = file_info.get('name', '')
            # Skip metadata XML files and thumbs
            if not file_name.endswith('_meta.xml') and not file_name.endswith('_files.xml') and 'thumb' not in file_name.lower():
                files.append({
                    'name': file_name,
                    'size': file_info.get('size', 0),
                    'format': file_info.get('format', 'Unknown'),
                    'url': f"https://archive.org/download/{identifier}/{file_name}"
                })
        
        return files
    except Exception as e:
        print(f"   ⚠️ Could not fetch files for {identifier}: {e}")
        return []

def filter_by_search_term(items: list, search_term: str) -> list:
    """Filter results to only include items matching the search term"""
    filtered = []
    search_lower = search_term.lower()
    search_words = search_lower.split()
    
    for item in items:
        title_lower = item['title'].lower()
        # Check if search term appears in title
        if search_lower in title_lower:
            filtered.append(item)
        # Or check if all words appear (for multi-word searches)
        elif all(word in title_lower for word in search_words):
            filtered.append(item)
    
    return filtered

def fetch_download_links_for_all(items: list, max_items: int = None):
    """Fetch actual file download links for each item, prioritizing PDFs"""
    
    if max_items:
        items = items[:max_items]
        print(f"\n📥 Fetching download links for first {len(items)} items...")
    else:
        print(f"\n📥 Fetching download links for all {len(items)} items...")
    
    print("   This may take a moment...\n")
    
    results = []
    pdf_count = 0
    no_files_count = 0
    
    for i, item in enumerate(items, 1):
        print(f"   [{i}/{len(items)}] {item['title'][:50]}...")
        
        files = get_item_files(item['identifier'])
        
        # Find PDFs first
        pdf_files = [f for f in files if f['name'].lower().endswith('.pdf')]
        image_files = [f for f in files if f['name'].lower().endswith(('.jpg', '.jpeg', '.png'))]
        iso_files = [f for f in files if f['name'].lower().endswith('.iso')]
        zip_files = [f for f in files if f['name'].lower().endswith('.zip')]
        
        if pdf_files:
            best_file = pdf_files[0]
            file_type = "PDF"
            pdf_count += 1
        elif image_files:
            best_file = image_files[0]
            file_type = "Image"
        elif iso_files:
            best_file = iso_files[0]
            file_type = "ISO"
        elif zip_files:
            best_file = zip_files[0]
            file_type = "ZIP"
        elif files:
            best_file = files[0]
            file_type = "Other"
        else:
            best_file = None
            file_type = "None"
            no_files_count += 1
        
        # Format file size safely
        if best_file and best_file.get('size'):
            try:
                file_size_raw = int(best_file['size'])
                file_size_str = f"{file_size_raw:,}"
            except (ValueError, TypeError):
                file_size_str = str(best_file['size'])
        else:
            file_size_str = "0"
        
        results.append({
            'title': item['title'],
            'identifier': item['identifier'],
            'date': item['date'],
            'downloads': item['downloads'],
            'archive_url': item['url'],
            'file_url': best_file['url'] if best_file else None,
            'file_name': best_file['name'] if best_file else None,
            'file_type': file_type,
            'file_size': best_file['size'] if best_file else 0,
            'file_size_str': file_size_str,
            'all_files': files[:5]
        })
        
        time.sleep(0.5)
    
    # Print statistics
    print(f"\n📊 Fetch Statistics:")
    print(f"   Total items: {len(results)}")
    print(f"   PDF files found: {pdf_count}")
    print(f"   Items with NO downloadable files: {no_files_count}")
    
    return results

def save_download_links(results: list, filename: str):
    """Save direct download links to file"""
    with open(filename, 'w', encoding='utf-8') as f:
        f.write(f"Internet Archive - Direct Download Links\n")
        f.write(f"="*60 + "\n")
        f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"Total items: {len(results)}\n")
        f.write(f"="*60 + "\n\n")
        
        for item in results:
            f.write(f"📖 {item['title']}\n")
            f.write(f"   Date: {item['date']}\n")
            f.write(f"   Archive.org: {item['archive_url']}\n")
            if item['file_url']:
                f.write(f"   📥 DIRECT DOWNLOAD: {item['file_url']}\n")
                f.write(f"   File: {item['file_name']} ({item['file_type']}, {item['file_size_str']} bytes)\n")
            else:
                f.write(f"   ⚠️ No downloadable file found\n")
            f.write(f"   Downloads: {item['downloads']:,}\n")
            f.write("\n")
    
    print(f"\n💾 Saved download links to: {filename}")

def save_pdf_links_only(results: list, filename: str):
    """Save only PDF download URLs (one per line)"""
    with open(filename, 'w', encoding='utf-8') as f:
        for item in results:
            if item['file_url'] and item['file_type'] == 'PDF':
                f.write(f"{item['file_url']}\n")
    
    pdf_count = len([r for r in results if r['file_url'] and r['file_type'] == 'PDF'])
    print(f"📥 Saved {pdf_count} PDF download links to: {filename}")

def save_urls_only(items: list, filename: str):
    """Save only Archive.org URLs to file"""
    with open(filename, 'w', encoding='utf-8') as f:
        for item in items:
            f.write(f"{item['url']}\n")
    
    print(f"🔗 Saved {len(items)} Archive.org URLs to: {filename}")

def save_direct_links_only(results: list, filename: str):
    """Save only direct download URLs (one per line)"""
    with open(filename, 'w', encoding='utf-8') as f:
        for item in results:
            if item['file_url']:
                f.write(f"{item['file_url']}\n")
    
    direct_count = len([r for r in results if r['file_url']])
    print(f"📥 Saved {direct_count} direct download links to: {filename}")

def print_results(items: list, max_display: int = 20):
    """Print results to console"""
    if not items:
        print("❌ No results found")
        return
    
    print(f"\n{'='*60}")
    print(f"RESULTS ({len(items)} items found)")
    print(f"{'='*60}\n")
    
    for i, item in enumerate(items[:max_display], 1):
        print(f"{i}. {item['title']}")
        print(f"   📅 {item['date']} | ⬇️ {item['downloads']:,}")
        print(f"   🔗 {item['url']}")
        print()
    
    if len(items) > max_display:
        print(f"... and {len(items) - max_display} more items\n")

def get_user_input():
    """Get search query and limit from user with defaults"""
    
    print("\n" + "="*60)
    print("INTERNET ARCHIVE SEARCH & DOWNLOAD")
    print("="*60)
    
    query = input("\n📝 Enter search term (e.g., 'pc zone', 'nintendo power', 'playstation magazine'): ").strip()
    
    if not query:
        print("❌ No search term entered!")
        sys.exit(1)
    
    print(f"   Searching for: {query}")
    
    default_limit = 500
    print(f"\n🔢 Number of results (press Enter for default: {default_limit})")
    limit_input = input("Limit: ").strip()
    
    if not limit_input:
        limit = default_limit
        print(f"   Using default: {limit}")
    else:
        try:
            limit = int(limit_input)
            if limit > 2000:
                print("⚠️ Limit too high, capping at 2000")
                limit = 2000
        except ValueError:
            print(f"Invalid input, using default: {default_limit}")
            limit = default_limit
    
    print(f"\n📥 Fetch download links? (y/N): ", end='')
    fetch_links = input().strip().lower()
    
    if fetch_links in ['y', 'yes']:
        print(f"\n🔢 Number to fetch (press Enter for all): ", end='')
        link_limit_input = input().strip()
        link_limit = int(link_limit_input) if link_limit_input else None
    else:
        link_limit = 0
    
    return query, limit, fetch_links in ['y', 'yes'], link_limit

def save_results(items: list, filename: str):
    """Save results to text file"""
    with open(filename, 'w', encoding='utf-8') as f:
        f.write(f"Internet Archive Search Results\n")
        f.write(f"="*60 + "\n")
        f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"Total items: {len(items)}\n")
        f.write(f"="*60 + "\n\n")
        
        for i, item in enumerate(items, 1):
            f.write(f"{i}. {item['title']}\n")
            f.write(f"   Date: {item['date']}\n")
            f.write(f"   Downloads: {item['downloads']:,}\n")
            f.write(f"   URL: {item['url']}\n")
            if item['description']:
                f.write(f"   Description: {item['description']}...\n")
            f.write("\n")

def generate_downloader_script(results: list, search_term: str):
    """Generate a bash script to download all PDFs using wget"""
    pdf_links = [r['file_url'] for r in results if r['file_url'] and r['file_type'] == 'PDF']
    
    if not pdf_links:
        return
    
    safe_name = sanitize_filename(search_term)
    output_file = f"{safe_name}_download_pdf.sh"
    
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write("#!/bin/bash\n")
        f.write(f"# Auto-generated download script for: {search_term}\n")
        f.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"# Total PDFs: {len(pdf_links)}\n\n")
        
        folder_name = f"{safe_name}_pdfs"
        f.write(f"mkdir -p {folder_name}\n\n")
        
        for i, link in enumerate(pdf_links, 1):
            filename = f"{safe_name}_{i:03d}.pdf"
            # FIXED: Use double quotes instead of single quotes
            f.write(f'echo "Downloading {filename}..."\n')
            f.write(f'wget -O {folder_name}/{filename} "{link}"\n')
            f.write(f"sleep 1\n\n")
    
    os.chmod(output_file, 0o755)
    print(f"🔧 Generated download script: {output_file}")

def main():
    query, limit, fetch_links, link_limit = get_user_input()
    
    # Search Archive.org
    items = search_archive(query, limit)
    if not items:
        return
    
    # FILTER by the search term (only keep items with the search term in title)
    items = filter_by_search_term(items, query)
    print(f"\n🎯 Filtered to {len(items)} items containing '{query}' in the title")
    
    print_results(items)
    
    # Use the search query for filenames
    base = sanitize_filename(query)
    save_results(items, f"{base}.txt")
    save_urls_only(items, f"{base}_urls.txt")
    
    if fetch_links and items:
        print("\n" + "-"*40)
        results = fetch_download_links_for_all(items, link_limit)
        
        if results:
            save_download_links(results, f"{base}_download_links.txt")
            save_direct_links_only(results, f"{base}_direct_urls.txt")
            save_pdf_links_only(results, f"{base}_pdf_urls.txt")
            
            # Generate a bash script to download all PDFs
            generate_downloader_script(results, query)
            
            pdf_count = len([r for r in results if r['file_type'] == 'PDF'])
            print(f"\n📊 Summary:")
            print(f"   Total items processed: {len(results)}")
            print(f"   PDF files found: {pdf_count}")
            print(f"   Direct download links: {len([r for r in results if r['file_url']])}")
            
            if pdf_count > 0:
                safe_name = sanitize_filename(query)
                print(f"\n💡 To download all PDFs, run: ./download_{safe_name}.sh")
    
    print(f"\n✅ Done!")

if __name__ == "__main__":
    main()