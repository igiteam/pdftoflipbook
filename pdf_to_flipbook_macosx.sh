#!/bin/bash
# pdf_to_flipbook.sh
# Creates a macOS app for converting PDFs to Turn.js flipbooks

# ===============================================
# 1. COLOR OUTPUT & BANNER
# ===============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              PDF TO FLIPBOOK - Native macOS App          ║"
echo "║         Drag & Drop PDF → PNG Images + Flipbook HTML     ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ===============================================
# 2. APP NAME AND STRUCTURE SETUP
# ===============================================
read -p "Enter your Flipbook app name (default: PDF-To-FlipBook): " APPNAME
APPNAME=${APPNAME:-PDF-To-FlipBook}

if [ -d "$APPNAME" ]; then
    read -p "Folder '$APPNAME' already exists. Remove it? (y/N): " REMOVE
    REMOVE=${REMOVE:-N}
    if [[ "$REMOVE" == "y" || "$REMOVE" == "Y" ]]; then
        echo "Removing existing folder '$APPNAME'..."
        rm -rf "$APPNAME"
    else
        echo "Exiting to avoid overwriting."
        exit 1
    fi
fi

mkdir -p "$APPNAME/src" "$APPNAME/native" "$APPNAME/public" "$APPNAME/build"
cd "$APPNAME" || exit

# ===============================================
# 3. CREATE CUSTOM ICON
# ===============================================
echo -e "${CYAN}🎨 Downloading PDF icon...${NC}"

ICON_URL="https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/pdf_flipbook.png"

ICON_FILE="appicon.${ICON_URL##*.}"
ICON_FILE="${ICON_FILE%\?*}"

echo "📥 Downloading icon from: $ICON_URL"
curl -s -L "$ICON_URL" -o "/tmp/$ICON_FILE"

if [ -f "/tmp/$ICON_FILE" ] && [ -s "/tmp/$ICON_FILE" ]; then
    echo "✅ Icon downloaded successfully!"
    
    mkdir -p public
    cp "/tmp/$ICON_FILE" "public/app_icon.png"
    
    ICONSET_DIR="public/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    
    for SIZE in 16 32 64 128 256 512 1024; do
        sips -z $SIZE $SIZE "public/app_icon.png" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}.png" 2>/dev/null || true
        RETINA=$((SIZE * 2))
        sips -z $RETINA $RETINA "public/app_icon.png" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}@2x.png" 2>/dev/null || true
    done
    
    if command -v iconutil &> /dev/null; then
        iconutil -c icns "$ICONSET_DIR" -o "public/app_icon.icns" 2>/dev/null
        echo "✅ Created .icns file"
    else
        cp "public/app_icon.png" "public/app_icon.icns"
    fi
    
    rm -rf "$ICONSET_DIR"
else
    echo "⚠ Download failed, creating fallback icon"
    mkdir -p public
    cat > public/app_icon.png.b64 << 'EOF'
iVBORw0KGgoAAAANSUhEUgAAAgAAAAIAAQMAAADOtgr5AAAAAXNSR0IB2cksfwAAAAlwSFlzAAALEwAACxMBAJqcGAAAAANQTFRFAAAAp3o92gAAABxJREFUeJztwTEBAAAAwqD1T20Hb6AAAAAAAAA+Bhw4AAG1cXrRAAAAAElFTkSuQmCC
EOF
    base64 -D < public/app_icon.png.b64 > public/app_icon.png 2>/dev/null || {
        echo "PDF Icon" > public/app_icon.txt
    }
    cp public/app_icon.png public/app_icon.icns 2>/dev/null
    echo -e "${GREEN}✅ Created fallback icon${NC}"
fi

# ===============================================
# 4. CHECK SWIFT COMPILER
# ===============================================
echo -e "${CYAN}🔧 Checking Swift compiler...${NC}"

if ! command -v swiftc &> /dev/null; then
    echo -e "${RED}❌ Swift compiler not found${NC}"
    echo -e "${CYAN}🔄 Please install Xcode Command Line Tools:${NC}"
    echo "   xcode-select --install"
    exit 1
fi

echo -e "${GREEN}✅ Swift compiler found${NC}"

# ===============================================
# 5. CREATE SWIFT APP WITH COMPLETE HTML
# ===============================================
mkdir -p native/{Sources,Resources}
cd native || exit

echo "$APPNAME" > .appname

cat > Sources/main.swift << 'EOF'
import Cocoa
import PDFKit
import UniformTypeIdentifiers

