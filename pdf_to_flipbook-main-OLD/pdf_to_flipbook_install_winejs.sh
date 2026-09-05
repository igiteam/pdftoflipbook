#!/bin/bash
# ============================================
# PDF to FlipBook - WineJS Installer
# Adds PDF to FlipBook Converter to WineJS Platform
# ============================================
# App: PDF to FlipBook
# Category: Tools
# Features: Convert PDF to flipbook HTML, PNG extraction, Turn.js integration
# ============================================

APP_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/pdf_flipbook.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "📥 Installing PDF to FlipBook for WineJS..."

# ============= VERIFY WINEJS PLATFORM =============
log "Verifying WineJS platform..."

if [ ! -d "/opt/winejs" ]; then
    error "WineJS platform not found at /opt/winejs"
fi

if [ ! -f "/opt/winejs/translator/index.js" ]; then
    error "WineJS translator not found. Please install WineJS first."
fi

# Ensure winejs-net network exists
log "Checking winejs-net network..."
if ! docker network inspect winejs-net &>/dev/null; then
    docker network create winejs-net
    log "✅ winejs-net network created"
fi

# ============= GET DOMAIN FROM WINEJS CONFIG =============
if [ -f "/opt/winejs/translator/index.js" ]; then
    DOMAIN_NAME=$(grep "const DOMAIN_NAME" /opt/winejs/translator/index.js | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/")
fi

if [ -z "$DOMAIN_NAME" ]; then
    read -p "Enter your WineJS domain: " DOMAIN_NAME
fi

info "Using domain: $DOMAIN_NAME"

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=7300
MAX_RETRIES=50
APP_PORT=""

declare -a USED_PORTS
if [ -d "/opt/winejs/apps" ]; then
    for config in /opt/winejs/apps/*/config.json; do
        if [ -f "$config" ]; then
            PORT=$(grep -o '"port": [0-9]*' "$config" | awk '{print $2}')
            [ -n "$PORT" ] && USED_PORTS+=($PORT)
        fi
    done
fi

for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port"
fi

log "Using port: $APP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="pdf-flipbook"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/pdf-flipbook"
CONFIG_DIR="/opt/winejs/config/pdf-flipbook"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$CONFIG_DIR" "$ICON_DIR"

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/pdf-flipbook"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  winejs-pdf-flipbook-web:
    image: nginx:alpine
    container_name: winejs-${APP_NAME}-web
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - ${APP_DIR}/web:/usr/share/nginx/html:ro
      - ${DATA_DIR}:/usr/share/nginx/html/uploads:rw
    networks:
      - winejs-net
    depends_on:
      - winejs-pdf-flipbook-api

  winejs-pdf-flipbook-api:
    build: ${APP_DIR}/api
    container_name: winejs-${APP_NAME}-api
    restart: unless-stopped
    environment:
      - DATA_DIR=${DATA_DIR}
      - DOMAIN_NAME=${DOMAIN_NAME}
    volumes:
      - ${DATA_DIR}:/app/data
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= CREATE WEB INTERFACE =============
log "📄 Creating web interface..."

mkdir -p "$APP_DIR/web/css" "$APP_DIR/web/js"

# Create CSS
cat > "$APP_DIR/web/css/style.css" << 'CSS_EOF'
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
    background: linear-gradient(135deg, #1e1e2e 0%, #181825 100%);
    font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    color: #cdd6f4;
    min-height: 100vh;
}
.container { max-width: 1400px; margin: 0 auto; padding: 20px; }
.header {
    background: #11111b;
    border-radius: 12px;
    padding: 24px;
    margin-bottom: 30px;
    border: 1px solid #313244;
}
.header h1 { font-size: 28px; margin-bottom: 8px; display: flex; align-items: center; gap: 12px; }
.header h1 img { width: 40px; height: 40px; }
.header p { color: #6c7086; font-size: 14px; }
.card {
    background: #1e1e2e;
    border-radius: 12px;
    padding: 24px;
    margin-bottom: 24px;
    border: 1px solid #313244;
}
.card h2 {
    font-size: 20px;
    margin-bottom: 20px;
    color: #89b4fa;
    border-left: 3px solid #89b4fa;
    padding-left: 12px;
}
.drop-zone {
    border: 3px dashed #313244;
    border-radius: 16px;
    padding: 60px;
    text-align: center;
    cursor: pointer;
    transition: all 0.3s;
    margin-bottom: 20px;
}
.drop-zone:hover, .drop-zone.drag-over {
    border-color: #89b4fa;
    background: rgba(137, 180, 250, 0.1);
}
.drop-zone .emoji { font-size: 48px; margin-bottom: 16px; }
.drop-zone p { color: #6c7086; margin-top: 8px; font-size: 14px; }
.btn {
    padding: 10px 20px;
    border-radius: 8px;
    font-size: 14px;
    font-weight: 500;
    cursor: pointer;
    border: none;
    display: inline-flex;
    align-items: center;
    gap: 8px;
}
.btn-primary { background: #89b4fa; color: #1e1e2e; }
.btn-primary:hover { background: #b4befe; transform: translateY(-1px); }
.btn-secondary { background: #313244; color: #cdd6f4; }
.btn-secondary:hover { background: #45475a; }
.btn-group { display: flex; gap: 12px; flex-wrap: wrap; margin-top: 16px; }
.output-area {
    background: #11111b;
    border-radius: 8px;
    padding: 16px;
    margin-top: 16px;
    max-height: 400px;
    overflow-y: auto;
    font-family: monospace;
    font-size: 12px;
    border: 1px solid #313244;
}
.log-line { padding: 4px 0; border-bottom: 1px solid #1e1e2e; }
.log-info { color: #89b4fa; }
.log-success { color: #a6e3a1; }
.log-error { color: #f38ba8; }
.progress-container { margin-top: 16px; display: none; }
.progress-bar { width: 100%; height: 4px; background: #313244; border-radius: 2px; overflow: hidden; }
.progress-fill { height: 100%; background: #89b4fa; width: 0%; transition: width 0.3s; }
.result-link {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    background: #11111b;
    padding: 12px 20px;
    border-radius: 8px;
    text-decoration: none;
    color: #a6e3a1;
    margin-top: 16px;
}
.result-link:hover { background: #313244; color: #89b4fa; }
.footer {
    text-align: center;
    padding: 20px;
    color: #6c7086;
    font-size: 12px;
    border-top: 1px solid #313244;
    margin-top: 30px;
}
.footer a { color: #89b4fa; text-decoration: none; }
@media (max-width: 768px) {
    .container { padding: 12px; }
    .drop-zone { padding: 30px; }
}
CSS_EOF

# Create JavaScript
cat > "$APP_DIR/web/js/app.js" << 'JS_EOF'
const API_BASE = '/pdf-flipbook/api';
let currentFile = null;
let isProcessing = false;

function showAlert(msg, type) {
    const alert = document.createElement('div');
    alert.className = `alert alert-${type}`;
    alert.textContent = msg;
    document.body.appendChild(alert);
    setTimeout(() => alert.remove(), 3000);
}

function addLog(msg, type) {
    const output = document.getElementById('output');
    const line = document.createElement('div');
    line.className = `log-line log-${type}`;
    line.textContent = `[${new Date().toLocaleTimeString()}] ${msg}`;
    output.appendChild(line);
    line.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

function clearLogs() {
    document.getElementById('output').innerHTML = '';
    addLog('Logs cleared', 'info');
}

function handleDrop(e) {
    e.preventDefault();
    const dropZone = document.getElementById('dropZone');
    dropZone.classList.remove('drag-over');
    
    const files = e.dataTransfer.files;
    if (files.length > 0) {
        const file = files[0];
        if (file.type === 'application/pdf' || file.name.endsWith('.pdf')) {
            currentFile = file;
            document.getElementById('fileName').textContent = file.name;
            document.getElementById('fileSize').textContent = formatFileSize(file.size);
            document.getElementById('fileInfo').style.display = 'block';
            document.getElementById('convertBtn').disabled = false;
            addLog(`PDF loaded: ${file.name} (${formatFileSize(file.size)})`, 'success');
        } else {
            showAlert('Please drop a PDF file', 'error');
            addLog('Invalid file type. Please drop a PDF.', 'error');
        }
    }
}

function formatFileSize(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024, sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

function handleDragOver(e) {
    e.preventDefault();
    const dropZone = document.getElementById('dropZone');
    dropZone.classList.add('drag-over');
}

function handleDragLeave(e) {
    e.preventDefault();
    const dropZone = document.getElementById('dropZone');
    dropZone.classList.remove('drag-over');
}

async function selectFile() {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'application/pdf,.pdf';
    input.onchange = (e) => {
        if (e.target.files.length > 0) {
            currentFile = e.target.files[0];
            document.getElementById('fileName').textContent = currentFile.name;
            document.getElementById('fileSize').textContent = formatFileSize(currentFile.size);
            document.getElementById('fileInfo').style.display = 'block';
            document.getElementById('convertBtn').disabled = false;
            addLog(`PDF selected: ${currentFile.name}`, 'success');
        }
    };
    input.click();
}

async function convertPDF() {
    if (!currentFile || isProcessing) return;
    
    isProcessing = true;
    document.getElementById('convertBtn').disabled = true;
    document.getElementById('progressContainer').style.display = 'block';
    document.getElementById('progressFill').style.width = '0%';
    
    const formData = new FormData();
    formData.append('pdf', currentFile);
    
    addLog('Starting PDF conversion...', 'info');
    
    try {
        const response = await fetch(`${API_BASE}/convert`, {
            method: 'POST',
            body: formData
        });
        
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        
        while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            
            const text = decoder.decode(value);
            const lines = text.split('\n');
            
            for (const line of lines) {
                if (line.startsWith('data: ')) {
                    const data = JSON.parse(line.slice(6));
                    addLog(data.message, data.type || 'info');
                    
                    if (data.progress) {
                        document.getElementById('progressFill').style.width = `${data.progress}%`;
                    }
                    
                    if (data.complete) {
                        showAlert('Conversion complete!', 'success');
                        if (data.outputUrl) {
                            const resultDiv = document.getElementById('result');
                            resultDiv.innerHTML = `
                                <a href="${data.outputUrl}" class="result-link" target="_blank">
                                    📖 View FlipBook HTML
                                </a>
                                <a href="${data.outputUrl.replace('.html', '.zip')}" class="result-link" target="_blank">
                                    📦 Download All Pages (ZIP)
                                </a>
                            `;
                        }
                    }
                }
            }
        }
    } catch (error) {
        addLog(`ERROR: ${error.message}`, 'error');
        showAlert(`Conversion failed: ${error.message}`, 'error');
    }
    
    isProcessing = false;
    document.getElementById('convertBtn').disabled = false;
    document.getElementById('progressContainer').style.display = 'none';
}

document.addEventListener('DOMContentLoaded', () => {
    const dropZone = document.getElementById('dropZone');
    dropZone.addEventListener('dragover', handleDragOver);
    dropZone.addEventListener('dragleave', handleDragLeave);
    dropZone.addEventListener('drop', handleDrop);
    dropZone.addEventListener('click', selectFile);
});
JS_EOF

# Create main HTML
cat > "$APP_DIR/web/index.html" << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PDF to FlipBook - WineJS</title>
    <link rel="stylesheet" href="/css/style.css">
    <link rel="icon" type="image/png" href="https://cdn.gitgpt.chat/rtx/images/pdf_flipbook.png">
</head>
<body>
    <div class="container">
        <div class="header">
            <h1><img src="https://cdn.gitgpt.chat/rtx/images/pdf_flipbook.png" alt="">PDF to FlipBook</h1>
            <p>Convert PDF documents to interactive HTML flipbooks with Turn.js</p>
        </div>
        
        <div class="card">
            <h2>📄 Upload PDF</h2>
            <div id="dropZone" class="drop-zone">
                <div class="emoji">📖</div>
                <p>Drag & Drop PDF here or click to select</p>
                <p style="font-size: 12px; margin-top: 8px;">Supports any PDF file</p>
            </div>
            <div id="fileInfo" style="display: none; margin-top: 16px; padding: 12px; background: #11111b; border-radius: 8px;">
                <strong>📄 Selected:</strong> <span id="fileName"></span><br>
                <strong>📦 Size:</strong> <span id="fileSize"></span>
            </div>
            <div class="btn-group">
                <button id="convertBtn" class="btn btn-primary" onclick="convertPDF()" disabled>🔄 Convert to FlipBook</button>
                <button class="btn btn-secondary" onclick="clearLogs()">🗑️ Clear Logs</button>
            </div>
            
            <div class="progress-container" id="progressContainer">
                <div class="progress-bar"><div class="progress-fill" id="progressFill"></div></div>
            </div>
            
            <div class="output-area" id="output">
                <div class="log-line log-info">[System] Ready to convert PDF to FlipBook...</div>
            </div>
            
            <div id="result"></div>
        </div>
        
        <div class="footer">
            Powered by WineJS Platform | <a href="https://github.com/NV/pdf-to-flipbook" target="_blank">PDF to FlipBook on GitHub</a>
        </div>
    </div>
    <script src="/js/app.js"></script>
</body>
</html>
HTML_EOF

# ============= CREATE BACKEND API SERVICE =============
log "📝 Creating backend API service..."

mkdir -p "$APP_DIR/api"

cat > "$APP_DIR/api/server.js" << 'API_EOF'
const express = require('express');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const cors = require('cors');
const multer = require('multer');
const archiver = require('archiver');
const { promisify } = require('util');
const execAsync = promisify(exec);

const app = express();
const PORT = 3001;
const DATA_DIR = process.env.DATA_DIR || '/app/data';
const BASE_PATH = '/pdf-flipbook/api';

app.use(cors());
app.use(express.json());

if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
}

const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        const uploadDir = path.join(DATA_DIR, 'uploads');
        if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });
        cb(null, uploadDir);
    },
    filename: (req, file, cb) => {
        const timestamp = Date.now();
        const sanitizedName = file.originalname.replace(/[^a-zA-Z0-9.-]/g, '_');
        cb(null, `${timestamp}_${sanitizedName}`);
    }
});
const upload = multer({ storage, limits: { fileSize: 100 * 1024 * 1024 } });

app.use((req, res, next) => {
    if (!req.path.startsWith('/pdf-flipbook/api') && req.path !== '/health') {
        if (req.path !== '/health') return res.status(404).json({ error: 'Not found' });
    }
    next();
});

app.get('/health', (req, res) => {
    res.json({ status: 'ok' });
});

app.post(`${BASE_PATH}/convert`, upload.single('pdf'), async (req, res) => {
    if (!req.file) {
        return res.status(400).json({ error: 'No PDF file uploaded' });
    }
    
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    
    const pdfPath = req.file.path;
    const pdfName = path.parse(req.file.originalname).name.replace(/[^a-zA-Z0-9]/g, '_');
    const timestamp = Date.now();
    const outputDir = path.join(DATA_DIR, `flipbook_${pdfName}_${timestamp}`);
    const outputZip = path.join(DATA_DIR, `flipbook_${pdfName}_${timestamp}.zip`);
    
    fs.mkdirSync(outputDir, { recursive: true });
    
    res.write(`data: ${JSON.stringify({ message: `Processing: ${req.file.originalname}`, type: 'info', progress: 5 })}\n\n`);
    
    try {
        const pdfInfo = await execAsync(`pdfinfo "${pdfPath}"`);
        const pageCountMatch = pdfInfo.stdout.match(/Pages:\s*(\d+)/);
        const pageCount = pageCountMatch ? parseInt(pageCountMatch[1]) : 0;
        
        if (pageCount === 0) {
            throw new Error('Could not determine page count');
        }
        
        res.write(`data: ${JSON.stringify({ message: `PDF has ${pageCount} pages`, type: 'info', progress: 15 })}\n\n`);
        
        res.write(`data: ${JSON.stringify({ message: 'Converting pages to PNG...', type: 'info', progress: 20 })}\n\n`);
        
        for (let i = 1; i <= pageCount; i++) {
            await execAsync(`pdftoppm -png -f ${i} -singlefile "${pdfPath}" "${path.join(outputDir, `${pdfName}_page_${i}`)}"`);
            
            const progress = 20 + Math.floor((i / pageCount) * 60);
            res.write(`data: ${JSON.stringify({ message: `Converted page ${i}/${pageCount}`, type: 'info', progress })}\n\n`);
        }
        
        res.write(`data: ${JSON.stringify({ message: 'Generating HTML flipbook...', type: 'info', progress: 85 })}\n\n`);
        
        // EXACT HTML GENERATOR FROM YOUR SWIFT CODE - PRESERVED VERBATIM
        const html = `<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>${pdfName} - FlipBook</title>
    <script type="text/javascript" src="https://code.jquery.com/jquery-1.7.1.min.js"></script>
    <script type="text/javascript" src="https://cdn.gitgpt.chat/rtx/magazine_turn.js"></script>
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
            background-size: 100% 100% !important;
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

        /* Loading indicator for pages */
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
    </style>
</head>
<body>
    <div id="magazine"></div>
    <script>
        // Page configuration
        const totalPages = ${pageCount};
        const title = '${pdfName}';
        
        // Store current page to restore after rotation
        let currentPageNumber = 1;
        let turnInstance = null;
        let isRebuilding = false;
        
        // Lazy loading queue - only load images when needed
        let loadedPages = new Set();
        let loadingPages = new Set();
        let preloadQueue = [];
        
        // Create the magazine structure with placeholders
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
        
        // Load a specific page image
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
            const isLandscape = window.matchMedia("(orientation: landscape)").matches;
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
                    const isLandscape = window.matchMedia("(orientation: landscape)").matches;
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
                        }
                    } catch (e) { }
                }
            }, 100);
        });
        
        console.log('Flip book initialized with ' + totalPages + ' pages (aggressive preloading enabled)');
        console.log('Next page is preloaded before you flip for smooth transitions');
    </script>
