#!/usr/bin/env python3
import re
import json
import sys
from pathlib import Path

def convert_js_to_json(js_file, json_file):
    """Convert JavaScript magazine list to JSON format"""
    
    # Read the JS file
    with open(js_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Extract the array content between the brackets
    match = re.search(r'var mag_list = (\[[\s\S]*?\]);', content)
    if not match:
        print("Error: Could not find 'var mag_list =' array in file")
        return False
    
    js_array_text = match.group(1)
    
    # Manual parsing approach - more reliable for this format
    magazines = []
    
    # Find each object between { and }
    object_pattern = r'\{([^}]+)\}'
    objects = re.findall(object_pattern, js_array_text)
    
    for obj in objects:
        # Extract title
        title_match = re.search(r'title:\s*"([^"]+)"', obj)
        # Extract pdfUrl
        url_match = re.search(r'pdfUrl:\s*"([^"]+)"', obj)
        
        if title_match and url_match:
            title = title_match.group(1)
            url = url_match.group(1)
            magazines.append({'title': title, 'pdfUrl': url})
    
    if not magazines:
        print("Error: Could not parse any magazines from the file")
        return False
    
    # Convert to desired format
    output = {}
    for item in magazines:
        title = item['title']
        url = item['pdfUrl']
        
        # Clean title for filesystem
        clean_title = re.sub(r'[^\w\s-]', '', title)  # Remove special chars
        clean_title = re.sub(r'\s+', '_', clean_title)  # Replace spaces with underscores
        clean_title = re.sub(r'_+', '_', clean_title)  # Replace multiple underscores
        clean_title = clean_title.strip('_')  # Remove trailing/leading underscores
        
        # Handle duplicate titles by adding a suffix
        if clean_title in output:
            counter = 2
            while f"{clean_title}_{counter}" in output:
                counter += 1
            clean_title = f"{clean_title}_{counter}"
        
        output[clean_title] = url
    
    # Save to JSON
    with open(json_file, 'w', encoding='utf-8') as f:
        json.dump(output, f, indent=2, ensure_ascii=False)
    
    print(f"✓ Successfully converted {len(magazines)} magazines")
    print(f"✓ Output saved to: {json_file}")
    print(f"\nFirst 3 magazines:")
    for i, (title, url) in enumerate(list(output.items())[:3]):
        print(f"  {i+1}. {title}")
        print(f"     {url}")
    
    return True

def main():
    # Default filenames
    js_file = sys.argv[1] if len(sys.argv) > 1 else "mag_list_xbox_original.js"
    json_file = sys.argv[2] if len(sys.argv) > 2 else "magazines.json"
    
    if not Path(js_file).exists():
        print(f"Error: File '{js_file}' not found!")
        print(f"Usage: python3 {sys.argv[0]} [input.js] [output.json]")
        sys.exit(1)
    
    convert_js_to_json(js_file, json_file)

if __name__ == "__main__":
    main()