class ViewController: NSViewController, NSDraggingDestination {
    private let dropZone = NSView()
    private let dropLabel = NSTextField(labelWithString: "")
    private let convertButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private var currentPDFURL: URL?
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupDragDrop()
    }
    
    private func setupUI() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        
        dropZone.frame = NSRect(x: 50, y: 150, width: 400, height: 180)
        dropZone.wantsLayer = true
        dropZone.layer?.backgroundColor = NSColor(white: 0.95, alpha: 1).cgColor
        dropZone.layer?.borderWidth = 2
        dropZone.layer?.borderColor = NSColor.systemBlue.cgColor
        dropZone.layer?.cornerRadius = 12
        
        dropLabel.stringValue = "📄 Drag & Drop PDF Here\n\nor\n\nClick to Select"
        dropLabel.alignment = .center
        dropLabel.font = NSFont.systemFont(ofSize: 14)
        dropLabel.textColor = NSColor.secondaryLabelColor
        dropLabel.frame = NSRect(x: 0, y: 40, width: 400, height: 100)
        dropZone.addSubview(dropLabel)
        
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(selectPDF))
        dropZone.addGestureRecognizer(clickGesture)
        
        convertButton.title = "📖 Convert PDF to FlipBook"
        convertButton.bezelStyle = .rounded
        convertButton.frame = NSRect(x: 150, y: 80, width: 200, height: 40)
        convertButton.target = self
        convertButton.action = #selector(convertPDF)
        convertButton.isEnabled = false
        
        statusLabel.frame = NSRect(x: 50, y: 40, width: 400, height: 30)
        statusLabel.alignment = .center
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = NSColor.secondaryLabelColor
        
        progressIndicator.isIndeterminate = false
        progressIndicator.style = .bar
        progressIndicator.frame = NSRect(x: 100, y: 20, width: 300, height: 12)
        progressIndicator.isHidden = true
        
        view.addSubview(dropZone)
        view.addSubview(convertButton)
        view.addSubview(statusLabel)
        view.addSubview(progressIndicator)
    }
    
    private func setupDragDrop() {
        view.registerForDraggedTypes([.fileURL, .URL])
    }
    
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let urls = getDraggedFileURLs(from: sender), !urls.isEmpty {
            return .copy
        }
        return []
    }
    
    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = getDraggedFileURLs(from: sender), let url = urls.first else {
            return false
        }
        
        if url.pathExtension.lowercased() == "pdf" {
            currentPDFURL = url
            dropLabel.stringValue = "✅ " + url.lastPathComponent + "\n\nReady to convert!"
            dropLabel.textColor = NSColor.systemGreen
            convertButton.isEnabled = true
            statusLabel.stringValue = "PDF loaded: " + url.lastPathComponent
            return true
        }
        
        statusLabel.stringValue = "⚠️ Please drop a PDF file"
        return false
    }
    
    func draggingExited(_ sender: NSDraggingInfo?) {}
    
    private func getDraggedFileURLs(from sender: NSDraggingInfo) -> [URL]? {
        let pasteboard = sender.draggingPasteboard
        let classes = [NSURL.self]
        let options: [NSPasteboard.ReadingOptionKey: Any] = [:]
        
        guard let items = pasteboard.readObjects(forClasses: classes, options: options) as? [URL] else {
            return nil
        }
        
        return items
    }
    
    @objc func selectPDF() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.pdf]
        openPanel.allowsMultipleSelection = false
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                self.currentPDFURL = url
                self.dropLabel.stringValue = "✅ " + url.lastPathComponent + "\n\nReady to convert!"
                self.dropLabel.textColor = NSColor.systemGreen
                self.convertButton.isEnabled = true
                self.statusLabel.stringValue = "PDF loaded: " + url.lastPathComponent
            }
        }
    }
    
    @objc func convertPDF() {
        guard let pdfURL = currentPDFURL else { return }
        
        convertButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.doubleValue = 0
        
        let fileName = pdfURL.deletingPathExtension().lastPathComponent
        let sanitizedName = fileName.replacingOccurrences(of: " ", with: "_")
        
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let outputFolder = downloadsURL.appendingPathComponent(sanitizedName + "_FlipBook")
        
        do {
            try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        } catch {
            statusLabel.stringValue = "❌ Failed to create output folder"
            convertButton.isEnabled = true
            return
        }
        
        statusLabel.stringValue = "📄 Loading PDF..."
        
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            statusLabel.stringValue = "❌ Failed to load PDF"
            convertButton.isEnabled = true
            return
        }
        
        let pageCount = pdfDocument.pageCount
        statusLabel.stringValue = "🖼️ Converting \(pageCount) pages to PNG..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            var successCount = 0
            
            for i in 0..<pageCount {
                DispatchQueue.main.async {
                    self.progressIndicator.doubleValue = Double(i + 1) / Double(pageCount) * 100
                    self.statusLabel.stringValue = "📸 Converting page \(i + 1) of \(pageCount)..."
                }
                
                guard let page = pdfDocument.page(at: i) else { continue }
                
                var pageRect = page.bounds(for: .cropBox)
                if pageRect == .zero {
                    pageRect = page.bounds(for: .mediaBox)
                }
                
                let scale: CGFloat = 1.5
                let imageSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
                
                let image = NSImage(size: imageSize)
                image.lockFocus()
                
                if let context = NSGraphicsContext.current?.cgContext {
                    context.setFillColor(NSColor.white.cgColor)
                    context.fill(CGRect(origin: .zero, size: imageSize))
                    
                    context.scaleBy(x: scale, y: scale)
                    page.draw(with: .cropBox, to: context)
                }
                
                image.unlockFocus()
                
                let pageNumber = i + 1
                let imagePath = outputFolder.appendingPathComponent("\(sanitizedName)_page_\(pageNumber).png")
                
                guard let tiffData = image.tiffRepresentation,
                      let bitmapImage = NSBitmapImageRep(data: tiffData) else { continue }
                
                let compressionFactor: Float = 0.8
                guard let imageData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor]) else { continue }
                
                do {
                    try imageData.write(to: imagePath)
                    successCount += 1
                } catch {
                    print("Failed to save page \(pageNumber): \(error)")
                }
                
                Thread.sleep(forTimeInterval: 0.05)
            }
            
            DispatchQueue.main.async {
                if successCount > 0 {
                    self.statusLabel.stringValue = "📝 Generating HTML..."
                    let html = self.generateExternalHTML(pageCount: pageCount, title: sanitizedName)
                    let htmlPath = outputFolder.appendingPathComponent("\(sanitizedName)_flipbook.html")
                    do {
                        try html.write(to: htmlPath, atomically: true, encoding: .utf8)
                        self.statusLabel.stringValue = "✅ Complete! \(successCount)/\(pageCount) pages saved to Downloads/\(sanitizedName)_FlipBook"
                    } catch {
                        self.statusLabel.stringValue = "❌ Failed to save HTML"
                    }
                } else {
                    self.statusLabel.stringValue = "❌ Failed to convert any pages"
                }
                self.progressIndicator.isHidden = true
                self.convertButton.isEnabled = true
                
                NSWorkspace.shared.open(outputFolder)
            }
        }
    }
    
    private func generateExternalHTML(pageCount: Int, title: String) -> String {
        if pageCount == 0 {
            return ""
        }
        
        let safeTitle = title.replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\"", with: "\\\"")
        
        let html = """
        <!DOCTYPE html>
        <html>
        
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
            <title>\(safeTitle)</title>
            <script type="text/javascript" src="https://code.jquery.com/jquery-1.7.1.min.js"></script>
            <script type="text/javascript" src="https://cdn.jsdelivr.net/gh/igiteam/pdftoflipbook@refs/heads/main/magazine_turn.js"></script>
            <style>
                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                }
        
                body {
                    background: #2c3e50;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    min-height: 100vh;
                    font-family: 'Segoe UI', Arial, sans-serif;
                    padding: 0px;
                    overflow: hidden;
                    position: fixed;
                    top: 0;
                    left: 0;
                    right: 0;
                    bottom: 0;
                    -webkit-overflow-scrolling: touch;
                    overscroll-behavior: none;
                }
        
                #magazine {
                    width: 100vw;
                    height: 100vh;
                    background: #fff;
                    overscroll-behavior: none;
                }
        
                #magazine .turn-page {
                    background-size: 100.5% 100.5% !important;
                    background-position: center;
                    background-repeat: no-repeat;
                    background-color: #cbcbcb63;
                }
        
                html {
                    overflow: hidden;
                    position: fixed;
                    width: 100%;
                    height: 100%;
                    overscroll-behavior: none;
                    touch-action: pan-y pinch-zoom;
                }
        
                .turn-page.loading {
                    position: relative;
                }
        
                .turn-page.loading::after {
                    content: "📰";
                    position: absolute;
                    top: 50%;
                    left: 50%;
                    transform: translate(-50%, -50%);
                    font-size: 40px;
                    animation: spin 1s linear infinite;
                }
        
                @keyframes spin {
                    from {
                        transform: translate(-50%, -50%) rotate(0deg);
                    }
                    to {
                        transform: translate(-50%, -50%) rotate(360deg);
                    }
                }
        
                @media (hover: none) and (pointer: coarse) {
                    html, body {
                        margin: 0 !important;
                        padding: 0 !important;
                        top: 0 !important;
                        left: 0 !important;
                        position: fixed !important;
                    }
                    body {
                        display: block !important;
                        align-items: flex-start !important;
                        justify-content: flex-start !important;
                    }
                    #magazine {
                        top: 0 !important;
                        left: 0 !important;
                        position: absolute !important;
                        margin: 0 !important;
                    }
                    #pageScrollOverlay {
                        top: 0 !important;
                        bottom: 0 !important;
                        transform: translateX(-50%) !important;
                    }
                }
            </style>
        </head>
        
        <body>
            <div id="magazine"></div>
            <script>
                const totalPages = \(pageCount);
                const title = '\(safeTitle)';
                
                let currentPageNumber = 1;
                let turnInstance = null;
                let isRebuilding = false;
                let loadedPages = new Set();
                let loadingPages = new Set();
                let preloadQueue = [];
                
                function getSavedPage() {
                    const storageKey = 'flipbook_last_page_' + title;
                    const saved = localStorage.getItem(storageKey);
                    if (saved && !isNaN(saved) && saved >= 1 && saved <= totalPages) {
                        return parseInt(saved);
                    }
                    return 1;
                }
        
                function savePage(pageNum) {
                    const storageKey = 'flipbook_last_page_' + title;
                    localStorage.setItem(storageKey, pageNum);
                }
                
                function createMagazine() {
                    const magazine = $('#magazine');
                    magazine.empty();
                    for (let i = 1; i <= totalPages; i++) {
                        const pageDiv = $('<div>')
                            .addClass('turn-page loading')
                            .attr('data-page', i)
                            .attr('data-loaded', 'false');
                        magazine.append(pageDiv);
                    }
                }
                
                function loadPageImage(pageNum, priority = false) {
                    return new Promise((resolve) => {
                        if (loadedPages.has(pageNum) || loadingPages.has(pageNum)) {
                            resolve();
                            return;
                        }
                        const pageDiv = $('.turn-page[data-page="' + pageNum + '"]');
                        if (!pageDiv.length) {
                            resolve();
                            return;
                        }
                        if (pageDiv.attr('data-loaded') === 'true') {
                            loadedPages.add(pageNum);
                            resolve();
                            return;
                        }
                        loadingPages.add(pageNum);
                        const img = new Image();
                        const imgPath = title + '_page_' + pageNum + '.png';
                        img.onload = function () {
                            pageDiv.css('background-image', 'url(' + imgPath + ')');
                            pageDiv.removeClass('loading');
                            pageDiv.attr('data-loaded', 'true');
                            loadedPages.add(pageNum);
                            loadingPages.delete(pageNum);
                            if (priority) console.log('[Priority] Page ' + pageNum + ' loaded');
                            resolve();
                        };
                        img.onerror = function () {
                            pageDiv.css('background-image', 'url(\\'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="100%25" height="100%25"%3E%3Crect width="100%25" height="100%25" fill="%23333"/%3E%3Ctext x="50%25" y="50%25" text-anchor="middle" fill="%23666" font-size="20"%3EPage ' + pageNum + '%3C/text%3E%3C/svg%3E\\')');
                            pageDiv.removeClass('loading');
                            pageDiv.attr('data-loaded', 'error');
                            loadingPages.delete(pageNum);
                            console.warn('Failed to load page ' + pageNum + ': ' + imgPath);
                            resolve();
                        };
                        img.src = imgPath;
                    });
                }
                
                function preloadNearbyPages(currentPage, displayMode) {
                    let pagesToPreload = [];
                    if (displayMode === 'single') {
                        pagesToPreload = [currentPage + 1, currentPage + 2, currentPage + 3, currentPage + 4, currentPage + 5, currentPage - 1, currentPage - 2];
                    } else {
                        pagesToPreload = [currentPage + 1, currentPage + 2, currentPage + 3, currentPage + 4, currentPage - 1, currentPage - 2];
                    }
                    const pagesToLoad = pagesToPreload.filter(pageNum => {
                        return pageNum >= 1 && pageNum <= totalPages && !loadedPages.has(pageNum) && !loadingPages.has(pageNum);
                    });
                    if (pagesToLoad.length > 0) {
                        if (displayMode === 'single' && currentPage + 1 <= totalPages && !loadedPages.has(currentPage + 1)) {
                            loadPageImage(currentPage + 1, true);
                        }
                        pagesToLoad.forEach((pageNum, index) => {
                            if (pageNum !== currentPage + 1) {
                                setTimeout(() => {
                                    if (!loadedPages.has(pageNum) && !loadingPages.has(pageNum)) loadPageImage(pageNum);
                                }, index * 150);
                            }
                        });
                    }
                }
                
                function initFlipBook() {
                    if (isRebuilding) return;
                    isRebuilding = true;
                    const isLandscape = window.matchMedia('(orientation: landscape)').matches;
                    const displayMode = isLandscape ? 'double' : 'single';
                    let pageToRestore = currentPageNumber;
                    if (pageToRestore < 1) pageToRestore = 1;
                    if (pageToRestore > totalPages) pageToRestore = totalPages;
                    if (turnInstance) {
                        try { $('#magazine').turn('destroy'); } catch (e) { console.log('Destroy error:', e); }
                    }
                    setTimeout(() => {
                        $('#magazine').turn({
                            display: displayMode,
                            acceleration: true,
                            gradients: !$.isTouch,
                            elevation: 50,
                            duration: 400,
                            page: pageToRestore,
                            when: {
                                turning: function (e, page) {
                                    if (page >= 1 && page <= totalPages && !loadedPages.has(page)) loadPageImage(page, true);
                                },
                                turned: function (e, page) {
                                    currentPageNumber = page;
                                    savePage(page);
                                    const currentDisplayMode = $(this).turn('display');
                                    const visiblePages = $(this).turn('view');
                                    visiblePages.forEach(pageNum => { if (pageNum > 0 && pageNum <= totalPages) loadPageImage(pageNum); });
                                    preloadNearbyPages(page, currentDisplayMode);
                                },
                                first: function () {
                                    const firstPages = $(this).turn('view');
                                    firstPages.forEach(pageNum => { if (pageNum > 0 && pageNum <= totalPages) loadPageImage(pageNum); });
                                    const currentDisplayMode = $(this).turn('display');
                                    preloadNearbyPages(pageToRestore, currentDisplayMode);
                                },
                                missing: function (e, pages) {
                                    for (let i = 0; i < pages.length; i++) {
                                        if (pages[i] >= 1 && pages[i] <= totalPages) loadPageImage(pages[i], true);
                                    }
                                }
                            }
                        });
                        turnInstance = $('#magazine');
                        isRebuilding = false;
                        console.log('Flip book initialized: ' + displayMode + ' mode, page ' + pageToRestore);
                    }, 50);
                }
                
                createMagazine();
                
                async function initialPreload() {
                    for (let i = 1; i <= 6; i++) {
                        if (i <= totalPages) await loadPageImage(i, true);
                    }
                    console.log('Initial preload complete');
                }
                
                currentPageNumber = getSavedPage();
                initialPreload();
                $(window).ready(function () { initFlipBook(); });
                
                $(window).on('orientationchange', function () {
                    if (turnInstance) {
                        try {
                            const currentView = turnInstance.turn('view');
                            if (currentView && currentView.length) currentPageNumber = currentView[0] || currentPageNumber;
                        } catch (e) { }
                    }
                    setTimeout(() => {
                        createMagazine();
                        loadedPages.clear();
                        loadingPages.clear();
                        preloadQueue = [];
                        initFlipBook();
                        initialPreload();
                    }, 100);
                });
                
                let resizeTimer;
                $(window).on('resize', function () {
                    clearTimeout(resizeTimer);
                    resizeTimer = setTimeout(() => {
                        if (turnInstance) {
                            try {
                                const currentView = turnInstance.turn('view');
                                if (currentView && currentView.length) currentPageNumber = currentView[0] || currentPageNumber;
                            } catch (e) { }
                            const isLandscape = window.matchMedia('(orientation: landscape)').matches;
                            const displayMode = isLandscape ? 'double' : 'single';
                            if (turnInstance.turn('display') !== displayMode) {
                                setTimeout(() => {
                                    createMagazine();
                                    loadedPages.clear();
                                    loadingPages.clear();
                                    preloadQueue = [];
                                    initFlipBook();
                                    initialPreload();
                                }, 100);
                            } else {
                                try { turnInstance.turn('resize'); } catch (e) { }
                            }
                        }
                    }, 200);
                });
                
                $(window).bind('keydown', function (e) {
                    if (e.keyCode == 37) { $('#magazine').turn('previous'); e.preventDefault(); }
                    else if (e.keyCode == 39) { $('#magazine').turn('next'); e.preventDefault(); }
                });
                
                document.body.addEventListener('touchmove', function (e) {
                    if (e.target === document.body || e.target === document.documentElement) e.preventDefault();
                }, { passive: false });
                
                document.body.addEventListener('touchend', function () {
                    setTimeout(() => {
                        if (turnInstance) {
                            try {
                                const currentView = turnInstance.turn('view');
                                if (currentView && currentView.length) {
                                    currentPageNumber = currentView[0] || currentPageNumber;
                                    savePage(currentPageNumber);
                                }
                            } catch (e) { }
                        }
                    }, 100);
                });
                
                console.log('Flip book initialized with ' + totalPages + ' pages (aggressive preloading enabled)');
                console.log('Next page is preloaded before you flip for smooth transitions');
            </script>
            <script>
                (function () {
                    let pageScrollDragging = false;
                    let pageTrackStartY = 0;
                    let pageTrackStartScroll = 0;
                    let currentTotalPages = \(pageCount);
                    let hideTimeout = null;
                    let activeTimeout = null;
        
                    function getSavedPage() {
                        const storageKey = 'flipbook_last_page_' + title;
                        const saved = localStorage.getItem(storageKey);
                        if (saved && !isNaN(saved) && saved >= 1 && saved <= currentTotalPages) {
                            return parseInt(saved);
                        }
                        return 1;
                    }
        
                    function savePage(pageNum) {
                        const storageKey = 'flipbook_last_page_' + title;
                        localStorage.setItem(storageKey, pageNum);
                    }
        
                    function createScrollOverlay() {
                        if (document.getElementById('pageScrollOverlay')) return;
                        const overlayHTML = `
                <div id="pageScrollOverlay" style="
                    position: fixed;
                    left: 50%;
                    transform: translateX(-50%);
                    top: 0;
                    bottom: 0;
                    z-index: 9999;
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    justify-content: center;
                    pointer-events: none;
                    opacity: 0;
                    transition: opacity 0.3s ease;
                ">
                    <div class="vertical-ribbon-base" style="
                        position: absolute;
                        overflow: hidden;
                        left: 50%;
                        transform: translateX(-50%);
                        top: 0;
                        bottom: 0;
                        font-size: 14px;
                        font-weight: bold;
                        color: #fff;
                        --r: 0.8em;
                        border-inline: 0.5em solid #0000;
                        padding: 0.5em 0.2em calc(var(--r) + 0.2em);
                        clip-path: polygon(0 0, 100% 0, 100% 100%, calc(100% - 0.5em) 100%, 50% calc(100% - var(--r)), 0.5em 100%, 0 100%);
                        background: url('https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/ribbon.png') repeat-y center top / 100% auto;
                        width: 48px;
                        height: 85vh;
                        max-height: 85%;
                        display: flex;
                        align-items: center;
                        justify-content: center;
                        white-space: nowrap;
                        box-shadow: 2px 2px 8px rgba(0,0,0,0.3);
                        z-index: 9998;
                    ">
                        <span style="writing-mode: vertical-rl; text-orientation: mixed;"></span>
                    </div>
                    
                    <div id="pageDisplayCenter" style="
                        position: absolute;
                        left: 28px;
                        top: calc(50% - 3px);
                        transform: translateY(-50%);
                        font-family: 'Georgia', 'Times New Roman', serif;
                        font-size: 12px;
                        font-weight: normal;
                        font-style: italic;
                        color: #fff8e7;
                        background: url('https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/ribbon2.png') no-repeat center / 100% 100%;
                        padding: 8px;
                        border-radius: 0 4px 4px 0;
                        backdrop-filter: blur(4px);
                        pointer-events: none;
                        white-space: nowrap;
                        z-index: 10;
                        box-shadow: 2px 2px 8px rgba(0,0,0,0.3);
                        opacity: 0;
                        transition: opacity 0.2s ease;
                        letter-spacing: 0.5px;
                    ">
                        <span style="font-family: monospace; font-style: normal; font-weight: bold;"></span>${getSavedPage()} / ${currentTotalPages}
                    </div>
                    
                    <div id="pageSliderContainer" style="
                        position: relative;
                        width: 32px;
                        height: 85vh;
                        max-height: 85%;
                        background: transparent;
                        touch-action: none;
                        pointer-events: auto;
                        cursor: grab;
                        z-index: 9999;
                    ">
                        <div style="
                            position: absolute;
                            top: 0;
                            left: 0;
                            width: 100%;
                            height: 88vh;
                            max-height: 88%;
                            overflow: hidden;
                            pointer-events: none;
                        ">
                            <div id="pageTrack" style="
                                position: absolute;
                                top: 0;
                                left: 0;
                                width: 100%;
                                transition: none;
                            "></div>
                        </div>
                        
                        <div style="
                            position: absolute;
                            left: 50%;
                            top: 50%;
                            transform: translate(-50%, -50%);
                            font-size: 20px;
                            font-weight: bold;
                            color: #fff;
                            --r: 0.5em;
                            border-inline: 0.3em solid #0000;
                            padding: 0.3em 0.15em calc(var(--r) + 0.15em);
                            clip-path: polygon(0 0, 100% 0, 100% 100%, calc(100% - 0.3em) calc(100% - var(--r)), 50% 100%, 0.3em calc(100% - var(--r)), 0 100%);
                            width: 36px;
                            height: 40px;
                            white-space: nowrap;
                            z-index: 15;
                            pointer-events: none;
                            display: flex;
                            align-items: center;
                            justify-content: center;
                        ">
                            <span style="writing-mode: vertical-rl; text-orientation: mixed;">📖</span>
                        </div>
                    </div>
                </div>
            `;
                        document.body.insertAdjacentHTML('beforeend', overlayHTML);
                        // Set initial position based on display mode
                        updateOverlayPosition();
                    }
        
                    // Add this new function to update overlay position based on display mode
                    function updateOverlayPosition() {
                        const overlay = document.getElementById('pageScrollOverlay');
                        if (!overlay) return;
        
                        const isLandscape = window.matchMedia('(orientation: landscape)').matches;
                        const displayMode = isLandscape ? 'double' : 'single';
        
                        // Detect iPad
                        const isIPad = /iPad|Macintosh/.test(navigator.userAgent) && 'ontouchend' in document;
        
                        if (displayMode === 'single') {
                            // Single page mode - position on left side with iPad adjustment
                            if (isIPad) {
                                overlay.style.left = '15px';  // Fix for iPad - was -15px, now positive offset
                            } else {
                                overlay.style.left = '0px';
                            }
                            overlay.style.transform = 'translateX(0)';
                        } else {
                            // Double page mode - position in center
                            overlay.style.left = '50%';
                            overlay.style.transform = 'translateX(-50%)';
                        }
                    }
        
                    function showOverlay(duration) { duration = duration || 3000; const o=document.getElementById('pageScrollOverlay'); if(o){o.style.opacity='1';if(hideTimeout)clearTimeout(hideTimeout);hideTimeout=setTimeout(function(){if(o&&!pageScrollDragging)o.style.opacity='0';},duration);} }
                    function showDisplay(duration) { duration = duration || 3000; const d=document.getElementById('pageDisplayCenter'); if(d){d.style.opacity='1';if(activeTimeout)clearTimeout(activeTimeout);activeTimeout=setTimeout(function(){if(d&&!pageScrollDragging)d.style.opacity='0';},duration);} }
                    function updatePageDisplay(pageNum) { const d=document.getElementById('pageDisplayCenter'); if(d){d.innerHTML='<span style=\"font-family:monospace;font-style:normal;font-weight:bold;\"></span>' + pageNum + '/' + currentTotalPages; savePage(pageNum); showDisplay();} }
        
                    function createPageNotches() {
                        const track = document.getElementById('pageTrack');
                        const container = document.getElementById('pageSliderContainer');
                        if (!track || !container) return;
                        track.innerHTML = '';
                        const notchCount = Math.min(currentTotalPages, 51);
                        const containerHeight = container.offsetHeight;
                        const notchSpacing = containerHeight / (notchCount - 1);
                        const centerX = container.offsetWidth / 2;
                        const centerY = containerHeight / 2;
                        const centerIndex = Math.floor(notchCount / 2);
                        for (let i = 0; i < notchCount; i++) {
                            const notch = document.createElement('div');
                            notch.style.position = 'absolute';
                            notch.style.borderRadius = '1px';
                            notch.style.pointerEvents = 'none';
                            const yPos = i * notchSpacing;
                            const offsetFromCenter = i - centerIndex;
                            if (offsetFromCenter === 0) {
                                notch.style.width = '22px';
                                notch.style.height = '3px';
                                notch.style.left = (centerX - 11) + 'px';
                                notch.style.backgroundColor = 'rgba(255,215,0,0.9)';
                                notch.style.boxShadow = '0 0 4px rgba(255,215,0,0.5)';
                            } else if (Math.abs(offsetFromCenter) % 5 === 0) {
                                notch.style.width = '18px';
                                notch.style.height = '2px';
                                notch.style.left = (centerX - 9) + 'px';
                                notch.style.backgroundColor = 'rgba(255,215,150,0.8)';
                            } else {
                                notch.style.width = '10px';
                                notch.style.height = '1.5px';
                                notch.style.left = (centerX - 5) + 'px';
                                notch.style.backgroundColor = 'rgba(255,235,200,0.6)';
                            }
                            notch.style.top = yPos + 'px';
                            track.appendChild(notch);
                        }
                        track.style.height = containerHeight + 'px';
                    }
        
                    function setupPageScrolling() {
                        const container = document.getElementById('pageSliderContainer');
                        const track = document.getElementById('pageTrack');
                        const overlay = document.getElementById('pageScrollOverlay');
                        if (!container || !track) return;
                        function getPageFromScroll(scrollY) { const containerHeight=container.offsetHeight,centerY=containerHeight/2,progress=(-scrollY+centerY)/containerHeight,clamped=Math.max(0,Math.min(1,progress)); return Math.floor(clamped*(currentTotalPages-1))+1; }
                        function updatePageFromScroll(scrollY) { if(!pageScrollDragging)return; const pageNum=getPageFromScroll(scrollY); updatePageDisplay(pageNum); const $magazine=$('#magazine'); if($magazine&&$magazine.turn)$magazine.turn('page',pageNum); }
                        function setTrackPosition(pageNum) { if(!track||!container)return; const progress=(pageNum-1)/(currentTotalPages-1),containerHeight=container.offsetHeight,centerY=containerHeight/2,scrollY=-(progress*containerHeight)+centerY; track.style.transform='translateY('+scrollY+'px)'; }
                        function startDrag(){ pageScrollDragging=true; showOverlay(2000); container.style.cursor='grabbing'; if(hideTimeout)clearTimeout(hideTimeout); if(activeTimeout)clearTimeout(activeTimeout); }
                        function endDrag(){ pageScrollDragging=false; container.style.cursor='grab'; const scroll=parseFloat((track.style.transform||'').match(/translateY\\(([^)]+)/)?.[1]||0),pageNum=getPageFromScroll(scroll); setTrackPosition(pageNum); updatePageDisplay(pageNum); if(hideTimeout)clearTimeout(hideTimeout); hideTimeout=setTimeout(function(){ const o=document.getElementById('pageScrollOverlay'); if(o&&!pageScrollDragging)o.style.opacity='0'; },2000); if(activeTimeout)clearTimeout(activeTimeout); activeTimeout=setTimeout(function(){ const d=document.getElementById('pageDisplayCenter'); if(d&&!pageScrollDragging)d.style.opacity='0'; },2000); }
                        container.addEventListener('mousedown',function(e){ e.preventDefault(); startDrag(); pageTrackStartY=e.clientY; const transform=track.style.transform; pageTrackStartScroll=transform&&transform.includes('translateY')?parseFloat(transform.match(/translateY\\(([^)]+)/)[1]):0; updatePageDisplay(getPageFromScroll(pageTrackStartScroll)); });
                        document.addEventListener('mousemove',function(e){ if(!pageScrollDragging)return; e.preventDefault(); const delta=e.clientY-pageTrackStartY,newScroll=pageTrackStartScroll+delta; track.style.transform='translateY('+newScroll+'px)'; updatePageFromScroll(newScroll); });
                        document.addEventListener('mouseup',function(){ if(pageScrollDragging)endDrag(); });
                        container.addEventListener('touchstart',function(e){ e.preventDefault(); startDrag(); pageTrackStartY=e.touches[0].clientY; const transform=track.style.transform; pageTrackStartScroll=transform&&transform.includes('translateY')?parseFloat(transform.match(/translateY\\(([^)]+)/)[1]):0; updatePageDisplay(getPageFromScroll(pageTrackStartScroll)); },{passive:false});
                        container.addEventListener('touchmove',function(e){ if(!pageScrollDragging)return; e.preventDefault(); const delta=e.touches[0].clientY-pageTrackStartY,newScroll=pageTrackStartScroll+delta; track.style.transform='translateY('+newScroll+'px)'; updatePageFromScroll(newScroll); },{passive:false});
                        container.addEventListener('touchend',function(e){ if(pageScrollDragging)endDrag(); e.preventDefault(); });
                        const $magazine=$('#magazine'); if($magazine&&$magazine.turn){ $magazine.bind('turned',function(e,page){ if(!pageScrollDragging){ setTrackPosition(page); updatePageDisplay(page); } }); }
                        const savedPage=getSavedPage();
                        setTimeout(function(){ createPageNotches(); setTrackPosition(savedPage); updatePageDisplay(savedPage); if(overlay)overlay.style.opacity='1'; showOverlay(3000); showDisplay(3000); },100);
                        setTimeout(function(){ const $magazine=$('#magazine'); if($magazine&&$magazine.turn)$magazine.turn('page',savedPage); },300);
                    }
        
                    function init(){
                        createScrollOverlay();
                        let attempts=0;
                        const interval=setInterval(function(){ attempts++; const $magazine=$('#magazine'); if(($magazine&&$magazine.turn&&typeof $magazine.turn('page')!=='undefined')||attempts>40){ clearInterval(interval); setTimeout(setupPageScrolling,200); } },100);
                    }
                    if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init); else init();
                })();
            </script>
            <script>
                (function fixiOSHeight() {
                    if(/iPad|iPhone|iPod/.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1)){
                        function adjustHeight(){ const vh=window.visualViewport?window.visualViewport.height:window.innerHeight; const magazine=document.getElementById('magazine'); if(magazine){ magazine.style.height=vh+'px'; magazine.style.top='0'; magazine.style.position='absolute'; } document.body.style.margin='0'; document.body.style.padding='0'; document.body.style.top='0'; document.body.style.position='fixed'; document.documentElement.style.margin='0'; document.documentElement.style.padding='0'; document.documentElement.style.top='0'; const slider=document.getElementById('pageSliderContainer'),ribbon=document.querySelector('.vertical-ribbon-base'),overlay=document.getElementById('pageScrollOverlay'); if(slider){ slider.style.height=(vh*0.85)+'px'; slider.style.maxHeight=(vh*0.85)+'px'; slider.style.top='auto'; slider.style.bottom='auto'; } if(ribbon){ ribbon.style.height=(vh*0.85)+'px'; ribbon.style.maxHeight=(vh*0.85)+'px'; } if(overlay){ overlay.style.top='0'; overlay.style.bottom='0'; } setTimeout(function(){ if(typeof createPageNotches==='function')createPageNotches(); if(typeof setTrackPosition==='function'&&window.currentPageNumber)setTrackPosition(window.currentPageNumber); },50); }
                        adjustHeight(); window.visualViewport?.addEventListener('resize',adjustHeight); window.addEventListener('resize',adjustHeight); window.addEventListener('orientationchange',function(){ setTimeout(adjustHeight,50); }); setTimeout(adjustHeight,100);
                    }
                })();
            </script>
            <script>
                (function(){
                    let wheelTimeout=null,lastScrollTime=0,isScrolling=false; const scrollThrottle=80;
                    function getPageFromScroll(scrollY){ const container=document.getElementById('pageSliderContainer'); if(!container)return 1; const containerHeight=container.offsetHeight,centerY=containerHeight/2,progress=(-scrollY+centerY)/containerHeight,clamped=Math.max(0,Math.min(1,progress)); return Math.floor(clamped*(\(pageCount)-1))+1; }
                    function setTrackPosition(pageNum){ const track=document.getElementById('pageTrack'),container=document.getElementById('pageSliderContainer'); if(!track||!container)return; const progress=(pageNum-1)/(\(pageCount)-1),containerHeight=container.offsetHeight,centerY=containerHeight/2,scrollY=-(progress*containerHeight)+centerY; track.style.transform='translateY('+scrollY+'px)'; }
                    function updatePageDisplayWithoutSave(pageNum){ const display=document.getElementById('pageDisplayCenter'); if(display){ display.innerHTML='<span style=\"font-family:monospace;font-style:normal;font-weight:bold;\"></span>' + pageNum + '/' + \(pageCount); } }
                    function savePageAndUpdateDisplay(pageNum){ const display=document.getElementById('pageDisplayCenter'); if(display){ display.innerHTML='<span style=\"font-family:monospace;font-style:normal;font-weight:bold;\"></span>' + pageNum + '/' + \(pageCount); localStorage.setItem('flipbook_last_page_'+title,pageNum); } }
                    function handleWheel(e){ if(window.pageScrollDragging)return; const container=document.getElementById('pageSliderContainer'),track=document.getElementById('pageTrack'); if(!container||!track)return; const now=Date.now(); if(now-lastScrollTime<scrollThrottle)return; lastScrollTime=now; e.preventDefault(); const overlay=document.getElementById('pageScrollOverlay'),display=document.getElementById('pageDisplayCenter'); if(overlay)overlay.style.opacity='1'; if(display)display.style.opacity='1'; if(window.wheelHideTimeout)clearTimeout(window.wheelHideTimeout); if(window.wheelDisplayTimeout)clearTimeout(window.wheelDisplayTimeout); window.wheelHideTimeout=setTimeout(function(){ if(overlay&&!window.pageScrollDragging&&!isScrolling)overlay.style.opacity='0'; },1500); window.wheelDisplayTimeout=setTimeout(function(){ if(display&&!window.pageScrollDragging&&!isScrolling)display.style.opacity='0'; },1500); const currentScroll=parseFloat((track.style.transform||'').match(/translateY\\(([^)]+)/)?.[1]||0),sensitivity=1.5,delta=e.deltaY*sensitivity; let newScroll=currentScroll+delta; const containerHeight=container.offsetHeight,centerY=containerHeight/2,minScroll=-centerY,maxScroll=containerHeight-centerY; newScroll=Math.max(minScroll,Math.min(maxScroll,newScroll)); track.style.transform='translateY('+newScroll+'px)'; const pageNum=getPageFromScroll(newScroll); updatePageDisplayWithoutSave(pageNum); const $magazine=$('#magazine'); if($magazine&&$magazine.turn)$magazine.turn('page',pageNum); if(wheelTimeout)clearTimeout(wheelTimeout); wheelTimeout=setTimeout(function(){ isScrolling=true; const finalScroll=parseFloat((track.style.transform||'').match(/translateY\\(([^)]+)/)?.[1]||0),finalPage=getPageFromScroll(finalScroll); setTrackPosition(finalPage); savePageAndUpdateDisplay(finalPage); const $magazine=$('#magazine'); if($magazine&&$magazine.turn)$magazine.turn('page',finalPage); setTimeout(function(){ isScrolling=false; },200); },100); }
                    function initWheelScrolling(){ window.currentTotalPages=\(pageCount); window.pageScrollDragging=false; window.addEventListener('wheel',handleWheel,{passive:false}); }
                    if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',initWheelScrolling); else initWheelScrolling();
                })();
            </script>
        </body>
        
        </html>
        """
        
        return html
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let viewController = ViewController()
        window = NSWindow(contentViewController: viewController)
        window.title = "PDF to FlipBook Converter"
        window.setContentSize(NSSize(width: 500, height: 400))
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.minSize = NSSize(width: 450, height: 350)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
EOF