</body>
</html>`;
        
        const htmlPath = path.join(outputDir, `${pdfName}_flipbook.html`);
        fs.writeFileSync(htmlPath, html);
        
        res.write(`data: ${JSON.stringify({ message: 'Creating ZIP archive...', type: 'info', progress: 95 })}\n\n`);
        
        await new Promise((resolve, reject) => {
            const output = fs.createWriteStream(outputZip);
            const archive = archiver('zip', { zlib: { level: 9 } });
            output.on('close', resolve);
            archive.on('error', reject);
            archive.pipe(output);
            archive.directory(outputDir, false);
            archive.finalize();
        });
        
        fs.unlinkSync(pdfPath);
        
        const outputUrl = `/pdf-flipbook/data/flipbook_${pdfName}_${timestamp}/${pdfName}_flipbook.html`;
        
        res.write(`data: ${JSON.stringify({ 
            message: `✅ Conversion complete! ${pageCount} pages converted`, 
            type: 'success', 
            complete: true, 
            progress: 100,
            outputUrl
        })}\n\n`);
        
    } catch (error) {
        console.error('Conversion error:', error);
        res.write(`data: ${JSON.stringify({ message: `❌ Error: ${error.message}`, type: 'error', complete: true })}\n\n`);
        if (fs.existsSync(pdfPath)) fs.unlinkSync(pdfPath);
        if (fs.existsSync(outputDir)) fs.rmSync(outputDir, { recursive: true, force: true });
    }
    
    res.end();
});

app.listen(PORT, () => {
    console.log(`PDF to FlipBook API running on port ${PORT}`);
});
API_EOF

# Create Dockerfile for API
cat > "$APP_DIR/api/Dockerfile" << 'DOCKERFILE_EOF'
FROM node:18-alpine

RUN apk add --no-cache \
    poppler-utils

WORKDIR /api

COPY package*.json ./
RUN npm install

COPY server.js .

EXPOSE 3001

CMD ["node", "server.js"]
DOCKERFILE_EOF

# Create package.json for API
cat > "$APP_DIR/api/package.json" << 'PACKAGE_EOF'
{
    "name": "pdf-flipbook-api",
    "version": "1.0.0",
    "description": "PDF to FlipBook API for WineJS",
    "main": "server.js",
    "scripts": { "start": "node server.js" },
    "dependencies": {
        "express": "^4.18.2",
        "cors": "^2.8.5",
        "multer": "^1.4.5-lts.1",
        "archiver": "^6.0.0"
    }
}
PACKAGE_EOF

# ============= CREATE CONFIG.JSON =============
log "📝 Creating config.json..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "PDF to FlipBook",
    "version": "1.0.0",
    "description": "Convert PDF documents to interactive HTML flipbooks. Drag and drop any PDF to generate page-by-page PNGs and a beautiful flipbook viewer.",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/pdf-flipbook.png",
    "category": "Tools",
    "features": [
        "📄 Drag & drop PDF conversion",
        "🖼️ Extracts each page as PNG",
        "📖 Generates interactive HTML flipbook",
        "📱 Mobile-responsive viewer",
        "🎴 Double-page mode on landscape",
        "⌨️ Keyboard navigation (arrow keys)",
        "📦 Download all pages as ZIP",
        "⚡ Real-time progress tracking"
    ]
}
CONF_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading app icon..."
curl -L "$APP_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon, using default"

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-pdf-flipbook << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
DATA_DIR="${DATA_DIR}"

case "\$1" in
    status)
        docker ps | grep pdf-flipbook
        ;;
    logs-web)
        docker logs winejs-${APP_NAME}-web --tail 50
        ;;
    logs-api)
        docker logs winejs-${APP_NAME}-api --tail 50
        ;;
    restart)
        docker restart winejs-${APP_NAME}-web
        docker restart winejs-${APP_NAME}-api
        echo "PDF to FlipBook restarted"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/pdf-flipbook/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/pdf-flipbook/"
        fi
        ;;
    output)
        echo "Data directory: \$DATA_DIR"
        ls -la "\$DATA_DIR"
        ;;
    *)
        echo "PDF to FlipBook Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-pdf-flipbook open        - Open web interface"
        echo "  winejs-pdf-flipbook status      - Check server status"
        echo "  winejs-pdf-flipbook logs-web    - View web server logs"
        echo "  winejs-pdf-flipbook logs-api    - View API logs"
        echo "  winejs-pdf-flipbook restart     - Restart all services"
        echo "  winejs-pdf-flipbook output      - Show data directory"
        echo ""
        echo "Web Interface: https://\${DOMAIN_NAME}/pdf-flipbook/"
        echo "Data Directory: \$DATA_DIR"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-pdf-flipbook

# ============= START CONTAINERS =============
log "🚀 Building and starting containers..."

cd "$INSTANCE_DIR"

docker build -t winejs-pdf-flipbook-api:latest "$APP_DIR/api" 2>&1 | tail -20
docker-compose down 2>/dev/null
docker-compose up -d

sleep 10

if docker ps | grep -q "winejs-${APP_NAME}-api"; then
    success "✅ API container started successfully"
else
    warn "⚠️ API container may not have started"
fi

if docker ps | grep -q "winejs-${APP_NAME}-web"; then
    success "✅ Web container started successfully"
else
    warn "⚠️ Web container may not have started"
fi

# ============= UPDATE NGINX =============
log "📝 Setting up nginx..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if ! grep -q "location /pdf-flipbook" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        HTTPS_START=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$HTTPS_START" ]; then
            BRACE_COUNT=0
            LINE_NUM=$HTTPS_START
            TOTAL_LINES=$(wc -l < /etc/nginx/sites-available/winejs)
            HTTPS_END=""
            
            while [ $LINE_NUM -le $TOTAL_LINES ]; do
                LINE=$(sed -n "${LINE_NUM}p" /etc/nginx/sites-available/winejs)
                for ((i=0; i<${#LINE}; i++)); do
                    char="${LINE:$i:1}"
                    if [ "$char" = "{" ]; then
                        BRACE_COUNT=$((BRACE_COUNT + 1))
                    elif [ "$char" = "}" ]; then
                        BRACE_COUNT=$((BRACE_COUNT - 1))
                    fi
                done
                if [ $BRACE_COUNT -eq 0 ]; then
                    HTTPS_END=$LINE_NUM
                    break
                fi
                LINE_NUM=$((LINE_NUM + 1))
            done
            
            if [ -n "$HTTPS_END" ]; then
                sed -i "${HTTPS_END}i\\
    # PDF to FlipBook Web Interface\n\
    location = /pdf-flipbook {\n\
        return 301 /pdf-flipbook/;\n\
    }\n\
    \n\
    location /pdf-flipbook/ {\n\
        proxy_pass http://127.0.0.1:8080/;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection 'upgrade';\n\
        proxy_set_header Host \\\$host;\n\
        proxy_cache_bypass \\\$http_upgrade;\n\
        proxy_buffering off;\n\
        proxy_read_timeout 300s;\n\
    }\n\
    \n\
    location /pdf-flipbook/api/ {\n\
        proxy_pass http://127.0.0.1:3001/pdf-flipbook/api/;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_buffering off;\n\
        proxy_read_timeout 300s;\n\
        client_max_body_size 100M;\n\
    }\n\
    \n\
    location /pdf-flipbook/data/ {\n\
        alias ${DATA_DIR}/;\n\
        autoindex on;\n\
    }\n" /etc/nginx/sites-available/winejs
                
                if nginx -t; then
                    systemctl reload nginx
                    log "✅ Nginx updated with PDF to FlipBook routes"
                else
                    warn "Nginx test failed, restoring backup"
                    cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
                    nginx -t && systemctl reload nginx
                fi
            else
                warn "Could not find HTTPS block closing brace"
            fi
        else
            warn "Could not find HTTPS server block (listen 443)"
        fi
    else
        log "PDF to FlipBook routes already exist"
    fi
fi

# ============= RESTART TRANSLATOR =============
log "🔄 Restarting WineJS translator..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

sleep 3

# ============= CREATE UNINSTALL SCRIPT =============
log "🗑️ Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_pdf-flipbook.sh" << 'UNINSTALL_EOF'
#!/bin/bash
# WineJS PDF to FlipBook Uninstaller

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }

cd /tmp || cd /root || exit 1

log "🧹 Uninstalling PDF to FlipBook..."

for container in winejs-pdf-flipbook-web winejs-pdf-flipbook-api; do
    if docker ps -a 2>/dev/null | grep -q "$container"; then
        docker stop "$container" 2>/dev/null || true
        docker rm "$container" 2>/dev/null || true
    fi
done

APP_DIR="/opt/winejs/apps/pdf-flipbook"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/pdf-flipbook"
DATA_DIR="/opt/winejs/data/pdf-flipbook"
ICON_FILE="/opt/winejs/translator/public/icons/pdf-flipbook.png"

[ -d "$INSTANCE_DIR" ] && rm -rf "$INSTANCE_DIR"
[ -d "$APP_DIR" ] && rm -rf "$APP_DIR"
[ -d "$DATA_DIR" ] && rm -rf "$DATA_DIR"
[ -f "$ICON_FILE" ] && rm -f "$ICON_FILE"
[ -f "/usr/local/bin/winejs-pdf-flipbook" ] && rm -f "/usr/local/bin/winejs-pdf-flipbook"

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    if grep -q "pdf-flipbook" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup.pdf-flipbook
        sed -i '/# PDF to FlipBook Web Interface/,/location \/pdf-flipbook\/ {/d' /etc/nginx/sites-available/winejs
        sed -i '/location = \/pdf-flipbook {/,/}/d' /etc/nginx/sites-available/winejs
        sed -i '/location \/pdf-flipbook\/api\/ {/,/}/d' /etc/nginx/sites-available/winejs
        sed -i '/pdf-flipbook/d' /etc/nginx/sites-available/winejs
        nginx -t && systemctl reload nginx
    fi
fi

pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

echo -e "${GREEN}✅ PDF to FlipBook uninstalled${NC}"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_pdf-flipbook.sh"
log "✅ Uninstall script created"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              PDF TO FLIPBOOK INSTALLED ON WINEJS!              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ PDF to FlipBook installed!"
echo ""
info "🌐 Web Interface:"
info "   • https://$DOMAIN_NAME/pdf-flipbook/"
echo ""
info "📁 Data Directory:"
info "   • $DATA_DIR"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-pdf-flipbook open        # Open web interface"
info "   • winejs-pdf-flipbook status      # Check server status"
info "   • winejs-pdf-flipbook output      # Show data directory"
echo ""
info "📖 How to use:"
info "   • Drag & drop a PDF onto the drop zone"
info "   • Click 'Convert to FlipBook'"
info "   • Download the generated HTML and PNGs"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_pdf-flipbook.sh"
echo ""
success "✨ Ready! Visit https://$DOMAIN_NAME/pdf-flipbook/"
echo ""