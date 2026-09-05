#!/bin/bash

# PDF to FlipBook API - Standalone Service v2.0 (WineJS Architecture)
# API server: JSON only on port 3000
# Web UI: Static HTML served by nginx
# Usage: curl -sL https://cdn.gitgpt.chat/rtx/sh/flipbook.sh | sudo bash

# Force non-interactive mode for all apt commands
export DEBIAN_FRONTEND=noninteractive

# Pre-seed openssl answers to avoid prompts
echo "openssl openssl/restart-services boolean true" | debconf-set-selections

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to get user input with default
get_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    read -p "$prompt [$default]: " input
    eval "$var_name=\${input:-\$default}"
}

# Enhanced email validation with MX record check
validate_email() {
    local email="$1"
    
    # Basic format validation
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        warn "Invalid email format: $email"
        return 1
    fi
    
    # Extract domain
    local domain="${email#*@}"
    
    # Check if domain is resolvable (has A record)
    if ! host -t A "$domain" >/dev/null 2>&1; then
        warn "Email domain $domain does not resolve to any IP address"
        return 1
    fi
    
    # Check MX records with timeout
    local mx_records
    mx_records=$(dig +short +timeout=5 +tries=2 MX "$domain" 2>/dev/null | grep -c .)
    
    if [ "$mx_records" -eq 0 ]; then
        info "Email domain $domain has no MX records, but A record exists (may still work)"
        return 0
    fi
    
    success "✓ Email validated (MX records found)"
    return 0
}