# ===============================================
# 6. CREATE BUILD SCRIPT
# ===============================================
cat > build_app.sh << 'EOF'
#!/bin/bash

APPNAME=$(cat .appname 2>/dev/null || echo "PDF-To-FlipBook")

echo "🔨 Building $APPNAME..."
echo ""

rm -rf build dist 2>/dev/null || true
mkdir -p build dist

echo "📦 Compiling Swift code..."
swiftc Sources/main.swift \
    -framework Cocoa \
    -framework PDFKit \
    -o build/app_binary 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Compilation failed"
    exit 1
fi

echo "✅ Compilation successful!"
echo ""
echo "📦 Creating app bundle: $APPNAME.app"
APP_BUNDLE="dist/$APPNAME.app"
rm -rf "$APP_BUNDLE" 2>/dev/null || true
mkdir -p "$APP_BUNDLE/Contents/"{MacOS,Resources}

cp build/app_binary "$APP_BUNDLE/Contents/MacOS/$APPNAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APPNAME"
echo "✅ Copied binary"

if [ -f "../public/app_icon.icns" ] && [ -s "../public/app_icon.icns" ]; then
    cp "../public/app_icon.icns" "$APP_BUNDLE/Contents/Resources/app_icon.icns"
    echo "✅ Copied .icns icon"
