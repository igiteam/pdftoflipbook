# pdf_to_flipbook

Creates HTML flipbook from PDF - really cool

## Screenshots

![Example Output](https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/pdf-to-flipbook-example.gif)


## What is this?

This is an application that converts any PDF document into an interactive HTML flipbook with realistic page-turning effects. Just drag and drop a PDF, click convert, and you get a beautiful browser-based flipbook that works on desktop and mobile devices.

## Features

- Drag & drop PDF conversion
- Creates high-quality PNG images from each page
- Generates interactive HTML flipbook using Turn.js
- Bookmark ribbon for quick page navigation
- Mouse wheel scrolling support
- Touch-friendly for mobile devices
- Remembers last page you were reading
- Dual-page view in landscape, single-page in portrait
- Native macOS app with custom icon

## Installation Ubuntu
```
curl -o "pdf_to_flipbook_install_do.sh" "https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/pdf_to_flipbook_install_do.sh" && chmod +x "pdf_to_flipbook_install_do.sh" && sudo ./"pdf_to_flipbook_install_do.sh"
```

## Installation MACOSX

1. Run the `One-Click-Install.command` script
2. The app will be installed to `~/Applications/`
3. A copy will also be placed on your Desktop
4. The app will automatically launch after installation

## Usage

1. Launch PDF to FlipBook from your Applications folder or Desktop
2. Drag and drop any PDF file onto the app window
3. Click "Convert PDF to FlipBook"
4. Find your flipbook in the Downloads folder under `[PDFname]_FlipBook/`
5. Open the `[name]_flipbook.html` file in any web browser

## Requirements

- macOS 10.15 or later
- Xcode Command Line Tools (install with `xcode-select --install`)

## Output

The converter creates:

- PNG images of each page (saved as `[name]_page_1.png`, etc.)
- Interactive HTML flipbook (`[name]_flipbook.html`)
- All files saved to your Downloads folder

## How the Flipbook Works

- **Mouse/Touch**: Click and drag page corners to flip
- **Scroll wheel**: Scroll anywhere to navigate pages
- **Bookmark ribbon**: Drag the ribbon on the left side to jump pages
- **Orientation**: Automatically switches between single and dual-page view
- **Memory**: Saves your last read page in browser storage
- **Keyboard**: Left/right arrow keys to navigate

## Notes

- Large PDFs may take a few moments to convert
- Output images are optimized JPEGs (80% quality) for good balance of quality and file size
- The flipbook works offline once generated - all assets are self-contained

## License

Free to use and modify
![macOS App](https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/pdf-to-flipbook-macosx.png)