# Enhanced domain validation with DNS check
validate_domain() {
    local domain="$1"
    
    domain="${domain%.}"
    
    if [ -z "$domain" ]; then
        warn "Domain cannot be empty"
        return 1
    fi
    
    if [ ${#domain} -gt 253 ]; then
        warn "Domain is too long (max 253 characters)"
        return 1
    fi
    
    if [[ "$domain" =~ [^a-zA-Z0-9.-] ]]; then
        warn "Domain contains invalid characters"
        return 1
    fi
    
    if [[ "$domain" == .* ]] || [[ "$domain" == *. ]]; then
        warn "Domain cannot start or end with a dot"
        return 1
    fi
    
    if [[ "$domain" == *..* ]]; then
        warn "Domain cannot contain consecutive dots"
        return 1
    fi
    
    if [[ ! "$domain" =~ \. ]]; then
        warn "Domain must contain at least one dot"
        return 1
    fi
    
    IFS='.' read -ra parts <<< "$domain"
    
    local tld="${parts[-1]}"
    if [ ${#tld} -lt 2 ]; then
        warn "TLD must be at least 2 characters"
        return 1
    fi
    
    for part in "${parts[@]}"; do
        if [ ${#part} -gt 63 ]; then
            warn "Domain part '$part' is too long"
            return 1
        fi
        
        if [[ "$part" == -* ]] || [[ "$part" == *- ]]; then
            warn "Domain part '$part' cannot start or end with a hyphen"
            return 1
        fi
        
        if [[ ! "$part" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
            warn "Domain part '$part' contains invalid characters"
            return 1
        fi
    done
    
    if [[ "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        warn "That looks like an IP address, not a domain name"
        return 1
    fi
    
    return 0
}

# Enhanced DNS checker
check_dns() {
    local domain="$1"
    local expected_ip="$2"
    local max_attempts=5
    local attempt=1
    
    info "Checking if $domain resolves to $expected_ip..."
    info "Note: DNS changes can take up to 48 hours to propagate worldwide"
    echo ""
    
    while [ $attempt -le $max_attempts ]; do
        info "Attempt $attempt of $max_attempts..."
        
        local resolved_ip=""
        
        resolved_ip=$(dig +short @8.8.8.8 "$domain" 2>/dev/null | head -1)
        
        if [ -z "$resolved_ip" ]; then
            resolved_ip=$(dig +short @1.1.1.1 "$domain" 2>/dev/null | head -1)
        fi
        
        if [ -z "$resolved_ip" ]; then
            resolved_ip=$(dig +short "$domain" 2>/dev/null | head -1)
        fi
        
        if [ -z "$resolved_ip" ]; then
            resolved_ip=$(host -t A "$domain" 2>/dev/null | grep "has address" | head -1 | awk '{print $NF}')
        fi
        
        local cname_record=""
        cname_record=$(dig +short @8.8.8.8 CNAME "$domain" 2>/dev/null | head -1)
        
        if [ -n "$cname_record" ]; then
            info "⚠ $domain is a CNAME to: $cname_record"
            local cname_ip=$(dig +short @8.8.8.8 "$cname_record" 2>/dev/null | head -1)
            if [ -n "$cname_ip" ]; then
                info "CNAME resolves to IP: $cname_ip"
                resolved_ip="$cname_ip"
            fi
        fi
        
        if [ -n "$resolved_ip" ]; then
            info "✅ $domain resolves to: $resolved_ip"
            
            if [ "$resolved_ip" = "$expected_ip" ]; then
                success "✓ DNS is correctly configured! ✓"
                echo ""
                return 0
            else
                error "❌ Domain points to $resolved_ip, but your droplet IP is $expected_ip"
                echo ""
                error "DNS MISMATCH - CANNOT CONTINUE"
                error "══════════════════════════════════════════════════"
                error ""
                error "Your domain $domain resolves to: $resolved_ip"
                error "Your droplet IP is: $expected_ip"
                error ""
                error "These MUST match for SSL certificates to work!"
                error ""
                error "To fix this:"
                error "  1. Log in to your domain registrar"
                error "  2. Create/update the A record for $domain"
                error "  3. Set it to point to: $expected_ip"
                error "  4. Wait 5-10 minutes for DNS to propagate"
                error "  5. Run this installer again"
                error ""
                error "After updating DNS, verify with:"
                error "  dig +short $domain"
                error "══════════════════════════════════════════════════"
                exit 1
            fi
        else
            if [ $attempt -lt $max_attempts ]; then
                warn "⚠ Could not resolve $domain (attempt $attempt/$max_attempts)"
                info "Retrying in 10 seconds..."
                sleep 10
            else
                error "❌ FAILED TO RESOLVE DOMAIN AFTER $max_attempts ATTEMPTS"
                echo ""
                error "DNS RESOLUTION FAILED - CANNOT CONTINUE"
                error "══════════════════════════════════════════════════"
                error ""
                error "Your domain $domain could not be resolved!"
                error ""
                error "This usually means:"
                error "  • No A record exists for $domain"
                error "  • The domain hasn't been registered yet"
                error "  • DNS servers are not responding"
                error "  • Domain name is misspelled"
                error ""
                error "To fix this:"
                error "  1. Verify the domain is registered and active"
                error "  2. Create an A record for $domain"
                error "  3. Point it to: $expected_ip"
                error "  4. Wait for DNS propagation (5-30 minutes)"
                error "  5. Run this installer again"
                error ""
                error "After configuring DNS, verify with:"
                error "  dig +short $domain"
                error "══════════════════════════════════════════════════"
                exit 1
            fi
        fi
        
        attempt=$((attempt + 1))
    done
}

# Check if port is available
check_port_availability() {
    local port=$1
    if ss -tulpn 2>/dev/null | grep -q ":$port "; then
        return 1
    fi
    return 0
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    for cmd in dig host curl ss; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing_deps+=($cmd)
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        info "Installing missing dependencies: ${missing_deps[*]}"
        apt-get update -qq
        apt-get install -y -qq dnsutils curl iproute2 >/dev/null 2>&1
    fi
}

# Display banner
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║         PDF TO FLIPBOOK API - Standalone Service v2.0    ║"
echo "║         PURE JSON API + Static Web UI (WineJS style)     ║"
echo "║   Web UI: https://flip.gitgpt.chat/ - Drag & drop PDF    ║"
echo "║   API:    https://flip.gitgpt.chat/api/convert?url=...   ║"
echo "║   Optional auth: &token=your_secret_key                  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    warn "Not running as root. Some commands may need sudo."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check and install dependencies
check_dependencies

# Get user configuration
echo ""
info "Please provide configuration details:"
echo "-------------------------------------"

# Domain input
while true; do
    get_input "Enter your domain (e.g., flip.gitgpt.chat)" "flip.gitgpt.chat" DOMAIN_NAME
    
    if validate_domain "$DOMAIN_NAME"; then
        break
    else
        warn "Invalid domain format. Please enter a full domain (e.g., flip.gitgpt.chat)"
    fi
done

info "Using domain: $DOMAIN_NAME"
echo ""

# Get droplet IP
DROPLET_IP=$(curl -s --fail ifconfig.me 2>/dev/null || curl -s --fail http://checkip.amazonaws.com 2>/dev/null || echo "UNKNOWN")

if [ "$DROPLET_IP" = "UNKNOWN" ]; then
    error "Failed to detect droplet IP. Please check your internet connection."
fi

info "Detected droplet IP: $DROPLET_IP"

# Run DNS check
echo ""
info "═══════════════════════════════════════════════════════════════"
info "                    DNS VALIDATION"
info "═══════════════════════════════════════════════════════════════"
echo ""
check_dns "$DOMAIN_NAME" "$DROPLET_IP"

# Email input
while true; do
    get_input "Enter email for SSL certificate (Let's Encrypt)" "admin@$DOMAIN_NAME" SSL_EMAIL
    if validate_email "$SSL_EMAIL"; then
        success "✓ Email validated successfully"
        break
    else
        warn "Invalid email format or domain. Please enter a valid email address."
    fi
done

# Optional API token
echo ""
info "Optional: Set an API token for authentication"
info "If set, users must include &token=YOUR_TOKEN in requests"
info "Leave empty for public access (no token required)"
read -p "API Token (optional): " API_TOKEN

echo ""
log "Starting PDF to FlipBook API Setup v2.0 (WineJS Architecture)..."
log "Domain: $DOMAIN_NAME"
log "Email: $SSL_EMAIL"
log "Droplet IP: $DROPLET_IP"
if [ -n "$API_TOKEN" ]; then
    log "API Token: [SET] - authentication required"
else
    log "API Token: [NOT SET] - public access"
fi

# Check port availability
if ! check_port_availability 80; then
    warn "Port 80 is already in use. This may affect SSL certificate creation."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

if ! check_port_availability 443; then
    warn "Port 443 is already in use. This may affect HTTPS setup."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

log "All validations passed! Proceeding with installation..."

# Update system
log "Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq

# Install required tools
log "Installing required tools..."
apt-get install -y -qq curl wget git poppler-utils

# Install Redis for queue management
log "Installing Redis for job queue..."
apt-get install -y -qq redis-server
systemctl start redis-server
systemctl enable redis-server

# Configure Redis for better performance
log "Configuring Redis for optimal performance..."
cat >> /etc/redis/redis.conf << 'EOF'
maxmemory 256mb
maxmemory-policy allkeys-lru
save ""
appendonly no
EOF

systemctl restart redis-server
log "✅ Redis installed and configured"

# Install Node.js 18
log "Installing Node.js 18..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y -qq nodejs

# Install PM2
log "Installing PM2..."
npm install -g pm2

# Create swap file
log "Setting up swap space..."
if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log "Swap file created (2GB)"
else
    log "Swap file already exists"
fi

# ============= CREATE FLIPBOOK API SERVICE (PURE JSON API) =============
FLIPBOOK_DIR="/opt/flipbook-api"
log "Creating flipbook directory at $FLIPBOOK_DIR..."
mkdir -p $FLIPBOOK_DIR
cd $FLIPBOOK_DIR

# Create temp and output directories
mkdir -p /tmp/flipbook-temp
mkdir -p /var/www/flipbook/output
mkdir -p /var/www/flipbook/web
chmod 777 /tmp/flipbook-temp
chmod 777 /var/www/flipbook/output
chmod 755 /var/www/flipbook/web

# Install dependencies
log "Installing Node.js dependencies..."
npm init -y
npm install express bull ioredis archiver@5.3.2 pdfinfo multer

# Create main server with queue, token auth, AND file upload
# IMPORTANT: This is a PURE JSON API server - NO static file serving!
log "Creating flipbook API server (JSON only, no HTML serving)..."

# Fix the server.js file - update the upload endpoint
cat > $FLIPBOOK_DIR/server.js << 'EOF'
const express = require('express');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const Queue = require('bull');
const Redis = require('ioredis');
const archiver = require('archiver');
const multer = require('multer');
const util = require('util');
const execPromise = util.promisify(exec);

const app = express();
const PORT = process.env.PORT || 3000;
const TEMP_DIR = '/tmp/flipbook-temp';
const OUTPUT_DIR = '/var/www/flipbook/output';
const API_TOKEN = process.env.API_TOKEN || '';  // Empty = no auth

// IMPORTANT: No static file serving! That's handled by nginx
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Ensure directories exist
[TEMP_DIR, OUTPUT_DIR].forEach(dir => {
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

// Redis connection
const redis = new Redis({
    host: '127.0.0.1',
    port: 6379,
    maxRetriesPerRequest: null,
    retryStrategy: (times) => {
        if (times > 3) return null;
        return Math.min(times * 100, 3000);
    }
});

redis.on('connect', () => console.log('[Redis] Connected'));
redis.on('error', (err) => console.error('[Redis] Error:', err.message));

// Token validation middleware
const validateToken = (req, res, next) => {
    if (!API_TOKEN || API_TOKEN === '') {
        return next();
    }
    
    const token = req.query.token || req.headers['x-api-token'];
    
    if (!token || token !== API_TOKEN) {
        return res.status(401).json({
            error: 'Unauthorized',
            message: 'Valid API token required. Use &token=YOUR_TOKEN or X-API-Token header'
        });
    }
    
    next();
};

// Configure multer for file uploads
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        const uploadDir = path.join(TEMP_DIR, 'uploads');
        if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });
        cb(null, uploadDir);
    },
    filename: (req, file, cb) => {
        const timestamp = Date.now();
        const sanitizedName = file.originalname.replace(/[^a-zA-Z0-9.-]/g, '_');
        cb(null, `${timestamp}_${sanitizedName}`);
    }
});

const upload = multer({ 
    storage: storage, 
    limits: { fileSize: 1024 * 1024 * 1024 },
    fileFilter: (req, file, cb) => {
        if (file.mimetype === 'application/pdf') {
            cb(null, true);
        } else {
            cb(new Error('Only PDF files are allowed'), false);
        }
    }
});

// Store history of converted flipbooks
const HISTORY_FILE = path.join(OUTPUT_DIR, 'history.json');
let conversionHistory = [];

function loadHistory() {
    if (fs.existsSync(HISTORY_FILE)) {
        try {
            conversionHistory = JSON.parse(fs.readFileSync(HISTORY_FILE, 'utf8'));
        } catch(e) { conversionHistory = []; }
    }
}

function saveHistory() {
    fs.writeFileSync(HISTORY_FILE, JSON.stringify(conversionHistory.slice(0, 50), null, 2));
}

loadHistory();

// PDF processing queue (3 concurrent jobs)
const pdfQueue = new Queue('pdf processing', {
    redis: { host: '127.0.0.1', port: 6379 },
    defaultJobOptions: {
        attempts: 2,
        backoff: { type: 'exponential', delay: 5000 },
        timeout: 300000,
        removeOnComplete: true,
        removeOnFail: false
    }
});

// Process PDF jobs
pdfQueue.process(3, async (job) => {
    const { pdfUrl, pdfPath: uploadedPdfPath, cacheKey, originalName, source } = job.data;
    
    console.log(`[Queue] Processing PDF: ${source === 'upload' ? originalName : pdfUrl} (Job ${job.id})`);
    
    const jobId = job.id;
    const timestamp = Date.now();
    const tempDir = path.join(TEMP_DIR, `job_${jobId}_${timestamp}`);
    const outputDir = path.join(OUTPUT_DIR, `flipbook_${cacheKey}`);
    
    fs.mkdirSync(tempDir, { recursive: true });
    if (!fs.existsSync(outputDir)) fs.mkdirSync(outputDir, { recursive: true });
    
    try {
        let pdfPath;
        
        if (source === 'upload' && uploadedPdfPath && fs.existsSync(uploadedPdfPath)) {
            pdfPath = uploadedPdfPath;
            console.log(`[Job ${jobId}] Using uploaded file: ${path.basename(pdfPath)}`);
        } else {
            // Download PDF from URL
            console.log(`[Job ${jobId}] Downloading PDF from URL...`);
            pdfPath = path.join(tempDir, 'input.pdf');
            
            await new Promise((resolve, reject) => {
                const https = require('https');
                const http = require('http');
                const protocol = pdfUrl.startsWith('https') ? https : http;
                
                const file = fs.createWriteStream(pdfPath);
                protocol.get(pdfUrl, (response) => {
                    if (response.statusCode !== 200) {
                        reject(new Error(`HTTP ${response.statusCode}`));
                        return;
                    }
                    response.pipe(file);
                    file.on('finish', () => {
                        file.close();
                        resolve();
                    });
                }).on('error', reject);
            });
        }
        
        // Get page count
        console.log(`[Job ${jobId}] Getting page count...`);
        const { stdout: pdfInfo } = await execPromise(`pdfinfo "${pdfPath}"`);
        const pageCountMatch = pdfInfo.match(/Pages:\s*(\d+)/);
        const pageCount = pageCountMatch ? parseInt(pageCountMatch[1]) : 0;
        
        if (pageCount === 0) throw new Error('Could not determine page count');
        console.log(`[Job ${jobId}] PDF has ${pageCount} pages`);
        
        // Get PDF name
        let pdfName;
        if (originalName) {
            pdfName = path.parse(originalName).name.replace(/[^a-zA-Z0-9]/g, '_');
        } else if (pdfUrl) {
            pdfName = path.parse(pdfUrl).name.replace(/[^a-zA-Z0-9]/g, '_');
        } else {
            pdfName = `document_${timestamp}`;
        }
        
        // Convert pages to PNG
        console.log(`[Job ${jobId}] Converting pages to PNG...`);
        
        for (let i = 1; i <= pageCount; i++) {
            await execPromise(`pdftoppm -png -f ${i} -singlefile "${pdfPath}" "${path.join(outputDir, `${pdfName}_page_${i}`)}"`);
            console.log(`[Job ${jobId}] Converted page ${i}/${pageCount}`);
        }
        
        // Generate HTML flipbook
        console.log(`[Job ${jobId}] Generating HTML flipbook...`);
        const html = generateFlipbookHTML(pdfName, pageCount);
        const htmlPath = path.join(outputDir, `${pdfName}_flipbook.html`);
        fs.writeFileSync(htmlPath, html);
        
        // Create ZIP archive
        console.log(`[Job ${jobId}] Creating ZIP archive...`);
        const zipPath = path.join(OUTPUT_DIR, `flipbook_${cacheKey}.zip`);
        await createZip(outputDir, zipPath);
        
        // Add to history
        const historyEntry = {
            id: cacheKey,
            title: pdfName,
            page_count: pageCount,
            created_at: new Date().toISOString(),
            html_url: `/output/flipbook_${cacheKey}/${pdfName}_flipbook.html`,
            zip_url: `/output/flipbook_${cacheKey}.zip`,
            source: source || (pdfUrl ? 'url' : 'unknown'),
            original_name: originalName || pdfName
        };
        conversionHistory.unshift(historyEntry);
        saveHistory();
        
        // Clean up temp files (but keep uploaded file for this job)
        if (source !== 'upload') {
            fs.rmSync(tempDir, { recursive: true, force: true });
        } else {
            // For uploads, delete just the temp dir but keep the uploaded file already processed
            if (fs.existsSync(tempDir)) fs.rmSync(tempDir, { recursive: true, force: true });
            // Delete the uploaded file from uploads temp
            if (uploadedPdfPath && fs.existsSync(uploadedPdfPath)) {
                fs.unlinkSync(uploadedPdfPath);
            }
        }
        
        console.log(`[Job ${jobId}] Completed successfully`);
        
        return {
            success: true,
            title: pdfName,
            page_count: pageCount,
            html_url: `/output/flipbook_${cacheKey}/${pdfName}_flipbook.html`,
            zip_url: `/output/flipbook_${cacheKey}.zip`,
            processing_time_ms: Date.now() - timestamp
        };
        
    } catch (error) {
        console.error(`[Job ${jobId}] Error: ${error.message}`);
        if (fs.existsSync(tempDir)) fs.rmSync(tempDir, { recursive: true, force: true });
        throw error;
    }
});

// Helper: create ZIP
function createZip(sourceDir, outputPath) {
    return new Promise((resolve, reject) => {
        const output = fs.createWriteStream(outputPath);
        const archive = archiver('zip', { zlib: { level: 9 } });
        
        output.on('close', resolve);
        archive.on('error', reject);
        
        archive.pipe(output);
        archive.directory(sourceDir, false);
        archive.finalize();
    });
}

function generateFlipbookHTML(title, pageCount) {
    const safeTitle = title.replace(/'/g, "\\'");
    
    return '<!DOCTYPE html>\n\
<html>\n\
<head>\n\
    <meta charset="UTF-8">\n\
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">\n\
    <title>' + title + ' - FlipBook</title>\n\
    <script type="text/javascript" src="https://code.jquery.com/jquery-1.7.1.min.js"></script>\n\
    <script type="text/javascript" src="https://cdn.gitgpt.chat/rtx/magazine_turn.js"></script>\n\
    <style>\n\
        * {\n\
            margin: 0;\n\
            padding: 0;\n\
            box-sizing: border-box;\n\
        }\n\
        \n\
        body {\n\
            background: #2c3e50;\n\
            display: flex;\n\
            justify-content: center;\n\
            align-items: center;\n\
            min-height: 100vh;\n\
            font-family: "Segoe UI", Arial, sans-serif;\n\
            padding: 0px;\n\
            overflow: hidden;\n\
            position: fixed;\n\
            top: 0;\n\
            left: 0;\n\
            right: 0;\n\
            bottom: 0;\n\
            -webkit-overflow-scrolling: touch;\n\
            overscroll-behavior: none;\n\
        }\n\
        \n\
        #magazine {\n\
            width: 100vw;\n\
            height: 100vh;\n\
            background: #fff;\n\
            overscroll-behavior: none;\n\
        }\n\
        \n\
        #magazine .turn-page {\n\
            background-size: 100.5% 100.5% !important;\n\
            background-position: center;\n\
            background-repeat: no-repeat;\n\
            background-color: #cbcbcb63;\n\
        }\n\
        \n\
        html {\n\
            overflow: hidden;\n\
            position: fixed;\n\
            width: 100%;\n\
            height: 100%;\n\
            overscroll-behavior: none;\n\
            touch-action: pan-y pinch-zoom;\n\
        }\n\
        \n\
        .turn-page.loading {\n\
            position: relative;\n\
        }\n\
        \n\
        .turn-page.loading::after {\n\
            content: "📰";\n\
            position: absolute;\n\
            top: 50%;\n\
            left: 50%;\n\
            transform: translate(-50%, -50%);\n\
            font-size: 40px;\n\
            animation: spin 1s linear infinite;\n\
        }\n\
        \n\
        @keyframes spin {\n\
            from {\n\
                transform: translate(-50%, -50%) rotate(0deg);\n\
            }\n\
            to {\n\
                transform: translate(-50%, -50%) rotate(360deg);\n\
            }\n\
        }\n\
        \n\
        @media (hover: none) and (pointer: coarse) {\n\
            html, body {\n\
                margin: 0 !important;\n\
                padding: 0 !important;\n\
                top: 0 !important;\n\
                left: 0 !important;\n\
                position: fixed !important;\n\
            }\n\
            body {\n\
                display: block !important;\n\
                align-items: flex-start !important;\n\
                justify-content: flex-start !important;\n\
            }\n\
            #magazine {\n\
                top: 0 !important;\n\
                left: 0 !important;\n\
                position: absolute !important;\n\
                margin: 0 !important;\n\
            }\n\
            #pageScrollOverlay {\n\
                top: 0 !important;\n\
                bottom: 0 !important;\n\
                transform: translateX(-50%) !important;\n\
            }\n\
        }\n\
    </style>\n\
</head>\n\
<body>\n\
    <div id="magazine"></div>\n\
    <script>\n\
        const totalPages = ' + pageCount + ';\n\
        const title = "' + safeTitle + '";\n\
        \n\
        let currentPageNumber = 1;\n\
        let turnInstance = null;\n\
        let isRebuilding = false;\n\
        let loadedPages = new Set();\n\
        let loadingPages = new Set();\n\
        let preloadQueue = [];\n\
        \n\
        function getSavedPage() {\n\
            const storageKey = "flipbook_last_page_" + title;\n\
            const saved = localStorage.getItem(storageKey);\n\
            if (saved && !isNaN(saved) && saved >= 1 && saved <= totalPages) {\n\
                return parseInt(saved);\n\
            }\n\
            return 1;\n\
        }\n\
\n\
        function savePage(pageNum) {\n\
            const storageKey = "flipbook_last_page_" + title;\n\
            localStorage.setItem(storageKey, pageNum);\n\
        }\n\
        \n\
        function createMagazine() {\n\
            const magazine = $("#magazine");\n\
            magazine.empty();\n\
            for (let i = 1; i <= totalPages; i++) {\n\
                const pageDiv = $("<div>")\n\
                    .addClass("turn-page loading")\n\
                    .attr("data-page", i)\n\
                    .attr("data-loaded", "false");\n\
                magazine.append(pageDiv);\n\
            }\n\
        }\n\
        \n\
        function loadPageImage(pageNum, priority = false) {\n\
            return new Promise((resolve) => {\n\
                if (loadedPages.has(pageNum) || loadingPages.has(pageNum)) {\n\
                    resolve();\n\
                    return;\n\
                }\n\
                const pageDiv = $(".turn-page[data-page=" + pageNum + "]");\n\
                if (!pageDiv.length) {\n\
                    resolve();\n\
                    return;\n\
                }\n\
                if (pageDiv.attr("data-loaded") === "true") {\n\
                    loadedPages.add(pageNum);\n\
                    resolve();\n\
                    return;\n\
                }\n\
                loadingPages.add(pageNum);\n\
                const img = new Image();\n\
                const imgPath = title + "_page_" + pageNum + ".png";\n\
                img.onload = function () {\n\
                    pageDiv.css("background-image", "url(" + imgPath + ")");\n\
                    pageDiv.removeClass("loading");\n\
                    pageDiv.attr("data-loaded", "true");\n\
                    loadedPages.add(pageNum);\n\
                    loadingPages.delete(pageNum);\n\
                    if (priority) console.log("[Priority] Page " + pageNum + " loaded");\n\
                    resolve();\n\
                };\n\
                img.onerror = function () {\n\
                    pageDiv.css("background-image", "url(data:image/svg+xml,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%22100%25%22%20height%3D%22100%25%22%3E%3Crect%20width%3D%22100%25%22%20height%3D%22100%25%22%20fill%3D%22%23333%22%2F%3E%3Ctext%20x%3D%2250%25%22%20y%3D%2250%25%22%20text-anchor%3D%22middle%22%20fill%3D%22%23666%22%20font-size%3D%2220%22%3EPage%20") + pageNum + "%3C%2Ftext%3E%3C%2Fsvg%3E)");\n\
                    pageDiv.removeClass("loading");\n\
                    pageDiv.attr("data-loaded", "error");\n\
                    loadingPages.delete(pageNum);\n\
                    console.warn("Failed to load page " + pageNum + ": " + imgPath);\n\
                    resolve();\n\
                };\n\
                img.src = imgPath;\n\
            });\n\
        }\n\
        \n\
        function preloadNearbyPages(currentPage, displayMode) {\n\
            let pagesToPreload = [];\n\
            if (displayMode === "single") {\n\
                pagesToPreload = [currentPage + 1, currentPage + 2, currentPage + 3, currentPage + 4, currentPage + 5, currentPage - 1, currentPage - 2];\n\
            } else {\n\
                pagesToPreload = [currentPage + 1, currentPage + 2, currentPage + 3, currentPage + 4, currentPage - 1, currentPage - 2];\n\
            }\n\
            const pagesToLoad = pagesToPreload.filter(pageNum => {\n\
                return pageNum >= 1 && pageNum <= totalPages && !loadedPages.has(pageNum) && !loadingPages.has(pageNum);\n\
            });\n\
            if (pagesToLoad.length > 0) {\n\
                if (displayMode === "single" && currentPage + 1 <= totalPages && !loadedPages.has(currentPage + 1)) {\n\
                    loadPageImage(currentPage + 1, true);\n\
                }\n\
                pagesToLoad.forEach((pageNum, index) => {\n\
                    if (pageNum !== currentPage + 1) {\n\
                        setTimeout(() => {\n\
                            if (!loadedPages.has(pageNum) && !loadingPages.has(pageNum)) loadPageImage(pageNum);\n\
                        }, index * 150);\n\
                    }\n\
                });\n\
            }\n\
        }\n\
        \n\
        function initFlipBook() {\n\
            if (isRebuilding) return;\n\
            isRebuilding = true;\n\
            const isLandscape = window.matchMedia("(orientation: landscape)").matches;\n\
            const displayMode = isLandscape ? "double" : "single";\n\
            let pageToRestore = currentPageNumber;\n\
            if (pageToRestore < 1) pageToRestore = 1;\n\
            if (pageToRestore > totalPages) pageToRestore = totalPages;\n\
            if (turnInstance) {\n\
                try { $("#magazine").turn("destroy"); } catch (e) { console.log("Destroy error:", e); }\n\
            }\n\
            setTimeout(() => {\n\
                $("#magazine").turn({\n\
                    display: displayMode,\n\
                    acceleration: true,\n\
                    gradients: !$.isTouch,\n\
                    elevation: 50,\n\
                    duration: 400,\n\
                    page: pageToRestore,\n\
                    when: {\n\
                        turning: function (e, page) {\n\
                            if (page >= 1 && page <= totalPages && !loadedPages.has(page)) loadPageImage(page, true);\n\
                        },\n\
                        turned: function (e, page) {\n\
                            currentPageNumber = page;\n\
                            savePage(page);\n\
                            const currentDisplayMode = $(this).turn("display");\n\
                            const visiblePages = $(this).turn("view");\n\
                            visiblePages.forEach(pageNum => { if (pageNum > 0 && pageNum <= totalPages) loadPageImage(pageNum); });\n\
                            preloadNearbyPages(page, currentDisplayMode);\n\
                        },\n\
                        first: function () {\n\
                            const firstPages = $(this).turn("view");\n\
                            firstPages.forEach(pageNum => { if (pageNum > 0 && pageNum <= totalPages) loadPageImage(pageNum); });\n\
                            const currentDisplayMode = $(this).turn("display");\n\
                            preloadNearbyPages(pageToRestore, currentDisplayMode);\n\
                        },\n\
                        missing: function (e, pages) {\n\
                            for (let i = 0; i < pages.length; i++) {\n\
                                if (pages[i] >= 1 && pages[i] <= totalPages) loadPageImage(pages[i], true);\n\
                            }\n\
                        }\n\
                    }\n\
                });\n\
                turnInstance = $("#magazine");\n\
                isRebuilding = false;\n\
                console.log("Flip book initialized: " + displayMode + " mode, page " + pageToRestore);\n\
            }, 50);\n\
        }\n\
        \n\
        createMagazine();\n\
        \n\
        async function initialPreload() {\n\
            for (let i = 1; i <= 6; i++) {\n\
                if (i <= totalPages) await loadPageImage(i, true);\n\
            }\n\
            console.log("Initial preload complete");\n\
        }\n\
        \n\
        currentPageNumber = getSavedPage();\n\
        initialPreload();\n\
        $(window).ready(function () { initFlipBook(); });\n\
        \n\
        $(window).on("orientationchange", function () {\n\
            if (turnInstance) {\n\
                try {\n\
                    const currentView = turnInstance.turn("view");\n\
                    if (currentView && currentView.length) currentPageNumber = currentView[0] || currentPageNumber;\n\
                } catch (e) { }\n\
            }\n\
            setTimeout(() => {\n\
                createMagazine();\n\
                loadedPages.clear();\n\
                loadingPages.clear();\n\
                preloadQueue = [];\n\
                initFlipBook();\n\
                initialPreload();\n\
            }, 100);\n\
        });\n\
        \n\
        let resizeTimer;\n\
        $(window).on("resize", function () {\n\
            clearTimeout(resizeTimer);\n\
            resizeTimer = setTimeout(() => {\n\
                if (turnInstance) {\n\
                    try {\n\
                        const currentView = turnInstance.turn("view");\n\
                        if (currentView && currentView.length) currentPageNumber = currentView[0] || currentPageNumber;\n\
                    } catch (e) { }\n\
                    const isLandscape = window.matchMedia("(orientation: landscape)").matches;\n\
                    const displayMode = isLandscape ? "double" : "single";\n\
                    if (turnInstance.turn("display") !== displayMode) {\n\
                        setTimeout(() => {\n\
                            createMagazine();\n\
                            loadedPages.clear();\n\
                            loadingPages.clear();\n\
                            preloadQueue = [];\n\
                            initFlipBook();\n\
                            initialPreload();\n\
                        }, 100);\n\
                    } else {\n\
                        try { turnInstance.turn("resize"); } catch (e) { }\n\
                    }\n\
                }\n\
            }, 200);\n\
        });\n\
        \n\
        $(window).bind("keydown", function (e) {\n\
            if (e.keyCode == 37) { $("#magazine").turn("previous"); e.preventDefault(); }\n\
            else if (e.keyCode == 39) { $("#magazine").turn("next"); e.preventDefault(); }\n\
        });\n\
        \n\
        document.body.addEventListener("touchmove", function (e) {\n\
            if (e.target === document.body || e.target === document.documentElement) e.preventDefault();\n\
        }, { passive: false });\n\
        \n\
        document.body.addEventListener("touchend", function () {\n\
            setTimeout(() => {\n\
                if (turnInstance) {\n\
                    try {\n\
                        const currentView = turnInstance.turn("view");\n\
                        if (currentView && currentView.length) {\n\
                            currentPageNumber = currentView[0] || currentPageNumber;\n\
                            savePage(currentPageNumber);\n\
                        }\n\
                    } catch (e) { }\n\
                }\n\
            }, 100);\n\
        });\n\
        \n\
        console.log("Flip book initialized with " + totalPages + " pages (aggressive preloading enabled)");\n\
        console.log("Next page is preloaded before you flip for smooth transitions");\n\
    </script>\n\
\n\
    <script>\n\
        (function () {\n\
            let pageScrollDragging = false;\n\
            let pageTrackStartY = 0;\n\
            let pageTrackStartScroll = 0;\n\
            let currentTotalPages = ' + pageCount + ';\n\
            let hideTimeout = null;\n\
            let activeTimeout = null;\n\
\n\
            function getSavedPage() {\n\
                const storageKey = "flipbook_last_page_" + title;\n\
                const saved = localStorage.getItem(storageKey);\n\
                if (saved && !isNaN(saved) && saved >= 1 && saved <= currentTotalPages) {\n\
                    return parseInt(saved);\n\
                }\n\
                return 1;\n\
            }\n\
\n\
            function savePage(pageNum) {\n\
                const storageKey = "flipbook_last_page_" + title;\n\
                localStorage.setItem(storageKey, pageNum);\n\
            }\n\
\n\
            function createScrollOverlay() {\n\
                if (document.getElementById("pageScrollOverlay")) return;\n\
\n\
                const overlayHTML = `\n\
                <div id="pageScrollOverlay" style="\n\
                    position: fixed;\n\
                    left: 50%;\n\
                    transform: translateX(-50%);\n\
                    top: 0;\n\
                    bottom: 0;\n\
                    z-index: 9999;\n\
                    display: flex;\n\
                    flex-direction: column;\n\
                    align-items: center;\n\
                    justify-content: center;\n\
                    pointer-events: none;\n\
                    opacity: 0;\n\
                    transition: opacity 0.3s ease;\n\
                ">\n\
                    <div class="vertical-ribbon-base" style="\n\
                        position: absolute;\n\
                        overflow: hidden;\n\
                        left: 50%;\n\
                        transform: translateX(-50%);\n\
                        top: 0;\n\
                        bottom: 0;\n\
                        font-size: 14px;\n\
                        font-weight: bold;\n\
                        color: #fff;\n\
                        --r: 0.8em;\n\
                        border-inline: 0.5em solid #0000;\n\
                        padding: 0.5em 0.2em calc(var(--r) + 0.2em);\n\
                        clip-path: polygon(0 0, 100% 0, 100% 100%, calc(100% - 0.5em) 100%, 50% calc(100% - var(--r)), 0.5em 100%, 0 100%);\n\
                        background: url("https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/ribbon.png") repeat-y center top / 100% auto;\n\
                        width: 48px;\n\
                        height: 85vh;\n\
                        max-height: 85%;\n\
                        display: flex;\n\
                        align-items: center;\n\
                        justify-content: center;\n\
                        white-space: nowrap;\n\
                        z-index: 9998;\n\
                    ">\n\
                        <span style="writing-mode: vertical-rl; text-orientation: mixed;"></span>\n\
                    </div>\n\
                    \n\
                    <div id="pageDisplayCenter" style="\n\
                        position: absolute;\n\
                        left: 28px;\n\
                        top: calc(50% - 3px);\n\
                        transform: translateY(-50%);\n\
                        font-family: "Georgia", "Times New Roman", serif;\n\
                        font-size: 12px;\n\
                        font-weight: normal;\n\
                        font-style: italic;\n\
                        color: #fff8e7;\n\
                        background: url("https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/ribbon2.png") no-repeat center / 100% 100%;\n\
                        padding: 8px;\n\
                        border-radius: 0 4px 4px 0;\n\
                        backdrop-filter: blur(4px);\n\
                        pointer-events: none;\n\
                        white-space: nowrap;\n\
                        z-index: 10;\n\
                        box-shadow: 2px 2px 8px rgba(0,0,0,0.3);\n\
                        opacity: 0;\n\
                        transition: opacity 0.2s ease;\n\
                        letter-spacing: 0.5px;\n\
                    ">\n\
                        <span style="font-family: monospace; font-style: normal; font-weight: bold;">📖</span> Page ${getSavedPage()} / ${currentTotalPages}\n\
                    </div>\n\
                    \n\
                    <div id="pageSliderContainer" style="\n\
                        position: relative;\n\
                        width: 32px;\n\
                        height: 85vh;\n\
                        max-height: 85%;\n\
                        background: transparent;\n\
                        border-radius: 16px;\n\
                        touch-action: none;\n\
                        pointer-events: auto;\n\
                        cursor: grab;\n\
                        z-index: 9999;\n\
                    ">\n\
                        <div style="\n\
                            position: absolute;\n\
                            top: 0;\n\
                            left: 0;\n\
                            width: 100%;\n\
                            height: 100%;\n\
                            overflow: hidden;\n\
                            border-radius: 16px;\n\
                            pointer-events: none;\n\
                        ">\n\
                            <div id="pageTrack" style="\n\
                                position: absolute;\n\
                                top: 0;\n\
                                left: 0;\n\
                                width: 100%;\n\
                                transition: none;\n\
                            "></div>\n\
                        </div>\n\
                        \n\
                        <div style="\n\
                            position: absolute;\n\
                            left: 50%;\n\
                            top: 50%;\n\
                            transform: translate(-50%, -50%);\n\
                            font-size: 20px;\n\
                            font-weight: bold;\n\
                            color: #fff;\n\
                            --r: 0.5em;\n\
                            border-inline: 0.3em solid #0000;\n\
                            padding: 0.3em 0.15em calc(var(--r) + 0.15em);\n\
                            clip-path: polygon(0 0, 100% 0, 100% 100%, calc(100% - 0.3em) calc(100% - var(--r)), 50% 100%, 0.3em calc(100% - var(--r)), 0 100%);\n\
                            width: 36px;\n\
                            height: 40px;\n\
                            white-space: nowrap;\n\
                            z-index: 15;\n\
                            pointer-events: none;\n\
                            display: flex;\n\
                            align-items: center;\n\
                            justify-content: center;\n\
                        ">\n\
                            <span style="writing-mode: vertical-rl; text-orientation: mixed;">📖</span>\n\
                        </div>\n\
                    </div>\n\
                </div>\n\
            `;\n\
                document.body.insertAdjacentHTML("beforeend", overlayHTML);\n\
            }\n\
\n\
            function showOverlay(duration = 3000) {\n\
                const overlay = document.getElementById("pageScrollOverlay");\n\
                if (overlay) {\n\
                    overlay.style.opacity = "1";\n\
                    if (hideTimeout) clearTimeout(hideTimeout);\n\
                    hideTimeout = setTimeout(() => {\n\
                        if (overlay && !pageScrollDragging) {\n\
                            overlay.style.opacity = "0";\n\
                        }\n\
                    }, duration);\n\
                }\n\
            }\n\
\n\
            function showDisplay(duration = 3000) {\n\
                const display = document.getElementById("pageDisplayCenter");\n\
                if (display) {\n\
                    display.style.opacity = "1";\n\
                    if (activeTimeout) clearTimeout(activeTimeout);\n\
                    activeTimeout = setTimeout(() => {\n\
                        if (display && !pageScrollDragging) {\n\
                            display.style.opacity = "0";\n\
                        }\n\
                    }, duration);\n\
                }\n\
            }\n\
\n\
            function updatePageDisplay(pageNum) {\n\
                const display = document.getElementById("pageDisplayCenter");\n\
                if (display) {\n\
                    display.innerHTML = `<span style="font-family: monospace; font-style: normal; font-weight: bold;"></span>${pageNum}/${currentTotalPages}`;\n\
                    savePage(pageNum);\n\
                    showDisplay();\n\
                }\n\
            }\n\
\n\
            function createPageNotches() {\n\
                const track = document.getElementById("pageTrack");\n\
                const container = document.getElementById("pageSliderContainer");\n\
                if (!track || !container) return;\n\
\n\
                track.innerHTML = "";\n\
\n\
                const notchCount = Math.min(currentTotalPages, 51);\n\
                const containerHeight = container.offsetHeight;\n\
                const notchSpacing = containerHeight / (notchCount - 1);\n\
                const centerX = container.offsetWidth / 2;\n\
                const centerY = containerHeight / 2;\n\
                const centerIndex = Math.floor(notchCount / 2);\n\
\n\
                for (let i = 0; i < notchCount; i++) {\n\
                    const notch = document.createElement("div");\n\
                    notch.style.position = "absolute";\n\
                    notch.style.borderRadius = "1px";\n\
                    notch.style.pointerEvents = "none";\n\
\n\
                    const yPos = i * notchSpacing;\n\
                    const offsetFromCenter = i - centerIndex;\n\
\n\
                    if (offsetFromCenter === 0) {\n\
                        notch.style.width = "22px";\n\
                        notch.style.height = "3px";\n\
                        notch.style.left = (centerX - 11) + "px";\n\
                        notch.style.backgroundColor = "rgba(255, 215, 0, 0.9)";\n\
                        notch.style.boxShadow = "0 0 4px rgba(255,215,0,0.5)";\n\
                    } else if (Math.abs(offsetFromCenter) % 5 === 0) {\n\
                        notch.style.width = "18px";\n\
                        notch.style.height = "2px";\n\
                        notch.style.left = (centerX - 9) + "px";\n\
                        notch.style.backgroundColor = "rgba(255, 215, 150, 0.8)";\n\
                    } else {\n\
                        notch.style.width = "10px";\n\
                        notch.style.height = "1.5px";\n\
                        notch.style.left = (centerX - 5) + "px";\n\
                        notch.style.backgroundColor = "rgba(255, 235, 200, 0.6)";\n\
                    }\n\
\n\
                    notch.style.top = yPos + "px";\n\
                    track.appendChild(notch);\n\
                }\n\
\n\
                track.style.height = containerHeight + "px";\n\
            }\n\
\n\
            function setupPageScrolling() {\n\
                const container = document.getElementById("pageSliderContainer");\n\
                const track = document.getElementById("pageTrack");\n\
                const overlay = document.getElementById("pageScrollOverlay");\n\
\n\
                if (!container || !track) {\n\
                    console.error("Ribbon bookmark: elements not found");\n\
                    return;\n\
                }\n\
\n\
                function getPageFromScroll(scrollY) {\n\
                    const containerHeight = container.offsetHeight;\n\
                    const centerY = containerHeight / 2;\n\
                    const centeredPosition = -scrollY + centerY;\n\
                    const progress = centeredPosition / containerHeight;\n\
                    const clamped = Math.max(0, Math.min(1, progress));\n\
                    return Math.floor(clamped * (currentTotalPages - 1)) + 1;\n\
                }\n\
\n\
                function updatePageFromScroll(scrollY) {\n\
                    if (!pageScrollDragging) return;\n\
                    const pageNum = getPageFromScroll(scrollY);\n\
                    updatePageDisplay(pageNum);\n\
\n\
                    const $magazine = $("#magazine");\n\
                    if ($magazine && $magazine.turn) {\n\
                        $magazine.turn("page", pageNum);\n\
                    }\n\
                }\n\
\n\
                function setTrackPosition(pageNum) {\n\
                    if (!track || !container) return;\n\
                    const progress = (pageNum - 1) / (currentTotalPages - 1);\n\
                    const containerHeight = container.offsetHeight;\n\
                    const centerY = containerHeight / 2;\n\
                    const scrollY = -(progress * containerHeight) + centerY;\n\
                    track.style.transform = "translateY(" + scrollY + "px)";\n\
                }\n\
\n\
                function startDrag() {\n\
                    pageScrollDragging = true;\n\
                    showOverlay(2000);\n\
                    container.style.cursor = "grabbing";\n\
                    if (hideTimeout) clearTimeout(hideTimeout);\n\
                    if (activeTimeout) clearTimeout(activeTimeout);\n\
                }\n\
\n\
                function endDrag() {\n\
                    pageScrollDragging = false;\n\
                    container.style.cursor = "grab";\n\
                    const currentScroll = parseFloat(track.style.transform && track.style.transform.match(/translateY\\(([^)]+)/) ? track.style.transform.match(/translateY\\(([^)]+)/)[1] : 0);\n\
                    const pageNum = getPageFromScroll(currentScroll);\n\
                    setTrackPosition(pageNum);\n\
                    updatePageDisplay(pageNum);\n\
\n\
                    if (hideTimeout) clearTimeout(hideTimeout);\n\
                    hideTimeout = setTimeout(() => {\n\
                        const overlayEl = document.getElementById("pageScrollOverlay");\n\
                        if (overlayEl && !pageScrollDragging) overlayEl.style.opacity = "0";\n\
                    }, 2000);\n\
                    if (activeTimeout) clearTimeout(activeTimeout);\n\
                    activeTimeout = setTimeout(() => {\n\
                        const displayEl = document.getElementById("pageDisplayCenter");\n\
                        if (displayEl && !pageScrollDragging) displayEl.style.opacity = "0";\n\
                    }, 2000);\n\
                }\n\
\n\
                container.addEventListener("mousedown", (e) => {\n\
                    e.preventDefault();\n\
                    startDrag();\n\
                    pageTrackStartY = e.clientY;\n\
                    const transform = track.style.transform;\n\
                    pageTrackStartScroll = transform && transform.includes("translateY") ? parseFloat(transform.match(/translateY\\(([^)]+)/)[1]) : 0;\n\
                    updatePageDisplay(getPageFromScroll(pageTrackStartScroll));\n\
                });\n\
\n\
                document.addEventListener("mousemove", (e) => {\n\
                    if (!pageScrollDragging) return;\n\
                    e.preventDefault();\n\
                    const delta = e.clientY - pageTrackStartY;\n\
                    const newScroll = pageTrackStartScroll + delta;\n\
                    track.style.transform = "translateY(" + newScroll + "px)";\n\
                    updatePageFromScroll(newScroll);\n\
                });\n\
\n\
                document.addEventListener("mouseup", () => {\n\
                    if (pageScrollDragging) endDrag();\n\
                });\n\
\n\
                container.addEventListener("touchstart", (e) => {\n\
                    e.preventDefault();\n\
                    startDrag();\n\
                    pageTrackStartY = e.touches[0].clientY;\n\
                    const transform = track.style.transform;\n\
                    pageTrackStartScroll = transform && transform.includes("translateY") ? parseFloat(transform.match(/translateY\\(([^)]+)/)[1]) : 0;\n\
                    updatePageDisplay(getPageFromScroll(pageTrackStartScroll));\n\
                }, { passive: false });\n\
\n\
                container.addEventListener("touchmove", (e) => {\n\
                    if (!pageScrollDragging) return;\n\
                    e.preventDefault();\n\
                    const delta = e.touches[0].clientY - pageTrackStartY;\n\
                    const newScroll = pageTrackStartScroll + delta;\n\
                    track.style.transform = "translateY(" + newScroll + "px)";\n\
                    updatePageFromScroll(newScroll);\n\
                }, { passive: false });\n\
\n\
                container.addEventListener("touchend", (e) => {\n\
                    if (pageScrollDragging) endDrag();\n\
                    e.preventDefault();\n\
                });\n\
\n\
                const $magazine = $("#magazine");\n\
                if ($magazine && $magazine.turn) {\n\
                    $magazine.bind("turned", function (e, page) {\n\
                        if (!pageScrollDragging) {\n\
                            setTrackPosition(page);\n\
                            updatePageDisplay(page);\n\
                        }\n\
                    });\n\
                }\n\
\n\
                const savedPage = getSavedPage();\n\
                setTimeout(() => {\n\
                    createPageNotches();\n\
                    setTrackPosition(savedPage);\n\
                    updatePageDisplay(savedPage);\n\
                    if (overlay) overlay.style.opacity = "1";\n\
                    showOverlay(3000);\n\
                    showDisplay(3000);\n\
                    console.log("Ribbon bookmark ready! Last page: " + savedPage);\n\
                }, 100);\n\
\n\
                setTimeout(() => {\n\
                    const $magazine = $("#magazine");\n\
                    if ($magazine && $magazine.turn) {\n\
                        $magazine.turn("page", savedPage);\n\
                    }\n\
                }, 300);\n\
            }\n\
\n\
            function init() {\n\
                createScrollOverlay();\n\
\n\
                let attempts = 0;\n\
                const interval = setInterval(() => {\n\
                    attempts++;\n\
                    const $magazine = $("#magazine");\n\
                    if (($magazine && $magazine.turn && typeof $magazine.turn("page") !== "undefined") || attempts > 40) {\n\
                        clearInterval(interval);\n\
                        setTimeout(setupPageScrolling, 200);\n\
                    }\n\
                }, 100);\n\
            }\n\
\n\
            if (document.readyState === "loading") {\n\
                document.addEventListener("DOMContentLoaded", init);\n\
            } else {\n\
                init();\n\
            }\n\
        })();\n\
    </script>\n\
    <script>\n\
        (function fixiOSHeight() {\n\
            if (/iPad|iPhone|iPod/.test(navigator.userAgent) ||\n\
                (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)) {\n\
\n\
                function adjustHeight() {\n\
                    const vh = window.visualViewport ? window.visualViewport.height : window.innerHeight;\n\
\n\
                    const magazine = document.getElementById("magazine");\n\
                    if (magazine) {\n\
                        magazine.style.height = vh + "px";\n\
                        magazine.style.top = "0";\n\
                        magazine.style.position = "absolute";\n\
                    }\n\
\n\
                    document.body.style.margin = "0";\n\
                    document.body.style.padding = "0";\n\
                    document.body.style.top = "0";\n\
                    document.body.style.position = "fixed";\n\
\n\
                    document.documentElement.style.margin = "0";\n\
                    document.documentElement.style.padding = "0";\n\
                    document.documentElement.style.top = "0";\n\
\n\
                    const slider = document.getElementById("pageSliderContainer");\n\
                    const ribbon = document.querySelector(".vertical-ribbon-base");\n\
                    const overlay = document.getElementById("pageScrollOverlay");\n\
\n\
                    if (slider) {\n\
                        slider.style.height = (vh * 0.85) + "px";\n\
                        slider.style.maxHeight = (vh * 0.85) + "px";\n\
                        slider.style.top = "auto";\n\
                        slider.style.bottom = "auto";\n\
                    }\n\
                    if (ribbon) {\n\
                        ribbon.style.height = (vh * 0.85) + "px";\n\
                        ribbon.style.maxHeight = (vh * 0.85) + "px";\n\
                    }\n\
                    if (overlay) {\n\
                        overlay.style.top = "0";\n\
                        overlay.style.bottom = "0";\n\
                    }\n\
\n\
                    setTimeout(() => {\n\
                        if (typeof createPageNotches === "function") {\n\
                            createPageNotches();\n\
                        }\n\
                        if (typeof setTrackPosition === "function" && window.currentPageNumber) {\n\
                            setTrackPosition(window.currentPageNumber);\n\
                        }\n\
                    }, 50);\n\
                }\n\
\n\
                adjustHeight();\n\
                window.visualViewport && window.visualViewport.addEventListener("resize", adjustHeight);\n\
                window.addEventListener("resize", adjustHeight);\n\
                window.addEventListener("orientationchange", function () {\n\
                    setTimeout(adjustHeight, 50);\n\
                });\n\
\n\
                setTimeout(adjustHeight, 100);\n\
            }\n\
        })();\n\
    </script>\n\
    <script>\n\
        (function () {\n\
            let wheelTimeout = null;\n\
            let lastScrollTime = 0;\n\
            const scrollThrottle = 80;\n\
            let isScrolling = false;\n\
\n\
            function getPageFromScroll(scrollY) {\n\
                const container = document.getElementById("pageSliderContainer");\n\
                if (!container) return 1;\n\
\n\
                const containerHeight = container.offsetHeight;\n\
                const centerY = containerHeight / 2;\n\
                const centeredPosition = -scrollY + centerY;\n\
                const progress = centeredPosition / containerHeight;\n\
                const clamped = Math.max(0, Math.min(1, progress));\n\
                const currentTotalPages = window.currentTotalPages || ' + pageCount + ';\n\
                return Math.floor(clamped * (currentTotalPages - 1)) + 1;\n\
            }\n\
\n\
            function setTrackPosition(pageNum) {\n\
                const track = document.getElementById("pageTrack");\n\
                const container = document.getElementById("pageSliderContainer");\n\
                if (!track || !container) return;\n\
\n\
                const currentTotalPages = window.currentTotalPages || ' + pageCount + ';\n\
                const progress = (pageNum - 1) / (currentTotalPages - 1);\n\
                const containerHeight = container.offsetHeight;\n\
                const centerY = containerHeight / 2;\n\
                const scrollY = -(progress * containerHeight) + centerY;\n\
                track.style.transform = "translateY(" + scrollY + "px)";\n\
            }\n\
\n\
            function updatePageDisplayWithoutSave(pageNum) {\n\
                const display = document.getElementById("pageDisplayCenter");\n\
                if (display) {\n\
                    display.innerHTML = `<span style="font-family: monospace; font-style: normal; font-weight: bold;"></span>${pageNum}/${window.currentTotalPages || ' + pageCount + '}`;\n\
                }\n\
            }\n\
\n\
            function savePageAndUpdateDisplay(pageNum) {\n\
                const display = document.getElementById("pageDisplayCenter");\n\
                if (display) {\n\
                    display.innerHTML = `<span style="font-family: monospace; font-style: normal; font-weight: bold;"></span>${pageNum}/${window.currentTotalPages || ' + pageCount + '}`;\n\
                    localStorage.setItem("flipbook_last_page_" + title, pageNum);\n\
                }\n\
            }\n\
\n\
            function handleWheel(e) {\n\
                if (window.pageScrollDragging) return;\n\
\n\
                const container = document.getElementById("pageSliderContainer");\n\
                const track = document.getElementById("pageTrack");\n\
                if (!container || !track) return;\n\
\n\
                const now = Date.now();\n\
                if (now - lastScrollTime < scrollThrottle) return;\n\
                lastScrollTime = now;\n\
\n\
                e.preventDefault();\n\
\n\
                const overlay = document.getElementById("pageScrollOverlay");\n\
                const display = document.getElementById("pageDisplayCenter");\n\
\n\
                if (overlay) overlay.style.opacity = "1";\n\
                if (display) display.style.opacity = "1";\n\
\n\
                if (window.wheelHideTimeout) clearTimeout(window.wheelHideTimeout);\n\
                if (window.wheelDisplayTimeout) clearTimeout(window.wheelDisplayTimeout);\n\
\n\
                window.wheelHideTimeout = setTimeout(() => {\n\
                    if (overlay && !window.pageScrollDragging && !isScrolling) {\n\
                        overlay.style.opacity = "0";\n\
                    }\n\
                }, 1500);\n\
\n\
                window.wheelDisplayTimeout = setTimeout(() => {\n\
                    if (display && !window.pageScrollDragging && !isScrolling) {\n\
                        display.style.opacity = "0";\n\
                    }\n\
                }, 1500);\n\
\n\
                const currentScroll = parseFloat(track.style.transform && track.style.transform.match(/translateY\\(([^)]+)/) ? track.style.transform.match(/translateY\\(([^)]+)/)[1] : 0);\n\
                const sensitivity = 1.5;\n\
                const delta = e.deltaY * sensitivity;\n\
\n\
                let newScroll = currentScroll + delta;\n\
                const containerHeight = container.offsetHeight;\n\
                const centerY = containerHeight / 2;\n\
                const minScroll = -centerY;\n\
                const maxScroll = (containerHeight) - centerY;\n\
\n\
                newScroll = Math.max(minScroll, Math.min(maxScroll, newScroll));\n\
                track.style.transform = "translateY(" + newScroll + "px)";\n\
\n\
                const pageNum = getPageFromScroll(newScroll);\n\
                updatePageDisplayWithoutSave(pageNum);\n\
\n\
                const $magazine = $("#magazine");\n\
                if ($magazine && $magazine.turn) {\n\
                    $magazine.turn("page", pageNum);\n\
                }\n\
\n\
                if (wheelTimeout) clearTimeout(wheelTimeout);\n\
                wheelTimeout = setTimeout(() => {\n\
                    isScrolling = true;\n\
                    const finalScroll = parseFloat(track.style.transform && track.style.transform.match(/translateY\\(([^)]+)/) ? track.style.transform.match(/translateY\\(([^)]+)/)[1] : 0);\n\
                    const finalPage = getPageFromScroll(finalScroll);\n\
                    setTrackPosition(finalPage);\n\
                    savePageAndUpdateDisplay(finalPage);\n\
\n\
                    const $magazine = $("#magazine");\n\
                    if ($magazine && $magazine.turn) {\n\
                        $magazine.turn("page", finalPage);\n\
                    }\n\
\n\
                    setTimeout(() => {\n\
                        isScrolling = false;\n\
                    }, 200);\n\
                }, 100);\n\
            }\n\
\n\
            function initWheelScrolling() {\n\
                window.currentTotalPages = ' + pageCount + ';\n\
                window.pageScrollDragging = false;\n\
\n\
                window.addEventListener("wheel", handleWheel, { passive: false });\n\
                console.log("Wheel scrolling enabled - scroll anywhere to control pages");\n\
            }\n\
\n\
            if (document.readyState === "loading") {\n\
                document.addEventListener("DOMContentLoaded", initWheelScrolling);\n\
            } else {\n\
                initWheelScrolling();\n\
            }\n\
        })();\n\
    </script>\n\
</body>\n\
</html>';
}

// ============= PURE JSON API ENDPOINTS =============
// NO static file serving - everything returns JSON or error

// Get history list
app.get('/api/history', async (req, res) => {
    res.json({ success: true, history: conversionHistory });
});

// Delete from history
app.delete('/api/history/:id', async (req, res) => {
    const id = req.params.id;
    const entry = conversionHistory.find(h => h.id === id);
    if (entry) {
        // Delete files
        const outputDir = path.join(OUTPUT_DIR, `flipbook_${id}`);
        const zipPath = path.join(OUTPUT_DIR, `flipbook_${id}.zip`);
        if (fs.existsSync(outputDir)) fs.rmSync(outputDir, { recursive: true, force: true });
        if (fs.existsSync(zipPath)) fs.unlinkSync(zipPath);
        // Remove from history
        conversionHistory = conversionHistory.filter(h => h.id !== id);
        saveHistory();
        res.json({ success: true });
    } else {
        res.status(404).json({ error: 'Not found' });
    }
});

// Queue stats
app.get('/queue/stats', async (req, res) => {
    const [waiting, active] = await Promise.all([
        pdfQueue.getWaitingCount(),
        pdfQueue.getActiveCount()
    ]);
    res.json({ waiting, active, concurrency: 3 });
});

// Health check
app.get('/health', async (req, res) => {
    res.json({ status: 'OK', timestamp: Date.now() });
});

// Cache invalidation
app.post('/cache/invalidate', async (req, res) => {
    try {
        const { url } = req.body;
        const cacheKey = crypto.createHash('md5').update(url).digest('hex');
        const outputDir = path.join(OUTPUT_DIR, `flipbook_${cacheKey}`);
        const zipPath = path.join(OUTPUT_DIR, `flipbook_${cacheKey}.zip`);
        
        if (fs.existsSync(outputDir)) fs.rmSync(outputDir, { recursive: true, force: true });
        if (fs.existsSync(zipPath)) fs.unlinkSync(zipPath);
        
        res.json({ message: `Invalidated cache for ${url}` });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Clear all cache
app.post('/cache/clear-all', async (req, res) => {
    try {
        const files = fs.readdirSync(OUTPUT_DIR);
        let deleted = 0;
        for (const file of files) {
            if (file !== 'history.json') {
                const filePath = path.join(OUTPUT_DIR, file);
                fs.rmSync(filePath, { recursive: true, force: true });
                deleted++;
            }
        }
        conversionHistory = [];
        saveHistory();
        await pdfQueue.empty();
        res.json({ message: `Cleared ${deleted} cache entries` });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Convert PDF by URL - API endpoint (JSON only)
app.get('/api/convert', validateToken, async (req, res) => {
    const startTime = Date.now();
    
    try {
        const targetUrl = req.query.url;
        const forceRefresh = req.query.rc === '1' || req.query.recache === '1';
        
        if (!targetUrl) {
            return res.status(400).json({
                error: 'Missing url parameter',
                example: '/api/convert?url=https://example.com/document.pdf'
            });
        }
        
        const normalizedUrl = targetUrl.startsWith('http') ? targetUrl : 'https://' + targetUrl;
        const cacheKey = crypto.createHash('md5').update(normalizedUrl).digest('hex');
        const outputDir = path.join(OUTPUT_DIR, `flipbook_${cacheKey}`);
        const zipPath = path.join(OUTPUT_DIR, `flipbook_${cacheKey}.zip`);
        
        // Check cache
        if (!forceRefresh && fs.existsSync(outputDir) && fs.existsSync(zipPath)) {
            const files = fs.readdirSync(outputDir);
            const htmlFile = files.find(f => f.endsWith('_flipbook.html'));
            const pdfName = htmlFile ? htmlFile.replace('_flipbook.html', '') : 'document';
            
            console.log(`[Cache] HIT for ${normalizedUrl}`);
            
            res.set('X-Cache', 'HIT');
            res.set('X-Processing-Time', `${Date.now() - startTime}ms`);
            
            return res.json({
                success: true,
                cached: true,
                title: pdfName,
                html_url: `/output/flipbook_${cacheKey}/${htmlFile}`,
                zip_url: `/output/flipbook_${cacheKey}.zip`
            });
        }
        
        console.log(`[Cache] MISS for ${normalizedUrl}, queueing...`);
        
        const waiting = await pdfQueue.getWaitingCount();
        const active = await pdfQueue.getActiveCount();
        
        if (waiting > 20) {
            return res.status(503).json({
                error: 'Queue full',
                queue: { waiting, active },
                retryAfter: Math.ceil(waiting / 3) * 10,
                message: 'Too many requests. Try again in a few seconds.'
            });
        }
        
        const job = await pdfQueue.add({
            pdfUrl: normalizedUrl,
            cacheKey: cacheKey,
            originalName: null,
            source: 'url'
        });
        
        console.log(`[Queue] Added job ${job.id} for ${normalizedUrl}`);
        
        const result = await job.finished();
        
        res.set('X-Cache', 'MISS');
        res.set('X-Processing-Time', `${Date.now() - startTime}ms`);
        res.set('X-Queue-Waiting', waiting);
        res.set('X-Queue-Active', active);
        
        res.json({
            success: true,
            cached: false,
            job_id: job.id,
            ...result
        });
        
    } catch (error) {
        console.error('[Error]', error.message);
        res.status(500).json({
            error: 'Failed to process PDF',
            details: error.message,
            url: req.query.url
        });
    }
});

// File upload endpoint
app.post('/api/upload', upload.single('pdf'), async (req, res) => {
    // Handle multer errors
    if (req.fileValidationError) {
        return res.status(400).json({ error: req.fileValidationError });
    }
    
    if (!req.file) {
        return res.status(400).json({ error: 'No PDF file uploaded. Please send a file with field name "pdf".' });
    }
    
    const startTime = Date.now();
    const uploadedFile = req.file;
    const originalName = uploadedFile.originalname;
    const cacheKey = crypto.createHash('md5').update(originalName + Date.now()).digest('hex');
    
    console.log(`[Upload] Received: ${originalName} (${uploadedFile.size} bytes)`);
    
    try {
        const waiting = await pdfQueue.getWaitingCount();
        const active = await pdfQueue.getActiveCount();
        
        const job = await pdfQueue.add({
            pdfPath: uploadedFile.path,
            cacheKey: cacheKey,
            originalName: originalName,
            source: 'upload'
        });
        
        console.log(`[Upload] Added job ${job.id} for ${originalName}`);
        
        // Wait for job to complete
        const result = await job.finished();
        
        // Send JSON response
        res.json({
            success: true,
            job_id: job.id,
            ...result
        });
        
    } catch (error) {
        console.error('[Upload Error]', error.message);
        // Clean up uploaded file on error
        if (uploadedFile.path && fs.existsSync(uploadedFile.path)) {
            fs.unlinkSync(uploadedFile.path);
        }
        res.status(500).json({
            error: 'Failed to process PDF',
            details: error.message
        });
    }
});

// Error handler for multer
app.use((error, req, res, next) => {
    if (error instanceof multer.MulterError) {
        if (error.code === 'FILE_TOO_LARGE') {
            return res.status(400).json({ error: 'File too large. Maximum size is 100MB.' });
        }
        return res.status(400).json({ error: error.message });
    }
    next(error);
});

// 404 handler for any non-API routes
app.use((req, res) => {
    res.status(404).json({ 
        error: 'Not Found',
        message: 'This is a JSON API server. Please use /api/ endpoints or visit the web UI served by nginx.'
    });
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`✅ PDF to FlipBook API running on port ${PORT}`);
    console.log(`   API Base: http://localhost:${PORT}/api/convert`);
    console.log(`   Upload: POST /api/upload`);
    console.log(`   History: GET /api/history`);
    console.log(`   Queue: 3 concurrent conversions`);
    console.log(`   ⚠️  Web UI is served by nginx at /var/www/flipbook/web/`);
    if (API_TOKEN) {
        console.log(`   Authentication: REQUIRED (token set)`);
    } else {
        console.log(`   Authentication: DISABLED (public access)`);
    }
});
EOF

# ============= CREATE WEB UI (Served by nginx) =============
log "Creating web UI at /var/www/flipbook/web/..."

cat > /var/www/flipbook/web/index.html << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes">
    <title>PDF to FlipBook - Convert PDF to Interactive Flipbook</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            color: #e0e0e0;
            min-height: 100vh;
        }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        
        /* Header */
        .header {
            text-align: center;
            padding: 40px 20px;
            background: rgba(0,0,0,0.3);
            border-radius: 24px;
            margin-bottom: 30px;
            backdrop-filter: blur(10px);
        }
        .header h1 {
            font-size: 48px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            margin-bottom: 10px;
        }
        .header p { color: #a0a0a0; font-size: 18px; }
        .badge {
            display: inline-block;
            background: rgba(102, 126, 234, 0.2);
            border: 1px solid rgba(102, 126, 234, 0.5);
            border-radius: 20px;
            padding: 5px 12px;
            font-size: 12px;
            margin-top: 15px;
        }
        
        /* Main Card */
        .card {
            background: rgba(30, 30, 50, 0.9);
            backdrop-filter: blur(10px);
            border-radius: 24px;
            padding: 30px;
            margin-bottom: 30px;
            border: 1px solid rgba(255,255,255,0.1);
            box-shadow: 0 20px 40px rgba(0,0,0,0.3);
        }
        .card h2 {
            font-size: 24px;
            margin-bottom: 20px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        /* Drop Zone */
        .drop-zone {
            border: 3px dashed rgba(102, 126, 234, 0.5);
            border-radius: 20px;
            padding: 60px 40px;
            text-align: center;
            cursor: pointer;
            transition: all 0.3s ease;
            background: rgba(0,0,0,0.2);
        }
        .drop-zone:hover, .drop-zone.drag-over {
            border-color: #667eea;
            background: rgba(102, 126, 234, 0.1);
            transform: scale(1.01);
        }
        .drop-zone .icon { font-size: 64px; margin-bottom: 20px; }
        .drop-zone h3 { font-size: 24px; margin-bottom: 10px; }
        .drop-zone p { color: #888; }
        
        /* File Info */
        .file-info {
            margin-top: 20px;
            padding: 15px;
            background: rgba(0,0,0,0.3);
            border-radius: 12px;
            display: none;
        }
        .file-info.show { display: block; animation: fadeIn 0.3s; }
        .file-name { font-weight: bold; color: #667eea; word-break: break-all; }
        .file-size { color: #888; font-size: 12px; margin-top: 5px; }
        
        /* Buttons */
        .btn-group { display: flex; gap: 15px; margin-top: 20px; flex-wrap: wrap; }
        .btn {
            padding: 12px 28px;
            border-radius: 12px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            border: none;
            transition: all 0.2s ease;
            display: inline-flex;
            align-items: center;
            gap: 8px;
        }
        .btn-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .btn-primary:hover:not(:disabled) {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(102,126,234,0.3);
        }
        .btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }
        .btn-secondary {
            background: rgba(255,255,255,0.1);
            color: #e0e0e0;
            border: 1px solid rgba(255,255,255,0.2);
        }
        .btn-secondary:hover {
            background: rgba(255,255,255,0.2);
        }
        .btn-danger {
            background: rgba(239, 68, 68, 0.2);
            color: #ef4444;
            border: 1px solid rgba(239,68,68,0.3);
        }
        .btn-danger:hover { background: rgba(239,68,68,0.3); }
        
        /* Progress */
        .progress-container {
            margin-top: 20px;
            display: none;
        }
        .progress-bar {
            width: 100%;
            height: 6px;
            background: rgba(255,255,255,0.1);
            border-radius: 3px;
            overflow: hidden;
        }
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #667eea, #764ba2);
            width: 0%;
            transition: width 0.3s ease;
            border-radius: 3px;
        }
        .progress-text {
            text-align: center;
            margin-top: 10px;
            font-size: 14px;
            color: #888;
        }
        
        /* Logs */
        .log-area {
            background: rgba(0,0,0,0.5);
            border-radius: 12px;
            padding: 15px;
            margin-top: 20px;
            max-height: 200px;
            overflow-y: auto;
            font-family: 'Monaco', 'Menlo', monospace;
            font-size: 12px;
        }
        .log-line {
            padding: 4px 0;
            border-bottom: 1px solid rgba(255,255,255,0.05);
            font-family: monospace;
        }
        .log-info { color: #667eea; }
        .log-success { color: #10b981; }
        .log-error { color: #ef4444; }
        .log-warning { color: #f59e0b; }
        
        /* Result */
        .result-area {
            margin-top: 20px;
            display: none;
        }
        .result-area.show { display: block; animation: fadeIn 0.3s; }
        .result-links {
            display: flex;
            gap: 15px;
            flex-wrap: wrap;
        }
        .result-link {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 12px 24px;
            background: rgba(16, 185, 129, 0.1);
            border: 1px solid rgba(16, 185, 129, 0.3);
            border-radius: 12px;
            text-decoration: none;
            color: #10b981;
            transition: all 0.2s;
        }
        .result-link:hover {
            background: rgba(16, 185, 129, 0.2);
            transform: translateY(-2px);
        }
        
        /* History Section */
        .history-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        .history-item {
            background: rgba(0,0,0,0.3);
            border-radius: 16px;
            padding: 16px;
            border: 1px solid rgba(255,255,255,0.1);
            transition: all 0.2s;
        }
        .history-item:hover {
            transform: translateY(-3px);
            border-color: rgba(102,126,234,0.5);
        }
        .history-title {
            font-weight: bold;
            font-size: 16px;
            margin-bottom: 8px;
            word-break: break-all;
            color: #667eea;
        }
        .history-meta {
            font-size: 11px;
            color: #888;
            margin-bottom: 12px;
        }
        .history-links {
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
        }
        .history-links a {
            color: #10b981;
            text-decoration: none;
            font-size: 12px;
            display: inline-flex;
            align-items: center;
            gap: 4px;
        }
        .history-links a:hover { text-decoration: underline; }
        .delete-btn {
            background: none;
            border: none;
            color: #ef4444;
            cursor: pointer;
            font-size: 12px;
            margin-top: 10px;
            display: inline-flex;
            align-items: center;
            gap: 4px;
        }
        .delete-btn:hover { opacity: 0.8; }
        
        /* API Section */
        .api-section {
            background: #0d1117;
            border-radius: 12px;
            padding: 20px;
            margin-top: 20px;
        }
        .code-block {
            background: #1a1a2e;
            border-radius: 8px;
            padding: 15px;
            overflow-x: auto;
            font-family: monospace;
            font-size: 13px;
            margin: 10px 0;
        }
        
        /* Footer */
        .footer {
            text-align: center;
            padding: 30px;
            color: #666;
            font-size: 14px;
            border-top: 1px solid rgba(255,255,255,0.1);
            margin-top: 30px;
        }
        .footer a { color: #667eea; text-decoration: none; }
        
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(10px); }
            to { opacity: 1; transform: translateY(0); }
        }
        
        @media (max-width: 768px) {
            .container { padding: 12px; }
            .header h1 { font-size: 32px; }
            .drop-zone { padding: 30px 20px; }
            .btn { padding: 10px 20px; font-size: 14px; }
        }
    </style>
</head>
<body>
    <div class="container">   
        <div class="card">
            <h2>📄 Upload PDF</h2>
            <div class="drop-zone" id="dropZone">
                <div class="icon">📖</div>
                <h3>Drag & Drop PDF Here</h3>
                <p>or click to select a file</p>
                <p style="font-size: 12px; margin-top: 10px;">Max file size: 1024MB</p>
            </div>
            <div class="file-info" id="fileInfo">
                <div class="file-name" id="fileName"></div>
                <div class="file-size" id="fileSize"></div>
            </div>
            <div class="btn-group">
                <button class="btn btn-primary" id="convertBtn" disabled>🔄 Convert to FlipBook</button>
                <button class="btn btn-secondary" id="clearLogsBtn">🗑️ Clear Logs</button>
            </div>
            <div class="progress-container" id="progressContainer">
                <div class="progress-bar"><div class="progress-fill" id="progressFill"></div></div>
                <div class="progress-text" id="progressText">Preparing...</div>
            </div>
            <div class="log-area" id="logArea">
                <div class="log-line log-info">✨ Ready! Drag & drop a PDF to start</div>
            </div>
            <div class="result-area" id="resultArea">
                <h3 style="margin-bottom: 15px;">🎉 Conversion Complete!</h3>
                <div class="result-links" id="resultLinks"></div>
            </div>
        </div>
        
        <div class="card" id="historyCard" style="display: none;">
            <h2>📚 Recent Flipbooks</h2>
            <div class="history-grid" id="historyGrid"></div>
        </div>
        
        <div class="card">
            <h2>🔌 API Access</h2>
            <p>You can also use this service programmatically:</p>
            <div class="api-section">
                <strong>Convert PDF by URL:</strong>
                <div class="code-block" id="apiUrlExample"></div>
                <strong>Response:</strong>
                <div class="code-block" id="apiResponseExample"></div>
                <strong>Upload file via curl:</strong>
                <div class="code-block" id="curlExample"></div>
            </div>
        </div>
        
        <div class="footer">
            Powered by Turn.js | PDF to FlipBook v2.0 (WineJS Architecture)<br>
            <a href="#" id="clearAllCacheBtn">Clear All Cache</a> | 
            <a href="/health">Health Check</a> | 
            <a href="/queue/stats">Queue Stats</a>
        </div>
    </div>
    
    <script>
        const API_BASE = '';
        let currentFile = null;
        let isProcessing = false;
        let eventSource = null;
        
        // Get API token from URL if present
        const urlParams = new URLSearchParams(window.location.search);
        const apiToken = urlParams.get('token') || '';
        
        function addLog(msg, type = 'info') {
            const logArea = document.getElementById('logArea');
            const line = document.createElement('div');
            line.className = `log-line log-${type}`;
            line.textContent = `[${new Date().toLocaleTimeString()}] ${msg}`;
            logArea.appendChild(line);
            line.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        }
        
        function clearLogs() {
            document.getElementById('logArea').innerHTML = '';
            addLog('Logs cleared', 'info');
        }
        
        function formatFileSize(bytes) {
            if (bytes === 0) return '0 B';
            const k = 1024, sizes = ['B', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
        }
        
        function handleDrop(e) {
            e.preventDefault();
            document.getElementById('dropZone').classList.remove('drag-over');
            const files = e.dataTransfer.files;
            if (files.length > 0 && files[0].type === 'application/pdf') {
                currentFile = files[0];
                document.getElementById('fileName').textContent = currentFile.name;
                document.getElementById('fileSize').textContent = formatFileSize(currentFile.size);
                document.getElementById('fileInfo').classList.add('show');
                document.getElementById('convertBtn').disabled = false;
                addLog(`PDF loaded: ${currentFile.name} (${formatFileSize(currentFile.size)})`, 'success');
            } else {
                addLog('Please drop a valid PDF file', 'error');
            }
        }
        
        function handleDragOver(e) {
            e.preventDefault();
            document.getElementById('dropZone').classList.add('drag-over');
        }
        
        function handleDragLeave(e) {
            e.preventDefault();
            document.getElementById('dropZone').classList.remove('drag-over');
        }
        
        async function selectFile() {
            const input = document.createElement('input');
            input.type = 'file';
            input.accept = 'application/pdf';
            input.onchange = (e) => {
                if (e.target.files.length > 0) {
                    currentFile = e.target.files[0];
                    document.getElementById('fileName').textContent = currentFile.name;
                    document.getElementById('fileSize').textContent = formatFileSize(currentFile.size);
                    document.getElementById('fileInfo').classList.add('show');
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
            document.getElementById('resultArea').classList.remove('show');
            document.getElementById('progressFill').style.width = '0%';
            document.getElementById('progressText').textContent = 'Uploading...';
            
            const formData = new FormData();
            formData.append('pdf', currentFile);
            
            addLog('Uploading PDF...', 'info');
            
            try {
                const response = await fetch('/api/upload', {
                    method: 'POST',
                    body: formData
                });
                
                const result = await response.json();
                
                if (result.success) {
                    addLog(`✅ Conversion complete! ${result.page_count} pages converted`, 'success');
                    document.getElementById('progressFill').style.width = '100%';
                    document.getElementById('progressText').textContent = 'Complete!';
                    
                    const resultLinks = document.getElementById('resultLinks');
                    resultLinks.innerHTML = `
                        <a href="${result.html_url}" class="result-link" target="_blank">📖 View FlipBook HTML</a>
                        <a href="${result.zip_url}" class="result-link" target="_blank">📦 Download ZIP (all pages)</a>
                    `;
                    document.getElementById('resultArea').classList.add('show');
                    
                    addLog(`Flipbook available at: ${result.html_url}`, 'success');
                    loadHistory();
                } else {
                    addLog(`❌ Conversion failed: ${result.error || 'Unknown error'}`, 'error');
                }
            } catch (error) {
                addLog(`❌ Error: ${error.message}`, 'error');
            } finally {
                isProcessing = false;
                document.getElementById('convertBtn').disabled = false;
                setTimeout(() => {
                    document.getElementById('progressContainer').style.display = 'none';
                }, 2000);
            }
        }
        
        async function loadHistory() {
            try {
                const response = await fetch('/api/history');
                const data = await response.json();
                const history = data.history || [];
                
                const historyCard = document.getElementById('historyCard');
                const historyGrid = document.getElementById('historyGrid');
                
                if (history.length > 0) {
                    historyCard.style.display = 'block';
                    historyGrid.innerHTML = history.map(item => `
                        <div class="history-item">
                            <div class="history-title">📄 ${escapeHtml(item.title)}</div>
                            <div class="history-meta">${item.page_count} pages | ${new Date(item.created_at).toLocaleString()}</div>
                            <div class="history-links">
                                <a href="${item.html_url}" target="_blank">📖 View</a>
                                <a href="${item.zip_url}" target="_blank">📦 ZIP</a>
                            </div>
                            <button class="delete-btn" onclick="deleteHistoryItem('${item.id}')">🗑️ Delete</button>
                        </div>
                    `).join('');
                } else {
                    historyCard.style.display = 'none';
                }
            } catch (error) {
                console.error('Failed to load history:', error);
            }
        }
        
        async function deleteHistoryItem(id) {
            if (confirm('Delete this flipbook?')) {
                try {
                    await fetch(`/api/history/${id}`, { method: 'DELETE' });
                    loadHistory();
                    addLog('Flipbook deleted', 'warning');
                } catch (error) {
                    addLog(`Failed to delete: ${error.message}`, 'error');
                }
            }
        }
        
        async function clearAllCache() {
            if (confirm('⚠️ WARNING: This will delete ALL flipbooks! Are you sure?')) {
                try {
                    const response = await fetch('/cache/clear-all', { method: 'POST' });
                    const result = await response.json();
                    addLog(result.message, 'success');
                    loadHistory();
                } catch (error) {
                    addLog(`Failed to clear cache: ${error.message}`, 'error');
                }
            }
        }
        
        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }
        
        // Set up API examples
        const domain = window.location.origin;
        const tokenParam = apiToken ? `&token=${apiToken}` : '';
        document.getElementById('apiUrlExample').textContent = `${domain}/api/convert?url=https://example.com/document.pdf${tokenParam}`;
        document.getElementById('apiResponseExample').textContent = JSON.stringify({
            success: true,
            cached: false,
            title: "document",
            page_count: 10,
            html_url: "/output/flipbook_hash/document_flipbook.html",
            zip_url: "/output/flipbook_hash.zip"
        }, null, 2);
        document.getElementById('curlExample').textContent = `curl -X POST ${domain}/api/upload -F "pdf=@document.pdf"`;
        
        // Event listeners
        document.getElementById('dropZone').addEventListener('dragover', handleDragOver);
        document.getElementById('dropZone').addEventListener('dragleave', handleDragLeave);
        document.getElementById('dropZone').addEventListener('drop', handleDrop);
        document.getElementById('dropZone').addEventListener('click', selectFile);
        document.getElementById('convertBtn').addEventListener('click', convertPDF);
        document.getElementById('clearLogsBtn').addEventListener('click', clearLogs);
        document.getElementById('clearAllCacheBtn').addEventListener('click', clearAllCache);
        
        // Load history on page load
        loadHistory();
        
        addLog('Web UI ready! Drag & drop a PDF or use the API', 'success');
        addLog('API is JSON only at /api/convert, /api/upload, /api/history', 'info');
    </script>
</body>
</html>
HTML_EOF

# Create PM2 ecosystem file
log "Creating PM2 ecosystem configuration..."
cat > /opt/ecosystem.config.js << EOF
module.exports = {
    apps: [
        {
            name: 'flipbook-api',
            cwd: '/opt/flipbook-api',
            script: 'server.js',
            watch: false,
            instances: 1,
            exec_mode: 'fork',
            max_memory_restart: '500M',
            env: {
                NODE_ENV: 'production',
                PORT: 3000,
                API_TOKEN: '$API_TOKEN'
            }
        }
    ]
};
EOF

# Start PM2 service
log "Starting PM2 service..."
pm2 start /opt/ecosystem.config.js
pm2 save
pm2 startup

# ============= SETUP NGINX AND SSL =============

# Configure firewall
log "Configuring firewall..."
if command -v ufw &> /dev/null; then
    ufw --force disable
    ufw allow 22/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    ufw --force enable
    log "Firewall configured"
else
    apt-get install -y -qq ufw
    ufw --force disable
    ufw allow 22/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    ufw --force enable
fi

# Stop services using port 80
log "Stopping any services using port 80..."
systemctl stop nginx 2>/dev/null || true
pkill -f nginx 2>/dev/null || true
pm2 stop all 2>/dev/null || true
sleep 2
fuser -k 80/tcp 2>/dev/null || true
sleep 2

# Wait for port 80 to be free
log "Waiting for port 80 to be free..."
PORT_FREE=false
for i in {1..10}; do
    if ! ss -tulpn | grep -q ":80 "; then
        PORT_FREE=true
        log "✅ Port 80 is free after $i seconds"
        break
    fi
    log "Port 80 still in use... waiting (${i}/10)"
    sleep 1
done

if [ "$PORT_FREE" = false ]; then
    error "Port 80 is still in use after 10 seconds"
fi

# Install nginx and SSL tools
log "Installing nginx and SSL tools..."
apt-get install -y -qq nginx certbot python3-certbot-nginx

# Stop nginx
systemctl stop nginx 2>/dev/null || true
pkill -f nginx 2>/dev/null || true
sleep 2

# Get SSL certificate
log "Obtaining SSL certificate for $DOMAIN_NAME..."
if certbot certonly --standalone -d "$DOMAIN_NAME" --non-interactive --agree-tos -m "$SSL_EMAIL"; then
    log "✅ SSL certificate obtained successfully"
    SSL_ENABLED=true
else
    warn "SSL certificate failed. Continuing with HTTP only..."
    SSL_ENABLED=false
fi

# Create nginx configuration (WineJS style)
log "Creating nginx reverse proxy configuration (WineJS architecture)..."

if [ "$SSL_ENABLED" = true ]; then
    cat > /etc/nginx/sites-available/$DOMAIN_NAME << 'NGINX_EOF'
# Cache zone for API responses
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=flipbook_cache:50m max_size=1024m inactive=24h use_temp_path=off;

# HTTP redirect to HTTPS
server {
    listen 80;
    server_name DOMAIN_NAME_PLACEHOLDER DROPLET_IP_PLACEHOLDER;
    
    # Redirect all HTTP traffic to HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name DOMAIN_NAME_PLACEHOLDER;
    
    ssl_certificate /etc/letsencrypt/live/DOMAIN_NAME_PLACEHOLDER/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN_NAME_PLACEHOLDER/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers off;
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    client_max_body_size 1024M;
    
    # Web UI static files - served directly by nginx
    location / {
        root /var/www/flipbook/web;
        try_files $uri $uri/ /index.html;
        index index.html;
        
        # Cache static assets
        location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg)$ {
            expires 30d;
            add_header Cache-Control "public, immutable";
        }
    }
    
    # API endpoints - proxy to Node.js JSON API
    location /api/ {
        proxy_pass http://127.0.0.1:3000/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_read_timeout 300s;
        client_max_body_size 1024M;
    }
    
    # Queue stats endpoint
    location /queue/ {
        proxy_pass http://127.0.0.1:3000/queue/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
    }
    
    # Health check endpoint
    location /health {
        proxy_pass http://127.0.0.1:3000/health;
        access_log off;
    }
    
    # Cache management endpoints
    location /cache/ {
        proxy_pass http://127.0.0.1:3000/cache/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
    }
    
    # Generated flipbook files (static assets)
    location /output/ {
        alias /var/www/flipbook/output/;
        access_log off;
        expires 1h;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }
}
NGINX_EOF

    # Replace placeholders
    sed -i "s/DOMAIN_NAME_PLACEHOLDER/$DOMAIN_NAME/g" /etc/nginx/sites-available/$DOMAIN_NAME
    sed -i "s/DROPLET_IP_PLACEHOLDER/$DROPLET_IP/g" /etc/nginx/sites-available/$DOMAIN_NAME

else
    cat > /etc/nginx/sites-available/$DOMAIN_NAME << 'NGINX_EOF'
# Cache zone for API responses
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=flipbook_cache:50m max_size=500m inactive=24h use_temp_path=off;

server {
    listen 80;
    server_name DOMAIN_NAME_PLACEHOLDER DROPLET_IP_PLACEHOLDER;
    
    client_max_body_size 1024M;
    
    # Web UI static files - served directly by nginx
    location / {
        root /var/www/flipbook/web;
        try_files $uri $uri/ /index.html;
        index index.html;
        
        # Cache static assets
        location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg)$ {
            expires 30d;
            add_header Cache-Control "public, immutable";
        }
    }
    
    # API endpoints - proxy to Node.js JSON API
    location /api/ {
        proxy_pass http://127.0.0.1:3000/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_buffering off;
        client_max_body_size 1024M;
    }
    
    # Queue stats endpoint
    location /queue/ {
        proxy_pass http://127.0.0.1:3000/queue/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
    }
    
    # Health check endpoint
    location /health {
        proxy_pass http://127.0.0.1:3000/health;
        access_log off;
    }
    
    # Cache management endpoints
    location /cache/ {
        proxy_pass http://127.0.0.1:3000/cache/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
    }
    
    # Generated flipbook files (static assets)
    location /output/ {
        alias /var/www/flipbook/output/;
        access_log off;
        expires 1h;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }
}
NGINX_EOF

    # Replace placeholders
    sed -i "s/DOMAIN_NAME_PLACEHOLDER/$DOMAIN_NAME/g" /etc/nginx/sites-available/$DOMAIN_NAME
    sed -i "s/DROPLET_IP_PLACEHOLDER/$DROPLET_IP/g" /etc/nginx/sites-available/$DOMAIN_NAME
fi

# Enable nginx site
ln -sf /etc/nginx/sites-available/$DOMAIN_NAME /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Test nginx configuration
log "Testing nginx configuration..."
if nginx -t; then
    log "✅ Nginx configuration test passed"
else
    error "Nginx configuration test failed"
fi

# Add domain to hosts file
log "Adding $DOMAIN_NAME to /etc/hosts..."
if ! grep -q "$DOMAIN_NAME" /etc/hosts; then
    cp /etc/hosts /etc/hosts.bak
    sed -i "/127.0.0.1 localhost/a 127.0.0.1 $DOMAIN_NAME" /etc/hosts
    log "✅ Added $DOMAIN_NAME to /etc/hosts"
fi

# Start nginx
systemctl start nginx
systemctl enable nginx

# Create systemd service
log "Creating systemd service..."
cat > /etc/systemd/system/flipbook.service << 'EOF'
[Unit]
Description=PDF to FlipBook API Service (WineJS Architecture)
Requires=redis-server.service
After=redis-server.service network-online.target nginx.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/pm2 start /opt/ecosystem.config.js
ExecStop=/usr/bin/pm2 stop all
ExecReload=/usr/bin/pm2 reload all
User=root
Group=root
Restart=on-failure
RestartSec=10
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable flipbook.service
systemctl start flipbook.service

# Wait for services
log "Waiting for services to initialize..."
sleep 10

# Verify services
log "Verifying all services..."
systemctl is-active --quiet nginx || error "Nginx not running"
pm2 list | grep -q flipbook-api || error "FlipBook API not running"
systemctl is-active --quiet redis-server || error "Redis not running"

# Create monitoring script
log "Creating monitoring script..."
cat > /usr/local/bin/monitor-flipbook.sh << 'EOF'
#!/bin/bash
LOG_FILE="/var/log/flipbook-monitor.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Check Redis
if ! systemctl is-active --quiet redis-server; then
    log_message "Redis not running - restarting"
    systemctl restart redis-server
fi

# Check API
if ! pm2 list | grep -q flipbook-api; then
    log_message "API not running - restarting"
    pm2 restart flipbook-api
fi

# Check nginx
if ! systemctl is-active --quiet nginx; then
    log_message "Nginx not running - restarting"
    systemctl restart nginx
fi

# Check queue length
QUEUE_STATS=$(curl -s http://localhost:3000/queue/stats 2>/dev/null)
WAITING=$(echo $QUEUE_STATS | grep -o '"waiting":[0-9]*' | cut -d':' -f2 || echo "0")
if [ "$WAITING" -gt 20 ]; then
    log_message "WARNING: Queue backup! $WAITING waiting jobs"
fi

# Clean temp files
if [ -d /tmp/flipbook-temp ]; then
    find /tmp/flipbook-temp -type d -mmin +60 -exec rm -rf {} + 2>/dev/null
    find /tmp/flipbook-temp/uploads -type f -mmin +60 -exec rm -f {} + 2>/dev/null
    log_message "Monitor complete - Queue: $WAITING waiting"
fi
EOF

chmod +x /usr/local/bin/monitor-flipbook.sh

# Create SSL renewal script
if [ "$SSL_ENABLED" = true ]; then
    log "Creating SSL renewal script..."
    cat > /usr/local/bin/renew-ssl.sh << EOF
#!/bin/bash
LOG_FILE="/var/log/ssl-renewal.log"
DOMAIN="$DOMAIN_NAME"

echo "\$(date): Starting SSL renewal" >> "\$LOG_FILE"

systemctl stop nginx
pm2 stop all
sleep 5

if certbot renew --quiet --standalone; then
    echo "\$(date): ✅ SSL renewal successful" >> "\$LOG_FILE"
else
    echo "\$(date): ❌ SSL renewal failed" >> "\$LOG_FILE"
fi

pm2 start all
systemctl start nginx
EOF

    chmod +x /usr/local/bin/renew-ssl.sh
fi

# Create log rotation
cat > /etc/logrotate.d/flipbook << 'EOF'
/var/log/flipbook-monitor.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
}
EOF

# Create test script
log "Creating test script..."
cat > /opt/test-flipbook.sh << EOF
#!/bin/bash
DOMAIN_NAME="$DOMAIN_NAME"
SSL_ENABLED=$SSL_ENABLED
API_TOKEN="$API_TOKEN"

echo "=== PDF to FlipBook API Test Suite v2.0 (WineJS Architecture) ==="
echo "Domain: $DOMAIN_NAME"
echo "SSL Enabled: $SSL_ENABLED"
if [ -n "$API_TOKEN" ]; then
    echo "Auth: Token required"
else
    echo "Auth: Public access"
fi
echo ""

# Test URLs
TEST_URL="https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf"
PROTOCOL="http"
[ "$SSL_ENABLED" = true ] && PROTOCOL="https"

# Test 1: API Health (JSON)
echo "1. Testing API health (JSON)..."
curl -s "$PROTOCOL://$DOMAIN_NAME/health" | grep -q "OK" && echo "   ✅ API healthy (JSON)" || echo "   ❌ API not healthy"

# Test 2: Web UI (HTML)
echo "2. Testing Web UI (served by nginx)..."
curl -s "$PROTOCOL://$DOMAIN_NAME/" | grep -q "PDF to FlipBook" && echo "   ✅ Web UI accessible (static HTML)" || echo "   ❌ Web UI not accessible"

# Test 3: API Convert endpoint (JSON)
echo "3. Testing API convert endpoint..."
curl -s "$PROTOCOL://$DOMAIN_NAME/api/convert?url=$TEST_URL" | grep -q "success" && echo "   ✅ API convert working" || echo "   ❌ API convert failed"

# Test 4: Queue stats (JSON)
echo "4. Testing queue stats (JSON)..."
curl -s "$PROTOCOL://$DOMAIN_NAME/queue/stats" | grep -q "waiting" && echo "   ✅ Queue stats working" || echo "   ❌ Queue stats failed"

# Test 5: History API (JSON)
echo "5. Testing history API (JSON)..."
curl -s "$PROTOCOL://$DOMAIN_NAME/api/history" | grep -q "history" && echo "   ✅ History API working" || echo "   ❌ History API failed"

echo ""
echo "=== Test Complete ==="
echo ""
echo "Web UI: $PROTOCOL://$DOMAIN_NAME/"
echo "API Examples:"
if [ -n "$API_TOKEN" ]; then
    echo "  Convert: $PROTOCOL://$DOMAIN_NAME/api/convert?url=YOUR_PDF_URL&token=$API_TOKEN"
    echo "  Upload: curl -X POST $PROTOCOL://$DOMAIN_NAME/api/upload -F \"pdf=@document.pdf\" -H \"X-API-Token: $API_TOKEN\""
else
    echo "  Convert: $PROTOCOL://$DOMAIN_NAME/api/convert?url=YOUR_PDF_URL"
    echo "  Upload: curl -X POST $PROTOCOL://$DOMAIN_NAME/api/upload -F \"pdf=@document.pdf\""
fi
echo "  History: $PROTOCOL://$DOMAIN_NAME/api/history"
echo "  Queue:   $PROTOCOL://$DOMAIN_NAME/queue/stats"
echo ""
echo "Architecture: WineJS-style (API serves JSON only, nginx serves static HTML)"
EOF

chmod +x /opt/test-flipbook.sh

# Create quick test
cat > /opt/quick-test.sh << EOF
#!/bin/bash
DOMAIN_NAME="$DOMAIN_NAME"
SSL_ENABLED=$SSL_ENABLED

PROTOCOL="http"
[ "$SSL_ENABLED" = true ] && PROTOCOL="https"

echo "Quick FlipBook Test (WineJS Architecture)"
echo "=========================================="
echo ""

echo "1. Testing API (JSON)..."
curl -s "$PROTOCOL://$DOMAIN_NAME/health" | grep -q "OK" && echo "   ✅ API OK (JSON)" || echo "   ❌ API FAILED"

echo "2. Testing Web UI (HTML served by nginx)..."
curl -s "$PROTOCOL://$DOMAIN_NAME/" | grep -q "PDF to FlipBook" && echo "   ✅ Web UI OK (static HTML)" || echo "   ❌ Web UI FAILED"

echo "3. Testing API endpoints..."
curl -s "$PROTOCOL://$DOMAIN_NAME/queue/stats" | python3 -m json.tool 2>/dev/null | head -5 || curl -s "$PROTOCOL://$DOMAIN_NAME/queue/stats"

echo ""
echo "Architecture:"
echo "  - Web UI:  nginx serving /var/www/flipbook/web/"
echo "  - API:     Node.js on port 3000 (JSON only)"
echo "  - Output:  nginx serving /var/www/flipbook/output/"
echo ""
echo "Web UI: $PROTOCOL://$DOMAIN_NAME/"
echo "API:    $PROTOCOL://$DOMAIN_NAME/api/convert?url=YOUR_PDF_URL"
echo "Upload: curl -X POST $PROTOCOL://$DOMAIN_NAME/api/upload -F \"pdf=@document.pdf\""
EOF

chmod +x /opt/quick-test.sh

# Set up cron jobs
log "Setting up cron jobs..."
crontab -l 2>/dev/null | grep -v "monitor-flipbook.sh" | crontab -
crontab -l 2>/dev/null | grep -v "renew-ssl.sh" | crontab -

(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/monitor-flipbook.sh") | crontab -
if [ "$SSL_ENABLED" = true ]; then
    (crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/renew-ssl.sh") | crontab -
fi

# Run initial test
log "Running initial test..."
if /opt/quick-test.sh; then
    log "✅ Initial test passed!"
else
    warn "Initial test had issues. Check logs above."
fi

# Final output
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      PDF TO FLIPBOOK API v2.0 SETUP COMPLETE!            ║${NC}"
echo -e "${GREEN}║      WineJS Architecture: Pure JSON API + Static Web UI  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
log "Your PDF to FlipBook server is ready!"
echo ""
info "🌐 Web Interface (Static HTML - served by nginx):"
if [ "$SSL_ENABLED" = true ]; then
    echo "  🔒 https://$DOMAIN_NAME/"
else
    echo "  🌐 http://$DOMAIN_NAME/"
fi
echo ""
info "🔌 API Endpoints (JSON only - served by Node.js):"
echo "  • GET  /api/convert?url=PDF_URL    - Convert PDF by URL"
echo "  • POST /api/upload                 - Upload PDF file"
echo "  • GET  /api/history                - View conversion history"
echo "  • GET  /queue/stats                - Queue statistics"
echo "  • POST /cache/clear-all            - Clear all cached flipbooks"
echo ""
info "Architecture (WineJS-style):"
echo "  📁 Web UI:  /var/www/flipbook/web/     - Served by nginx (static)"
echo "  📁 Output:  /var/www/flipbook/output/  - Served by nginx (static)"
echo "  🔧 API:     /opt/flipbook-api/         - Node.js JSON API on port 3000"
echo ""
info "Examples:"
if [ -n "$API_TOKEN" ]; then
    echo "  Web UI: https://$DOMAIN_NAME/?token=$API_TOKEN"
    echo "  API:    https://$DOMAIN_NAME/api/convert?url=https://example.com/doc.pdf&token=$API_TOKEN"
    echo "  Upload: curl -X POST https://$DOMAIN_NAME/api/upload -F \"pdf=@doc.pdf\" -H \"X-API-Token: $API_TOKEN\""
else
    echo "  Web UI: https://$DOMAIN_NAME/"
    echo "  API:    https://$DOMAIN_NAME/api/convert?url=https://example.com/doc.pdf"
    echo "  Upload: curl -X POST https://$DOMAIN_NAME/api/upload -F \"pdf=@document.pdf\""
fi
echo ""
info "Management:"
echo "  /opt/quick-test.sh             # Quick test"
echo "  /opt/test-flipbook.sh          # Full test"
echo "  pm2 logs flipbook-api          # View API logs"
echo "  pm2 restart flipbook-api       # Restart API service"
echo "  systemctl restart nginx        # Restart web server"
echo ""
info "Output Location:"
echo "  HTML: https://$DOMAIN_NAME/output/flipbook_HASH/filename_flipbook.html"
echo "  ZIP:  https://$DOMAIN_NAME/output/flipbook_HASH.zip"

# Final restart
log "Performing final restart..."
systemctl restart nginx
pm2 restart all

echo ""
log "✨ Setup complete! Your PDF to FlipBook server is ready to use!"
log "🌐 Open https://$DOMAIN_NAME/ in your browser to start converting PDFs!"
log "🔧 API is pure JSON at https://$DOMAIN_NAME/api/convert?url=PDF_URL"
log "📁 Web UI is static HTML served by nginx (fast!)"
echo ""

# Display architecture summary
echo -e "${CYAN}Architecture Summary (WineJS-style):${NC}"
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│  nginx (port 443/80)                                        │"
echo "│    ├── /                 → /var/www/flipbook/web/ (static)   │"
echo "│    ├── /api/*            → http://127.0.0.1:3000/api/       │"
echo "│    ├── /queue/*          → http://127.0.0.1:3000/queue/     │"
echo "│    ├── /health           → http://127.0.0.1:3000/health     │"
echo "│    ├── /cache/*          → http://127.0.0.1:3000/cache/     │"
echo "│    └── /output/*         → /var/www/flipbook/output/        │"
echo "│                                                              │"
echo "│  Node.js API (port 3000) - Pure JSON                         │"
echo "│    ├── /api/convert      (JSON)                             │"
echo "│    ├── /api/upload       (JSON)                             │"
echo "│    ├── /api/history      (JSON)                             │"
echo "│    ├── /queue/stats      (JSON)                             │"
echo "│    └── /health           (JSON)                             │"
echo "└─────────────────────────────────────────────────────────────┘"