elif [ -f "../public/app_icon.png" ] && [ -s "../public/app_icon.png" ]; then
    cp "../public/app_icon.png" "$APP_BUNDLE/Contents/Resources/app_icon.icns"
    echo "✅ Copied .png as icon"
else
    echo "⚠ No icon found, app will use default"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" << INFO_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APPNAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.flipbook.${APPNAME//-/_}</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$APPNAME</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSUIElement</key>
    <false/>
    <key>CFBundleIconFile</key>
    <string>app_icon.icns</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
INFO_EOF
echo "✅ Created Info.plist"

echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

if [ -d "$APP_BUNDLE" ]; then
    echo ""
    echo "🎉 BUILD SUCCESSFUL!"
    echo "📁 App bundle: $APP_BUNDLE"
else
    echo "❌ App bundle creation failed!"
    exit 1
fi

echo "✅ Build complete!"
EOF

chmod +x build_app.sh

# ===============================================
# 7. CREATE ONE-CLICK INSTALL SCRIPT
# ===============================================
cat > ../One-Click-Install.command << 'EOF'
#!/bin/bash

echo "⚡ PDF to FlipBook Installer"
echo "================================================"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

APPNAME=$(cat native/.appname 2>/dev/null || echo "PDF-To-FlipBook")
echo "Installing: $APPNAME"
echo ""

echo "🔨 Step 1: Building app..."
cd native || exit 1

if ./build_app.sh; then
    echo ""
    echo "✅ Build successful!"
else
    echo "❌ Build failed"
    exit 1
fi

echo ""
echo "📦 Step 2: Installing to Applications..."
APP_BUNDLE="dist/$APPNAME.app"
USER_APPS="$HOME/Applications"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ App bundle not found at: $APP_BUNDLE"
    exit 1
fi

mkdir -p "$USER_APPS"
if [ -d "$USER_APPS/$APPNAME.app" ]; then
    echo "⚠ Removing existing app..."
    rm -rf "$USER_APPS/$APPNAME.app"
fi

if cp -R "$APP_BUNDLE" "$USER_APPS/"; then
    INSTALL_PATH="$USER_APPS/$APPNAME.app"
    echo "✅ Installed to: $INSTALL_PATH"
else
    echo "❌ Installation failed!"
    exit 1
fi

echo -e "🔍 Verifying app bundle structure..."

if [ -f "$APP_BUNDLE/Contents/MacOS/$APPNAME" ]; then
    echo -e "   ✅ Bundle structure is CORRECT"
else
    echo -e "   ❌ Bundle structure is INCORRECT!"
    exit 1
fi

echo -e "📋 Installing to Applications..."

mkdir -p "$HOME/Applications"
APP_PATH="$HOME/Applications/$APPNAME.app"
rm -rf "$APP_PATH"
cp -R "$APP_BUNDLE" "$APP_PATH"

if [ -d "$APP_PATH" ]; then
    echo -e "   ✅ Installed to: $APP_PATH"
else
    echo -e "   ❌ Failed to install to Applications"
    APP_PATH="$(pwd)/$APP_BUNDLE"
fi

DESKTOP_APP="$HOME/Desktop/$APPNAME.app"
rm -rf "$DESKTOP_APP"
cp -R "$APP_BUNDLE" "$DESKTOP_APP"
echo -e "   ✅ Copied to Desktop: $DESKTOP_APP"

cat > "$HOME/Desktop/Launch $APPNAME.command" << LAUNCHER_EOF
#!/bin/bash
echo "🚀 Launching $APPNAME..."
open "$APP_PATH"
LAUNCHER_EOF
chmod +x "$HOME/Desktop/Launch $APPNAME.command"
echo -e "   ✅ Launcher created"

echo -e "📌 Adding to Dock..."

DOCK_APPS=$(defaults read com.apple.dock persistent-apps 2>/dev/null || echo "[]")
if ! echo "$DOCK_APPS" | grep -q "$APPNAME"; then
    defaults write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$APP_PATH</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
    killall Dock 2>/dev/null &
    echo -e "   ✅ Added to Dock"
else
    echo -e "   ⚠ App already in Dock"
fi

echo ""
echo "🚀 Step 4: Launching $APPNAME..."

sleep 2

if open "$INSTALL_PATH" 2>/dev/null; then
    echo "✅ App launched successfully!"
else
    echo "⚠ Could not launch automatically"
    echo "   Open manually from: $INSTALL_PATH"
    echo "   Or use: Desktop/Launch $APPNAME.command"
fi

echo ""
echo "🎉 INSTALLATION COMPLETE!"
echo "================================================"
echo "📋 HOW TO USE:"
echo "   1. Drag & drop a PDF onto the app window"
echo "   2. Click 'Convert PDF to FlipBook'"
echo "   3. PNG images + HTML saved to Downloads folder"
echo ""
echo "📁 OUTPUT: Downloads/[PDFName]_FlipBook/"
echo "   - [name]_page_1.png, page_2.png, etc."
echo "   - [name]_flipbook.html (open in browser)"
echo "================================================"
echo ""
echo "📌 App installed to: $INSTALL_PATH"
echo "📌 Desktop copy: $HOME/Desktop/$APPNAME.app"
echo "📌 Launcher: $HOME/Desktop/Launch $APPNAME.command"
EOF

chmod +x ../One-Click-Install.command

# ===============================================
# 8. BUILD AND INSTALL AUTOMATICALLY
# ===============================================
echo ""
echo -e "${GREEN}✅ PDF to FlipBook app created!${NC}"
echo ""
echo -e "${CYAN}📁 Project location:${NC} $(pwd)/"
echo -e "${CYAN}🚀 One-click install:${NC} ./One-Click-Install.command"
echo ""

read -p "Would you like to build and install the app now? (Y/n): " BUILD_NOW
BUILD_NOW=${BUILD_NOW:-Y}

if [[ "$BUILD_NOW" == "y" || "$BUILD_NOW" == "Y" || "$BUILD_NOW" == "" ]]; then
    echo -e "${CYAN}🚀 Running installer...${NC}"
    echo ""
    
    chmod +x ../One-Click-Install.command
    ../One-Click-Install.command
    
    echo ""
    echo -e "${GREEN}✅ Setup complete!${NC}"
else
    echo -e "${YELLOW}⏸ You can install later by running: ./One-Click-Install.command${NC}"
fi

echo ""
echo -e "${GREEN}✨ Your PDF to FlipBook app is ready!${NC}"
echo -e "${CYAN}💡 Drag any PDF onto the window and click Convert${NC}"