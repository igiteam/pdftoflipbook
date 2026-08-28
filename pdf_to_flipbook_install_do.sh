#!/bin/bash

# PDF to FlipBook API - Standalone Service v2.0 with Enhanced Features (WineJS Architecture)
# API server: JSON only on port 3000
# Web UI: Static HTML served by nginx with TABLE VIEW
# Features: Weserv thumbnails, Progress tracking, Favicons, Table View, OG Image Generation
# Usage: curl -sL https://cdn.gitgpt.chat/rtx/sh/flipbook-complete.sh | sudo bash

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
    
    for cmd in dig host curl ss docker; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing_deps+=($cmd)
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        info "Installing missing dependencies: ${missing_deps[*]}"
        apt-get update -qq
        apt-get install -y -qq dnsutils curl iproute2 docker.io >/dev/null 2>&1
        systemctl start docker 2>/dev/null || true
        systemctl enable docker 2>/dev/null || true
    fi
}

# Display banner
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║         PDF TO FLIPBOOK - Magazine Edition v2.1                  ║"
echo "║         Pure JSON API + Static Web UI + Table View               ║"
echo "║         + Weserv Thumbnails + Progress Tracking + Favicons       ║"
echo "║         + OG Image Generation (@vercel/og)                       ║"
echo "║   Web UI: https://your.domain/ - Drag & drop PDF                 ║"
echo "║   API:    https://your.domain/api/convert?url=...                ║"
echo "║   Optional auth: &token=your_secret_key                          ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
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
    get_input "Enter your domain (e.g., flipbook.gitgpt.chat)" "flipbook.gitgpt.chat" DOMAIN_NAME
    
    if validate_domain "$DOMAIN_NAME"; then
        break
    else
        warn "Invalid domain format. Please enter a full domain (e.g., flipbook.gitgpt.chat)"
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

# Optional Discord webhooks
echo ""
info "Optional: Set up Discord webhook notifications"
info "When conversion completes, a notification will be sent to Discord"
info "You can add multiple webhooks separated by commas"
info "Example: https://discord.com/api/webhooks/123/abc,https://discord.com/api/webhooks/456/def"
read -p "Discord Webhook URLs (optional, comma-separated): " DISCORD_WEBHOOKS

if [ -n "$DISCORD_WEBHOOKS" ]; then
    log "Discord webhooks configured: $(echo $DISCORD_WEBHOOKS | tr ',' '\n' | wc -l) webhook(s)"
else
    log "Discord webhooks: NOT configured"
fi

# After domain input and before starting installation, add this:

echo ""
info "⚙️ Performance Configuration"
echo "-------------------------------------"

# Default RAM in MB (adjust based on droplet size)
DETECTED_RAM=$(free -m | awk '/^Mem:/{print $2}')
if [ "$DETECTED_RAM" -lt 2048 ]; then
    DEFAULT_RAM="1024"
    RAM_WARNING="⚠️ Low memory detected (${DETECTED_RAM}MB). Consider upgrading for better performance."
elif [ "$DETECTED_RAM" -lt 4096 ]; then
    DEFAULT_RAM="2048"
    RAM_WARNING="ℹ️ Standard memory (${DETECTED_RAM}MB). Good for most PDFs."
else
    DEFAULT_RAM="3072"
    RAM_WARNING="✅ High memory (${DETECTED_RAM}MB). Great for large comics!"
fi

echo -e "${BLUE}📊 Detected RAM: ${DETECTED_RAM}MB${NC}"
echo -e "${YELLOW}${RAM_WARNING}${NC}"
echo ""
info "Node.js memory limit affects how many pages can be processed at once"
info "Higher limit = better for large PDFs/comics, but leave room for system"
echo ""
read -p "Node.js memory limit in MB (1024, 2048, 3072, 4096) [${DEFAULT_RAM}]: " NODE_MEMORY

# Validate input
if [[ ! "$NODE_MEMORY" =~ ^[0-9]+$ ]] || [ "$NODE_MEMORY" -lt 512 ] || [ "$NODE_MEMORY" -gt 4096 ]; then
    NODE_MEMORY=$DEFAULT_RAM
    warn "Invalid input. Using default: ${NODE_MEMORY}MB"
fi

# Calculate safe limit (leave 1GB for OS)
MAX_SAFE=$((DETECTED_RAM - 1024))
if [ "$NODE_MEMORY" -gt "$MAX_SAFE" ] && [ "$MAX_SAFE" -gt 512 ]; then
    warn "Requested ${NODE_MEMORY}MB but only ${MAX_SAFE}MB is safe. Adjusting to ${MAX_SAFE}MB"
    NODE_MEMORY=$MAX_SAFE
fi

log "Node.js memory limit: ${NODE_MEMORY}MB"

log "Starting PDF to FlipBook API Setup v2.1 (Complete Edition with OG Images)..."
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

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    log "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl start docker
    systemctl enable docker
fi

# Start Weserv container for dynamic thumbnails
log "Starting Weserv container for dynamic image processing..."
docker rm -f weserv 2>/dev/null || true
docker run -d \
    --name weserv \
    --restart unless-stopped \
    -p 8080:80 \
    -e MEMORY_LIMIT=256M \
    -v /var/www/flipbook/output:/var/www/flipbook/output:ro \
    ghcr.io/weserv/images:5.x
log "✅ Weserv running on port 8080"

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

# ============= INSTALL NODE.JS 22 (REQUIRED FOR @vercel/og) =============
log "Installing Node.js 22.x (required for modern OG image generation)..."
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y -qq nodejs

# Verify Node.js version
NODE_VERSION=$(node -v)
log "Node.js version: $NODE_VERSION"

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

# Install dependencies (including OG generation)
log "Installing Node.js dependencies..."
npm init -y
npm install express bull ioredis archiver@5.3.2 pdfinfo multer axios @vercel/og react react-dom

# Create editable OG HTML template (kept as reference, but not used in new design)
log "Creating OG template file..."
cat > $FLIPBOOK_DIR/og-template.html << 'OG_HTML'
<div style="
    display: flex;
    width: 100%;
    height: 100%;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
    padding: 60px;
    font-family: Georgia, serif;
">
    <div style="
        background: rgba(0,0,0,0.7);
        backdrop-filter: blur(10px);
        border-radius: 32px;
        padding: 48px;
        text-align: center;
        max-width: 85%;
    ">
        {{#if THUMBNAIL}}
        <img src="{{THUMBNAIL}}" style="width:120px;height:120px;border-radius:60px;margin-bottom:24px;border:3px solid #667eea;">
        {{else}}
        <div style="font-size:80px;margin-bottom:24px;">📖</div>
        {{/if}}
        
        <h1 style="font-size:48px;color:white;margin-bottom:16px;">{{TITLE}}</h1>
        
        <div style="display:flex;gap:24px;color:#aaa;font-size:20px;justify-content:center;">
            <span>📄 {{PAGE_COUNT}} pages</span>
            <span>✨ Flipbook</span>
        </div>
        
        <div style="margin-top:32px;color:#667eea;font-size:14px;">{{DOMAIN}}</div>
    </div>
</div>
OG_HTML

log "✅ OG template created at $FLIPBOOK_DIR/og-template.html"

# Create OG image generator module -  blurred background
cat > $FLIPBOOK_DIR/og-generator.js << 'OG_GEN'
const { ImageResponse } = require('@vercel/og');
const fs = require('fs');
const crypto = require('crypto');
const React = require('react');

function getOGCacheKey(flipbookId) {
    return crypto.createHash('md5').update(`${flipbookId}`).digest('hex');
}

async function generateOGImage(flipbook, domain) {
    const title = (flipbook.display_title || flipbook.title || 'Flipbook').substring(0, 60);
    const pageCount = flipbook.page_count || 0;
    const firstPageUrl = `https://${domain}/output/flipbook_${flipbook.id}/${flipbook.title}_page_1.png`;
    
    // Blurred background + clear center image
    const element = React.createElement('div', {
        style: {
            display: 'flex',
            width: '100%',
            height: '100%',
            position: 'relative',
            alignItems: 'center',
            justifyContent: 'center',
            fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif'
        }
    },
        // Blurred background (enlarged first page)
        React.createElement('div', {
            style: {
                position: 'absolute',
                top: '-10%',
                left: '-10%',
                width: '120%',
                height: '120%',
                backgroundImage: `url(${firstPageUrl})`,
                backgroundSize: 'cover',
                backgroundPosition: 'center',
                filter: 'blur(20px)',
                opacity: 0.9
            }
        }),
        // Dark overlay for text readability
        React.createElement('div', {
            style: {
                position: 'absolute',
                top: 0,
                left: 0,
                width: '100%',
                height: '100%',
                background: 'rgba(0, 0, 0, 0.5)'
            }
        }),
        // Content container
        React.createElement('div', {
            style: {
                position: 'relative',
                zIndex: 2,
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                justifyContent: 'center',
                width: '80%',
                height: '85%',
                textAlign: 'center'
            }
        },
            // Actual first page image (clear, not blurred)
            React.createElement('img', {
                src: firstPageUrl,
                style: {
                    maxWidth: '70%',
                    maxHeight: '85%',
                    objectFit: 'contain',
                }
            }),
            // Title
            React.createElement('div', {
                style: {
                    fontSize: '28px',
                    fontWeight: 'bold',
                    color: 'white',
                    marginTop: '20px',
                    textShadow: '0 2px 4px rgba(0,0,0,0.5)'
                }
            }, title),
            // Metadata
            React.createElement('div', {
                style: {
                    display: 'flex',
                    gap: '24px',
                    marginTop: '12px',
                    color: '#ddd',
                    fontSize: '16px',
                    textShadow: '0 1px 2px rgba(0,0,0,0.5)'
                }
            },
                React.createElement('span', null, '📄 ' + pageCount + ' pages'),
                React.createElement('span', null, '📰 Flipbook')
            )
        )
    );
    
    const response = new ImageResponse(element, { 
        width: 1200, 
        height: 630, 
        emoji: 'twemoji',
        debug: false 
    });
    const buffer = await response.arrayBuffer();
    return {
        buffer: Buffer.from(buffer),
        cacheKey: getOGCacheKey(flipbook.id),
        contentType: 'image/png'
    };
}

module.exports = { generateOGImage, getOGCacheKey };
OG_GEN


log "✅ OG generator created"

# Create main server with all enhanced features
log "Creating flipbook API server with enhanced features (progress tracking, thumbnails, OG images, etc.)..."

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
const axios = require('axios');
const execPromise = util.promisify(exec);

const { generateOGImage, getOGCacheKey } = require('./og-generator');

const app = express();
const PORT = process.env.PORT || 3000;
const TEMP_DIR = '/tmp/flipbook-temp';
const OUTPUT_DIR = '/var/www/flipbook/output';
const API_TOKEN = process.env.API_TOKEN || '';
const DOMAIN = process.env.DOMAIN_NAME || '';
// Discord webhook configuration - Add this near other constants
const DISCORD_WEBHOOKS = (process.env.DISCORD_WEBHOOKS || '').split(',').filter(url => url.trim());

// IMPORTANT: No static file serving! That's handled by nginx
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Progress tracking map
const jobProgress = new Map();

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


// Generate thumbnail URL using Weserv (on-demand, no storage)
function getThumbnailUrl(cacheKey, pageCount, pdfName) {
    if (!DOMAIN || !pdfName) return null;
    return `https://${DOMAIN}/weserv/?url=https://${DOMAIN}/output/flipbook_${cacheKey}/${pdfName}_page_1.png&w=512&h=512&fit=cover`;
}

// ============= DISCORD WEBHOOK FUNCTIONS =============
// Send Discord notification when conversion completes
async function sendDiscordNotification(flipbook, jobId, domain) {
    if (DISCORD_WEBHOOKS.length === 0) return;
    
    const title = flipbook.display_title || flipbook.title || 'PDF Flipbook';
    const pageCount = flipbook.page_count || 0;
    const htmlUrl = `https://${domain}${flipbook.html_url}`;
    const zipUrl = `https://${domain}${flipbook.zip_url}`;
    const thumbnailUrl = flipbook.thumbnail_url || '';
    const source = flipbook.source || 'unknown';
    const timestamp = new Date().toISOString();
    
    // Create rich embed for Discord
    const embed = {
        title: `✅ Flipbook Ready: ${title.substring(0, 256)}`,
        description: `Your PDF has been successfully converted to an interactive flipbook!`,
        color: 0x667eea,
        fields: [
            {
                name: "📄 Pages",
                value: `${pageCount}`,
                inline: true
            },
            {
                name: "📁 Source",
                value: source === 'upload' ? 'File Upload' : 'URL',
                inline: true
            },
            {
                name: "🆔 Job ID",
                value: `\`${jobId}\``,
                inline: false
            },
            {
                name: "🔗 Flipbook Link",
                value: `[Click to View](${htmlUrl})`,
                inline: true
            },
            {
                name: "📦 Download ZIP",
                value: `[Download Archive](${zipUrl})`,
                inline: true
            }
        ],
        footer: {
            text: `PDF to FlipBook • Converted at ${new Date().toLocaleString()}`
        },
        timestamp: timestamp
    };
    
    // Add thumbnail if available
    if (thumbnailUrl) {
        embed.thumbnail = { url: thumbnailUrl };
    }
    
    // Add source URL if it was a URL conversion
    if (source === 'url' && flipbook.source_url) {
        embed.fields.push({
            name: "📎 Source URL",
            value: `[${flipbook.source_url.substring(0, 100)}](${flipbook.source_url})`,
            inline: false
        });
    }
    
    const payload = {
        username: "PDF to FlipBook",
        avatar_url: "https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/pdf_flipbook.png",
        embeds: [embed],
        content: `🎉 **New flipbook created!** ${title}`
    };
    
    // Send to all webhooks
    const results = [];
    for (const webhookUrl of DISCORD_WEBHOOKS) {
        try {
            const response = await fetch(webhookUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });
            
            if (response.ok) {
                console.log(`[Discord] Notification sent successfully to ${webhookUrl.substring(0, 50)}...`);
                results.push({ success: true, url: webhookUrl });
            } else {
                console.error(`[Discord] Failed to send to ${webhookUrl}: ${response.status} ${response.statusText}`);
                results.push({ success: false, url: webhookUrl, error: `HTTP ${response.status}` });
            }
        } catch (error) {
            console.error(`[Discord] Error sending to ${webhookUrl}:`, error.message);
            results.push({ success: false, url: webhookUrl, error: error.message });
        }
    }
    
    return results;
}

// Send error notification to Discord
async function sendDiscordErrorNotification(error, context, domain) {
    if (DISCORD_WEBHOOKS.length === 0) return;
    
    const embed = {
        title: "❌ Flipbook Conversion Failed",
        description: `An error occurred during PDF conversion.`,
        color: 0xef4444,
        fields: [
            {
                name: "Error",
                value: `\`\`\`${error.message.substring(0, 500)}\`\`\``,
                inline: false
            },
            {
                name: "Context",
                value: context,
                inline: false
            },
            {
                name: "Timestamp",
                value: new Date().toLocaleString(),
                inline: false
            }
        ],
        footer: {
            text: "PDF to FlipBook • Error Notification"
        },
        timestamp: new Date().toISOString()
    };
    
    const payload = {
        username: "PDF to FlipBook (Error)",
        avatar_url: "https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/pdf_flipbook.png",
        embeds: [embed]
    };
    
    for (const webhookUrl of DISCORD_WEBHOOKS) {
        try {
            await fetch(webhookUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });
            console.log(`[Discord] Error notification sent to ${webhookUrl.substring(0, 50)}...`);
        } catch (err) {
            console.error(`[Discord] Failed to send error notification:`, err.message);
        }
    }
}
// ============= END DISCORD WEBHOOK FUNCTIONS =============

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
    
    jobProgress.set(jobId, { percent: 0, stage: 'starting' });
    
    try {
        let pdfPath;
        
        if (source === 'upload' && uploadedPdfPath && fs.existsSync(uploadedPdfPath)) {
            pdfPath = uploadedPdfPath;
            console.log(`[Job ${jobId}] Using uploaded file: ${path.basename(pdfPath)}`);
            jobProgress.set(jobId, { percent: 10, stage: 'uploaded' });
        } else {
            // Download PDF from URL
            console.log(`[Job ${jobId}] Downloading PDF from URL...`);
            pdfPath = path.join(tempDir, 'input.pdf');
            jobProgress.set(jobId, { percent: 5, stage: 'downloading' });
            
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
        jobProgress.set(jobId, { percent: 20, stage: 'analyzing', totalPages: pageCount });
        
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
            const percent = 20 + Math.floor((i / pageCount) * 70);
            jobProgress.set(jobId, { percent, stage: 'converting', currentPage: i, totalPages: pageCount });
            await execPromise(`pdftoppm -png -cropbox -f ${i} -singlefile "${pdfPath}" "${path.join(outputDir, `${pdfName}_page_${i}`)}"`);
            console.log(`[Job ${jobId}] Converted page ${i}/${pageCount}`);
        }
        
        // Generate thumbnail URL (Weserv on-demand)
        const thumbnailUrl = getThumbnailUrl(cacheKey, pageCount, pdfName);
        
        // Generate HTML flipbook with OG meta tags
        console.log(`[Job ${jobId}] Generating HTML flipbook with OG images...`);
        const html = generateFlipbookHTML(pdfName, pageCount, thumbnailUrl, cacheKey, DOMAIN);
        const htmlPath = path.join(outputDir, `${pdfName}_flipbook.html`);
        fs.writeFileSync(htmlPath, html);
        
        // Create ZIP archive
        console.log(`[Job ${jobId}] Creating ZIP archive...`);
        const zipPath = path.join(OUTPUT_DIR, `flipbook_${cacheKey}.zip`);
        await createZip(outputDir, zipPath);
        
        // Add to history with thumbnail_url
        const historyEntry = {
            id: cacheKey,
            title: pdfName,
            page_count: pageCount,
            created_at: new Date().toISOString(),
            timestamp: Math.floor(Date.now() / 1000),
            html_url: `/output/flipbook_${cacheKey}/${pdfName}_flipbook.html`,
            zip_url: `/output/flipbook_${cacheKey}.zip`,
            thumbnail_url: thumbnailUrl,
            source: source || (pdfUrl ? 'url' : 'unknown'),
            source_url: pdfUrl || null,  // Add this line
            original_name: originalName || pdfName,
            display_title: originalName || pdfName
        };
        conversionHistory.unshift(historyEntry);
        saveHistory();
        
        // Send Discord notification
        if (DISCORD_WEBHOOKS.length > 0) {
            try {
                const notificationResult = await sendDiscordNotification(historyEntry, jobId, DOMAIN);
                console.log(`[Discord] Notifications sent: ${notificationResult.filter(r => r.success).length}/${notificationResult.length} successful`);
            } catch (discordError) {
                console.error('[Discord] Failed to send notification:', discordError.message);
                // Don't fail the job if Discord notification fails
            }
        }

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
        
        jobProgress.set(jobId, { percent: 100, stage: 'complete' });
        console.log(`[Job ${jobId}] Completed successfully`);
        
        return {
            success: true,
            title: pdfName,
            page_count: pageCount,
            html_url: `/output/flipbook_${cacheKey}/${pdfName}_flipbook.html`,
            zip_url: `/output/flipbook_${cacheKey}.zip`,
            thumbnail_url: thumbnailUrl,
            processing_time_ms: Date.now() - timestamp
        };
        
    } catch (error) {
        console.error(`[Job ${jobId}] Error: ${error.message}`);
        jobProgress.set(jobId, { percent: 0, stage: 'error', error: error.message });
        
        // Send Discord error notification
        if (DISCORD_WEBHOOKS.length > 0) {
            await sendDiscordErrorNotification(error, `PDF: ${pdfUrl || originalName || 'unknown'}`, DOMAIN);
        }
        
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

function generateFlipbookHTML(title, pageCount, thumbnailUrl, cacheKey, domain) {
    const safeTitle = title.replace(/'/g, "\\'").replace(/"/g, '\\"');
    const iconUrl = thumbnailUrl || `data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'%3E%3Crect width='100' height='100' fill='%23667eea'/%3E%3Ctext x='50' y='70' text-anchor='middle' fill='white' font-size='60'%3E📖%3C/text%3E%3C/svg%3E`;
    const pageCountNum = pageCount || 0;
    
    // OG image URLs via Weserv for caching
    const ogImageBase = `https://${domain}`;
    const ogImageWeserv = `${ogImageBase}/weserv/?url=${ogImageBase}/api/og/${cacheKey}&w=1200&h=630`;
    const ogImageDirect = `${ogImageBase}/api/og/${cacheKey}`;
    
    return '<!DOCTYPE html>\n\
<html>\n\
<head>\n\
    <meta charset="UTF-8">\n\
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">\n\
    <meta name="apple-mobile-web-app-capable" content="yes">\n\
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">\n\
    \n\
    <!-- Favicons -->\n\
    <link rel="icon" type="image/png" href="' + iconUrl + '">\n\
    <link rel="apple-touch-icon" href="' + iconUrl + '" sizes="180x180">\n\
    \n\
    <!-- Open Graph / Social Media Meta Tags -->\n\
    <meta property="og:title" content="' + safeTitle + ' - Interactive Flipbook">\n\
    <meta property="og:description" content="Interactive flipbook magazine with ' + pageCountNum + ' pages. Read online with realistic page-turning effects.">\n\
    <meta property="og:image" content="' + ogImageWeserv + '">\n\
    <meta property="og:image:width" content="1200">\n\
    <meta property="og:image:height" content="630">\n\
    <meta property="og:image:alt" content="' + safeTitle + ' flipbook cover">\n\
    <meta property="og:type" content="website">\n\
    <meta property="og:url" content="https://' + domain + '/output/flipbook_' + cacheKey + '/' + safeTitle + '_flipbook.html">\n\
    <meta property="og:site_name" content="PDF to FlipBook">\n\
    \n\
    <!-- Twitter Card -->\n\
    <meta name="twitter:card" content="summary_large_image">\n\
    <meta name="twitter:title" content="' + safeTitle + ' - FlipBook">\n\
    <meta name="twitter:description" content="Interactive flipbook magazine with ' + pageCountNum + ' pages">\n\
    <meta name="twitter:image" content="' + ogImageWeserv + '">\n\
    <meta name="twitter:image:alt" content="' + safeTitle + ' flipbook preview">\n\
    \n\
    <!-- Additional OG tags for better sharing -->\n\
    <meta property="og:locale" content="en_US">\n\
    \n\
    <title>' + safeTitle + ' - FlipBook</title>\n\
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
            font-family: \'Segoe UI\', Arial, sans-serif;\n\
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
        const totalPages = ' + pageCountNum + ';\n\
        const title = \'' + safeTitle + '\';\n\
        \n\
        let currentPageNumber = 1;\n\
        let turnInstance = null;\n\
        let isRebuilding = false;\n\
        let loadedPages = new Set();\n\
        let loadingPages = new Set();\n\
        let preloadQueue = [];\n\
        \n\
        function getSavedPage() {\n\
            const storageKey = \'flipbook_last_page_\' + title;\n\
            const saved = localStorage.getItem(storageKey);\n\
            if (saved && !isNaN(saved) && saved >= 1 && saved <= totalPages) {\n\
                return parseInt(saved);\n\
            }\n\
            return 1;\n\
        }\n\
\n\
        function savePage(pageNum) {\n\
            const storageKey = \'flipbook_last_page_\' + title;\n\
            localStorage.setItem(storageKey, pageNum);\n\
        }\n\
        \n\
        function createMagazine() {\n\
            const magazine = $(\'#magazine\');\n\
            magazine.empty();\n\
            for (let i = 1; i <= totalPages; i++) {\n\
                const pageDiv = $(\'<div>\')\n\
                    .addClass(\'turn-page loading\')\n\
                    .attr(\'data-page\', i)\n\
                    .attr(\'data-loaded\', \'false\');\n\
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
                const pageDiv = $(\'.turn-page[data-page=\"\' + pageNum + \'\"]\');\n\
                if (!pageDiv.length) {\n\
                    resolve();\n\
                    return;\n\
                }\n\
                if (pageDiv.attr(\'data-loaded\') === \'true\') {\n\
                    loadedPages.add(pageNum);\n\
                    resolve();\n\
                    return;\n\
                }\n\
                loadingPages.add(pageNum);\n\
                const img = new Image();\n\
                const imgPath = title + \'_page_\' + pageNum + \'.png\';\n\
                img.onload = function () {\n\
                    pageDiv.css(\'background-image\', \'url(\' + imgPath + \')\');\n\
                    pageDiv.removeClass(\'loading\');\n\
                    pageDiv.attr(\'data-loaded\', \'true\');\n\
                    loadedPages.add(pageNum);\n\
                    loadingPages.delete(pageNum);\n\
                    if (priority) console.log(\'[Priority] Page \' + pageNum + \' loaded\');\n\
                    resolve();\n\
                };\n\
                img.onerror = function () {\n\
                    pageDiv.css(\'background-image\', \'url(\\\'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="100%25" height="100%25"%3E%3Crect width="100%25" height="100%25" fill="%23333"/%3E%3Ctext x="50%25" y="50%25" text-anchor="middle" fill="%23666" font-size="20"%3EPage \' + pageNum + \'%3C/text%3E%3C/svg%3E\\\')\');\n\
                    pageDiv.removeClass(\'loading\');\n\
                    pageDiv.attr(\'data-loaded\', \'error\');\n\
                    loadingPages.delete(pageNum);\n\
                    console.warn(\'Failed to load page \' + pageNum + \': \' + imgPath);\n\
                    resolve();\n\
                };\n\
                img.src = imgPath;\n\
            });\n\
        }\n\
        \n\
        function preloadNearbyPages(currentPage, displayMode) {\n\
            let pagesToPreload = [];\n\
            if (displayMode === \'single\') {\n\
                pagesToPreload = [currentPage + 1, currentPage + 2, currentPage + 3, currentPage + 4, currentPage + 5, currentPage - 1, currentPage - 2];\n\
            } else {\n\
                pagesToPreload = [currentPage + 1, currentPage + 2, currentPage + 3, currentPage + 4, currentPage - 1, currentPage - 2];\n\
            }\n\
            const pagesToLoad = pagesToPreload.filter(pageNum => {\n\
                return pageNum >= 1 && pageNum <= totalPages && !loadedPages.has(pageNum) && !loadingPages.has(pageNum);\n\
            });\n\
            if (pagesToLoad.length > 0) {\n\
                if (displayMode === \'single\' && currentPage + 1 <= totalPages && !loadedPages.has(currentPage + 1)) {\n\
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
            const isLandscape = window.matchMedia(\'(orientation: landscape)\').matches;\n\
            const displayMode = isLandscape ? \'double\' : \'single\';\n\
            let pageToRestore = currentPageNumber;\n\
            if (pageToRestore < 1) pageToRestore = 1;\n\
            if (pageToRestore > totalPages) pageToRestore = totalPages;\n\
            if (turnInstance) {\n\
                try { $(\'#magazine\').turn(\'destroy\'); } catch (e) { console.log(\'Destroy error:\', e); }\n\
            }\n\
            setTimeout(() => {\n\
                $(\'#magazine\').turn({\n\
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
                            const currentDisplayMode = $(this).turn(\'display\');\n\
                            const visiblePages = $(this).turn(\'view\');\n\
                            visiblePages.forEach(pageNum => { if (pageNum > 0 && pageNum <= totalPages) loadPageImage(pageNum); });\n\
                            preloadNearbyPages(page, currentDisplayMode);\n\
                        },\n\
                        first: function () {\n\
                            const firstPages = $(this).turn(\'view\');\n\
                            firstPages.forEach(pageNum => { if (pageNum > 0 && pageNum <= totalPages) loadPageImage(pageNum); });\n\
                            const currentDisplayMode = $(this).turn(\'display\');\n\
                            preloadNearbyPages(pageToRestore, currentDisplayMode);\n\
                        },\n\
                        missing: function (e, pages) {\n\
                            for (let i = 0; i < pages.length; i++) {\n\
                                if (pages[i] >= 1 && pages[i] <= totalPages) loadPageImage(pages[i], true);\n\
                            }\n\
                        }\n\
                    }\n\
                });\n\
                turnInstance = $(\'#magazine\');\n\
                isRebuilding = false;\n\
                console.log(\'Flip book initialized: \' + displayMode + \' mode, page \' + pageToRestore);\n\
            }, 50);\n\
        }\n\
        \n\
        createMagazine();\n\
        \n\
        async function initialPreload() {\n\
            for (let i = 1; i <= 6; i++) {\n\
                if (i <= totalPages) await loadPageImage(i, true);\n\
            }\n\
            console.log(\'Initial preload complete\');\n\
        }\n\
        \n\
        currentPageNumber = getSavedPage();\n\
        initialPreload();\n\
        $(window).ready(function () { initFlipBook(); });\n\
        \n\
        $(window).on(\'orientationchange\', function () {\n\
            if (turnInstance) {\n\
                try {\n\
                    const currentView = turnInstance.turn(\'view\');\n\
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
        $(window).on(\'resize\', function () {\n\
            clearTimeout(resizeTimer);\n\
            resizeTimer = setTimeout(() => {\n\
                if (turnInstance) {\n\
                    try {\n\
                        const currentView = turnInstance.turn(\'view\');\n\
                        if (currentView && currentView.length) currentPageNumber = currentView[0] || currentPageNumber;\n\
                    } catch (e) { }\n\
                    const isLandscape = window.matchMedia(\'(orientation: landscape)\').matches;\n\
                    const displayMode = isLandscape ? \'double\' : \'single\';\n\
                    if (turnInstance.turn(\'display\') !== displayMode) {\n\
                        setTimeout(() => {\n\
                            createMagazine();\n\
                            loadedPages.clear();\n\
                            loadingPages.clear();\n\
                            preloadQueue = [];\n\
                            initFlipBook();\n\
                            initialPreload();\n\
                        }, 100);\n\
                    } else {\n\
                        try { turnInstance.turn(\'resize\'); } catch (e) { }\n\
                    }\n\
                }\n\
            }, 200);\n\
        });\n\
        \n\
        $(window).bind(\'keydown\', function (e) {\n\
            if (e.keyCode == 37) { $(\'#magazine\').turn(\'previous\'); e.preventDefault(); }\n\
            else if (e.keyCode == 39) { $(\'#magazine\').turn(\'next\'); e.preventDefault(); }\n\
        });\n\
        \n\
        document.body.addEventListener(\'touchmove\', function (e) {\n\
            if (e.target === document.body || e.target === document.documentElement) e.preventDefault();\n\
        }, { passive: false });\n\
        \n\
        document.body.addEventListener(\'touchend\', function () {\n\
            setTimeout(() => {\n\
                if (turnInstance) {\n\
                    try {\n\
                        const currentView = turnInstance.turn(\'view\');\n\
                        if (currentView && currentView.length) {\n\
                            currentPageNumber = currentView[0] || currentPageNumber;\n\
                            savePage(currentPageNumber);\n\
                        }\n\
                    } catch (e) { }\n\
                }\n\
            }, 100);\n\
        });\n\
        \n\
        console.log(\'Flip book initialized with \' + totalPages + \' pages (aggressive preloading enabled)\');\n\
        console.log(\'Next page is preloaded before you flip for smooth transitions\');\n\
    </script>\n\
\n\
    <script>\n\
        (function () {\n\
            let pageScrollDragging = false;\n\
            let pageTrackStartY = 0;\n\
            let pageTrackStartScroll = 0;\n\
            let currentTotalPages = ' + pageCountNum + ';\n\
            let hideTimeout = null;\n\
            let activeTimeout = null;\n\
\n\
            function getSavedPage() {\n\
                const storageKey = \'flipbook_last_page_\' + title;\n\
                const saved = localStorage.getItem(storageKey);\n\
                if (saved && !isNaN(saved) && saved >= 1 && saved <= currentTotalPages) {\n\
                    return parseInt(saved);\n\
                }\n\
                return 1;\n\
            }\n\
\n\
            function savePage(pageNum) {\n\
                const storageKey = \'flipbook_last_page_\' + title;\n\
                localStorage.setItem(storageKey, pageNum);\n\
            }\n\
\n\
            function createScrollOverlay() {\n\
                if (document.getElementById(\'pageScrollOverlay\')) return;\n\
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
                        background: url(\'https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/ribbon.png\') repeat-y center top / 100% auto;\n\
                        width: 48px;\n\
                        height: 85vh;\n\
                        max-height: 85%;\n\
                        display: flex;\n\
                        align-items: center;\n\
                        justify-content: center;\n\
                        white-space: nowrap;\n\
                        box-shadow: 2px 2px 8px rgba(0,0,0,0.3);\n\
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
                        font-family: \'Georgia\', \'Times New Roman\', serif;\n\
                        font-size: 12px;\n\
                        font-weight: normal;\n\
                        font-style: italic;\n\
                        color: #fff8e7;\n\
                        background: url(\'https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/ribbon2.png\') no-repeat center / 100% 100%;\n\
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
                        <span style="font-family: monospace; font-style: normal; font-weight: bold;"></span>${getSavedPage()} / ${currentTotalPages}\n\
                    </div>\n\
                    \n\
                    <div id="pageSliderContainer" style="\n\
                        position: relative;\n\
                        width: 32px;\n\
                        height: 85vh;\n\
                        max-height: 85%;\n\
                        background: transparent;\n\
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
                            height: 88vh;\n\
                            max-height: 88%;\n\
                            overflow: hidden;\n\
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
                document.body.insertAdjacentHTML(\'beforeend\', overlayHTML);\n\
                updateOverlayPosition();\n\
            }\n\
\n\
            function updateOverlayPosition() {\n\
                const overlay = document.getElementById(\'pageScrollOverlay\');\n\
                if (!overlay) return;\n\
\n\
                const isLandscape = window.matchMedia(\'(orientation: landscape)\').matches;\n\
                const displayMode = isLandscape ? \'double\' : \'single\';\n\
                const isIPad = /iPad|Macintosh/.test(navigator.userAgent) && \'ontouchend\' in document;\n\
\n\
                if (displayMode === \'single\') {\n\
                    if (isIPad) {\n\
                        overlay.style.left = \'15px\';\n\
                    } else {\n\
                        overlay.style.left = \'0px\';\n\
                    }\n\
                    overlay.style.transform = \'translateX(0)\';\n\
                } else {\n\
                    overlay.style.left = \'50%\';\n\
                    overlay.style.transform = \'translateX(-50%)\';\n\
                }\n\
            }\n\
\n\
            function showOverlay(duration) { duration = duration || 3000; const o=document.getElementById(\'pageScrollOverlay\'); if(o){o.style.opacity=\'1\';if(hideTimeout)clearTimeout(hideTimeout);hideTimeout=setTimeout(function(){if(o&&!pageScrollDragging)o.style.opacity=\'0\';},duration);} }\n\
            function showDisplay(duration) { duration = duration || 3000; const d=document.getElementById(\'pageDisplayCenter\'); if(d){d.style.opacity=\'1\';if(activeTimeout)clearTimeout(activeTimeout);activeTimeout=setTimeout(function(){if(d&&!pageScrollDragging)d.style.opacity=\'0\';},duration);} }\n\
            function updatePageDisplay(pageNum) { const d=document.getElementById(\'pageDisplayCenter\'); if(d){d.innerHTML=\'<span style="font-family:monospace;font-style:normal;font-weight:bold;"></span>\' + pageNum + \'/\' + currentTotalPages; savePage(pageNum); showDisplay();} }\n\
\n\
            function createPageNotches() {\n\
                const track = document.getElementById(\'pageTrack\');\n\
                const container = document.getElementById(\'pageSliderContainer\');\n\
                if (!track || !container) return;\n\
                track.innerHTML = \'\';\n\
                const notchCount = Math.min(currentTotalPages, 51);\n\
                const containerHeight = container.offsetHeight;\n\
                const notchSpacing = containerHeight / (notchCount - 1);\n\
                const centerX = container.offsetWidth / 2;\n\
                const centerY = containerHeight / 2;\n\
                const centerIndex = Math.floor(notchCount / 2);\n\
                for (let i = 0; i < notchCount; i++) {\n\
                    const notch = document.createElement(\'div\');\n\
                    notch.style.position = \'absolute\';\n\
                    notch.style.borderRadius = \'1px\';\n\
                    notch.style.pointerEvents = \'none\';\n\
                    const yPos = i * notchSpacing;\n\
                    const offsetFromCenter = i - centerIndex;\n\
                    if (offsetFromCenter === 0) {\n\
                        notch.style.width = \'22px\';\n\
                        notch.style.height = \'3px\';\n\
                        notch.style.left = (centerX - 11) + \'px\';\n\
                        notch.style.backgroundColor = \'rgba(255,215,0,0.9)\';\n\
                        notch.style.boxShadow = \'0 0 4px rgba(255,215,0,0.5)\';\n\
                    } else if (Math.abs(offsetFromCenter) % 5 === 0) {\n\
                        notch.style.width = \'18px\';\n\
                        notch.style.height = \'2px\';\n\
                        notch.style.left = (centerX - 9) + \'px\';\n\
                        notch.style.backgroundColor = \'rgba(255,215,150,0.8)\';\n\
                    } else {\n\
                        notch.style.width = \'10px\';\n\
                        notch.style.height = \'1.5px\';\n\
                        notch.style.left = (centerX - 5) + \'px\';\n\
                        notch.style.backgroundColor = \'rgba(255,235,200,0.6)\';\n\
                    }\n\
                    notch.style.top = yPos + \'px\';\n\
                    track.appendChild(notch);\n\
                }\n\
                track.style.height = containerHeight + \'px\';\n\
            }\n\
\n\
            function setupPageScrolling() {\n\
                const container = document.getElementById(\'pageSliderContainer\');\n\
                const track = document.getElementById(\'pageTrack\');\n\
                const overlay = document.getElementById(\'pageScrollOverlay\');\n\
                if (!container || !track) return;\n\
                function getPageFromScroll(scrollY) { const containerHeight=container.offsetHeight,centerY=containerHeight/2,progress=(-scrollY+centerY)/containerHeight,clamped=Math.max(0,Math.min(1,progress)); return Math.floor(clamped*(currentTotalPages-1))+1; }\n\
                function updatePageFromScroll(scrollY) { if(!pageScrollDragging)return; const pageNum=getPageFromScroll(scrollY); updatePageDisplay(pageNum); const $magazine=$(\'#magazine\'); if($magazine&&$magazine.turn)$magazine.turn(\'page\',pageNum); }\n\
                function setTrackPosition(pageNum) { if(!track||!container)return; const progress=(pageNum-1)/(currentTotalPages-1),containerHeight=container.offsetHeight,centerY=containerHeight/2,scrollY=-(progress*containerHeight)+centerY; track.style.transform=\'translateY(\'+scrollY+\'px)\'; }\n\
                function startDrag(){ pageScrollDragging=true; showOverlay(2000); container.style.cursor=\'grabbing\'; if(hideTimeout)clearTimeout(hideTimeout); if(activeTimeout)clearTimeout(activeTimeout); }\n\
                function endDrag(){ pageScrollDragging=false; container.style.cursor=\'grab\'; const scroll=parseFloat((track.style.transform||\'\').match(/translateY\\(([^)]+)/)?.[1]||0),pageNum=getPageFromScroll(scroll); setTrackPosition(pageNum); updatePageDisplay(pageNum); if(hideTimeout)clearTimeout(hideTimeout); hideTimeout=setTimeout(function(){ const o=document.getElementById(\'pageScrollOverlay\'); if(o&&!pageScrollDragging)o.style.opacity=\'0\'; },2000); if(activeTimeout)clearTimeout(activeTimeout); activeTimeout=setTimeout(function(){ const d=document.getElementById(\'pageDisplayCenter\'); if(d&&!pageScrollDragging)d.style.opacity=\'0\'; },2000); }\n\
                container.addEventListener(\'mousedown\',function(e){ e.preventDefault(); startDrag(); pageTrackStartY=e.clientY; const transform=track.style.transform; pageTrackStartScroll=transform&&transform.includes(\'translateY\')?parseFloat(transform.match(/translateY\\(([^)]+)/)[1]):0; updatePageDisplay(getPageFromScroll(pageTrackStartScroll)); });\n\
                document.addEventListener(\'mousemove\',function(e){ if(!pageScrollDragging)return; e.preventDefault(); const delta=e.clientY-pageTrackStartY,newScroll=pageTrackStartScroll+delta; track.style.transform=\'translateY(\'+newScroll+\'px)\'; updatePageFromScroll(newScroll); });\n\
                document.addEventListener(\'mouseup\',function(){ if(pageScrollDragging)endDrag(); });\n\
                container.addEventListener(\'touchstart\',function(e){ e.preventDefault(); startDrag(); pageTrackStartY=e.touches[0].clientY; const transform=track.style.transform; pageTrackStartScroll=transform&&transform.includes(\'translateY\')?parseFloat(transform.match(/translateY\\(([^)]+)/)[1]):0; updatePageDisplay(getPageFromScroll(pageTrackStartScroll)); },{passive:false});\n\
                container.addEventListener(\'touchmove\',function(e){ if(!pageScrollDragging)return; e.preventDefault(); const delta=e.touches[0].clientY-pageTrackStartY,newScroll=pageTrackStartScroll+delta; track.style.transform=\'translateY(\'+newScroll+\'px)\'; updatePageFromScroll(newScroll); },{passive:false});\n\
                container.addEventListener(\'touchend\',function(e){ if(pageScrollDragging)endDrag(); e.preventDefault(); });\n\
                const $magazine=$(\'#magazine\'); if($magazine&&$magazine.turn){ $magazine.bind(\'turned\',function(e,page){ if(!pageScrollDragging){ setTrackPosition(page); updatePageDisplay(page); } }); }\n\
                const savedPage=getSavedPage();\n\
                setTimeout(function(){ createPageNotches(); setTrackPosition(savedPage); updatePageDisplay(savedPage); if(overlay)overlay.style.opacity=\'1\'; showOverlay(3000); showDisplay(3000); },100);\n\
                setTimeout(function(){ const $magazine=$(\'#magazine\'); if($magazine&&$magazine.turn)$magazine.turn(\'page\',savedPage); },300);\n\
            }\n\
\n\
            function init(){\n\
                createScrollOverlay();\n\
                let attempts=0;\n\
                const interval=setInterval(function(){ attempts++; const $magazine=$(\'#magazine\'); if(($magazine&&$magazine.turn&&typeof $magazine.turn(\'page\')!==\'undefined\')||attempts>40){ clearInterval(interval); setTimeout(setupPageScrolling,200); } },100);\n\
            }\n\
            if(document.readyState===\'loading\')document.addEventListener(\'DOMContentLoaded\',init); else init();\n\
        })();\n\
    </script>\n\
    <script>\n\
        (function fixiOSHeight() {\n\
            if(/iPad|iPhone|iPod/.test(navigator.userAgent)||(navigator.platform===\'MacIntel\'&&navigator.maxTouchPoints>1)){\n\
                function adjustHeight(){ const vh=window.visualViewport?window.visualViewport.height:window.innerHeight; const magazine=document.getElementById(\'magazine\'); if(magazine){ magazine.style.height=vh+\'px\'; magazine.style.top=\'0\'; magazine.style.position=\'absolute\'; } document.body.style.margin=\'0\'; document.body.style.padding=\'0\'; document.body.style.top=\'0\'; document.body.style.position=\'fixed\'; document.documentElement.style.margin=\'0\'; document.documentElement.style.padding=\'0\'; document.documentElement.style.top=\'0\'; const slider=document.getElementById(\'pageSliderContainer\'),ribbon=document.querySelector(\'.vertical-ribbon-base\'),overlay=document.getElementById(\'pageScrollOverlay\'); if(slider){ slider.style.height=(vh*0.85)+\'px\'; slider.style.maxHeight=(vh*0.85)+\'px\'; slider.style.top=\'auto\'; slider.style.bottom=\'auto\'; } if(ribbon){ ribbon.style.height=(vh*0.85)+\'px\'; ribbon.style.maxHeight=(vh*0.85)+\'px\'; } if(overlay){ overlay.style.top=\'0\'; overlay.style.bottom=\'0\'; } setTimeout(function(){ if(typeof createPageNotches===\'function\')createPageNotches(); if(typeof setTrackPosition===\'function\'&&window.currentPageNumber)setTrackPosition(window.currentPageNumber); },50); }\n\
                adjustHeight(); window.visualViewport?.addEventListener(\'resize\',adjustHeight); window.addEventListener(\'resize\',adjustHeight); window.addEventListener(\'orientationchange\',function(){ setTimeout(adjustHeight,50); }); setTimeout(adjustHeight,100);\n\
            }\n\
        })();\n\
    </script>\n\
    <script>\n\
        (function(){\n\
            let wheelTimeout=null,lastScrollTime=0,isScrolling=false; const scrollThrottle=80;\n\
            function getPageFromScroll(scrollY){ const container=document.getElementById(\'pageSliderContainer\'); if(!container)return 1; const containerHeight=container.offsetHeight,centerY=containerHeight/2,progress=(-scrollY+centerY)/containerHeight,clamped=Math.max(0,Math.min(1,progress)); return Math.floor(clamped*(' + pageCountNum + '-1))+1; }\n\
            function setTrackPosition(pageNum){ const track=document.getElementById(\'pageTrack\'),container=document.getElementById(\'pageSliderContainer\'); if(!track||!container)return; const progress=(pageNum-1)/(' + pageCountNum + '-1),containerHeight=container.offsetHeight,centerY=containerHeight/2,scrollY=-(progress*containerHeight)+centerY; track.style.transform=\'translateY(\'+scrollY+\'px)\'; }\n\
            function updatePageDisplayWithoutSave(pageNum){ const display=document.getElementById(\'pageDisplayCenter\'); if(display){ display.innerHTML=\'<span style="font-family:monospace;font-style:normal;font-weight:bold;"></span>\' + pageNum + \'/\' + ' + pageCountNum + '; } }\n\
            function savePageAndUpdateDisplay(pageNum){ const display=document.getElementById(\'pageDisplayCenter\'); if(display){ display.innerHTML=\'<span style="font-family:monospace;font-style:normal;font-weight:bold;"></span>\' + pageNum + \'/\' + ' + pageCountNum + '; localStorage.setItem(\'flipbook_last_page_\'+title,pageNum); } }\n\
            function handleWheel(e){ if(window.pageScrollDragging)return; const container=document.getElementById(\'pageSliderContainer\'),track=document.getElementById(\'pageTrack\'); if(!container||!track)return; const now=Date.now(); if(now-lastScrollTime<scrollThrottle)return; lastScrollTime=now; e.preventDefault(); const overlay=document.getElementById(\'pageScrollOverlay\'),display=document.getElementById(\'pageDisplayCenter\'); if(overlay)overlay.style.opacity=\'1\'; if(display)display.style.opacity=\'1\'; if(window.wheelHideTimeout)clearTimeout(window.wheelHideTimeout); if(window.wheelDisplayTimeout)clearTimeout(window.wheelDisplayTimeout); window.wheelHideTimeout=setTimeout(function(){ if(overlay&&!window.pageScrollDragging&&!isScrolling)overlay.style.opacity=\'0\'; },1500); window.wheelDisplayTimeout=setTimeout(function(){ if(display&&!window.pageScrollDragging&&!isScrolling)display.style.opacity=\'0\'; },1500); const currentScroll=parseFloat((track.style.transform||\'\').match(/translateY\\(([^)]+)/)?.[1]||0),sensitivity=1.5,delta=e.deltaY*sensitivity; let newScroll=currentScroll+delta; const containerHeight=container.offsetHeight,centerY=containerHeight/2,minScroll=-centerY,maxScroll=containerHeight-centerY; newScroll=Math.max(minScroll,Math.min(maxScroll,newScroll)); track.style.transform=\'translateY(\'+newScroll+\'px)\'; const pageNum=getPageFromScroll(newScroll); updatePageDisplayWithoutSave(pageNum); const $magazine=$(\'#magazine\'); if($magazine&&$magazine.turn)$magazine.turn(\'page\',pageNum); if(wheelTimeout)clearTimeout(wheelTimeout); wheelTimeout=setTimeout(function(){ isScrolling=true; const finalScroll=parseFloat((track.style.transform||\'\').match(/translateY\\(([^)]+)/)?.[1]||0),finalPage=getPageFromScroll(finalScroll); setTrackPosition(finalPage); savePageAndUpdateDisplay(finalPage); const $magazine=$(\'#magazine\'); if($magazine&&$magazine.turn)$magazine.turn(\'page\',finalPage); setTimeout(function(){ isScrolling=false; },200); },100); }\n\
            function initWheelScrolling(){ window.currentTotalPages=' + pageCountNum + '; window.pageScrollDragging=false; window.addEventListener(\'wheel\',handleWheel,{passive:false}); }\n\
            if(document.readyState===\'loading\')document.addEventListener(\'DOMContentLoaded\',initWheelScrolling); else initWheelScrolling();\n\
        })();\n\
    </script>\n\
</body>\n\
</html>';
}

// ============= PURE JSON API ENDPOINTS =============

// ============= OPEN GRAPH IMAGE ENDPOINT =============
// OG Image stats
app.get('/api/og/stats', async (req, res) => {
    res.json({
        version: '@vercel/og',
        node_version: process.version,
        total_flipbooks: conversionHistory.length,
        templates: ['magazine', 'modern', 'dark'],
        recommended_size: '1200x630',
        weserv_integration: `Use /weserv/?url=/api/og/:id&w=1200&h=630`,
        examples: {
            direct: `/api/og/FLIPBOOK_ID`,
            via_weserv: `/weserv/?url=/api/og/FLIPBOOK_ID&w=1200&h=630&fit=cover`
        }
    });
});

app.get('/api/og/:flipbookId', async (req, res) => {
    const startTime = Date.now();
    
    try {
        const { flipbookId } = req.params;
        
        // Find flipbook in history
        const flipbook = conversionHistory.find(h => h.id === flipbookId);
        
        if (!flipbook) {
            console.log(`[OG] Flipbook not found: ${flipbookId}`);
            return res.status(404).json({ 
                error: 'Flipbook not found',
                message: `No flipbook found with ID: ${flipbookId}`
            });
        }
        
        console.log(`[OG] Generating image for: ${flipbook.display_title || flipbook.title}`);
        
        // Generate OG image
        const { buffer, cacheKey, contentType } = await generateOGImage(flipbook, DOMAIN);
        
        // Set caching headers - Weserv will cache this aggressively
        res.setHeader('Content-Type', contentType);
        res.setHeader('Content-Length', buffer.length);
        res.setHeader('Cache-Control', 'public, max-age=31536000, immutable'); // 1 year
        res.setHeader('ETag', `"${cacheKey}"`);
        res.setHeader('X-OG-Generator', '@vercel/og');
        res.setHeader('X-Generation-Time', `${Date.now() - startTime}ms`);
        
        // Send the image
        res.send(buffer);
        
        console.log(`[OG] Generated in ${Date.now() - startTime}ms, size: ${buffer.length} bytes`);
        
    } catch (error) {
        console.error('[OG] Generation error:', error);
        
        // Fallback: Return a simple error message
        res.status(500).json({ 
            error: 'Failed to generate OG image',
            message: error.message,
            fallback: 'Use default og:image'
        });
    }
});


// Progress tracking endpoint - IMPROVED
app.get('/api/progress/:jobId', async (req, res) => {
    const jobId = req.params.jobId;
    const progress = jobProgress.get(jobId) || { percent: 0, stage: 'waiting' };
    
    // Check if job exists in queue
    const job = await pdfQueue.getJob(jobId);
    
    if (!job && progress.stage === 'waiting' && progress.percent === 0) {
        return res.status(404).json({
            error: 'Job not found',
            job_id: jobId,
            message: 'No job found with this ID. It may have expired or never existed.',
            tip: 'Check /api/history for completed jobs or /queue/stats for active jobs'
        });
    }
    
    // Add helpful information
    const response = {
        job_id: jobId,
        ...progress,
        help: {
            status_explanation: {
                waiting: 'Job is queued and waiting to start',
                downloading: 'Downloading PDF from URL',
                uploaded: 'File received, starting conversion',
                analyzing: 'Reading PDF structure',
                converting: `Converting pages ${progress.currentPage || '?'}/${progress.totalPages || '?'}`,
                complete: 'Conversion finished! Check /api/history',
                error: 'Conversion failed - check error field'
            },
            next_steps: progress.stage === 'complete' 
                ? 'Visit /api/history to get your flipbook links'
                : `Monitor progress at /api/progress/${jobId}`,
            estimated_remaining: getEstimatedTime(progress)
        }
    };
    
    res.json(response);
});

// Helper function for estimated time
function getEstimatedTime(progress) {
    if (progress.stage === 'complete') return '0 seconds (complete)';
    if (progress.stage === 'error') return 'N/A (failed)';
    if (progress.stage === 'converting' && progress.currentPage && progress.totalPages) {
        const pagesLeft = progress.totalPages - progress.currentPage;
        const estimatedSeconds = Math.ceil(pagesLeft * 2.5); // ~2.5 seconds per page
        if (estimatedSeconds < 60) return `~${estimatedSeconds} seconds`;
        return `~${Math.ceil(estimatedSeconds / 60)} minutes`;
    }
    return 'unknown (check back in 30 seconds)';
}

// List all active/waiting jobs
app.get('/api/jobs', async (req, res) => {
    try {
        const [waiting, active, completed, failed] = await Promise.all([
            pdfQueue.getWaiting(),
            pdfQueue.getActive(),
            pdfQueue.getCompleted(),
            pdfQueue.getFailed()
        ]);
        
        const jobs = {
            waiting: waiting.map(j => ({ id: j.id, timestamp: j.timestamp })),
            active: active.map(j => ({ id: j.id, timestamp: j.timestamp })),
            recent_completed: completed.slice(0, 10).map(j => ({ id: j.id, timestamp: j.timestamp })),
            counts: {
                waiting: waiting.length,
                active: active.length,
                completed: completed.length,
                failed: failed.length
            }
        };
        
        res.json(jobs);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

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

// Add this function to check for existing jobs
async function isUrlAlreadyProcessing(url) {
    const normalizedUrl = url.startsWith('http') ? url : 'https://' + url;
    const cacheKey = crypto.createHash('md5').update(normalizedUrl).digest('hex');
    
    // Check if already in queue (waiting or active)
    const waiting = await pdfQueue.getWaiting();
    const active = await pdfQueue.getActive();
    
    for (const job of [...waiting, ...active]) {
        if (job.data.pdfUrl === normalizedUrl || job.data.cacheKey === cacheKey) {
            return { processing: true, jobId: job.id };
        }
    }
    
    // Check if it exists in failed jobs (within last hour)
    const failed = await pdfQueue.getFailed();
    const recentFailed = failed.filter(job => 
        (job.data.pdfUrl === normalizedUrl || job.data.cacheKey === cacheKey) &&
        Date.now() - job.timestamp < 3600000 // Within last hour
    );
    
    if (recentFailed.length > 0) {
        return { failed: true, failedJobId: recentFailed[0].id, failedAt: recentFailed[0].timestamp };
    }
    
    return { processing: false };
}

// Add this helper function near the top of server.js
function isValidUrl(string) {
    try {
        const url = new URL(string);
        return url.protocol === 'http:' || url.protocol === 'https:';
    } catch (_) {
        return false;
    }
}
// Then modify the /api/convert endpoint:
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
        
        // Validate URL format
        if (!isValidUrl(targetUrl)) {
            return res.status(400).json({
                error: 'Invalid URL format',
                message: 'URL must start with http:// or https://',
                provided: targetUrl
            });
        }
        
        // Normalize URL
        const normalizedUrl = targetUrl.trim();
        const cacheKey = crypto.createHash('md5').update(normalizedUrl).digest('hex');
        const outputDir = path.join(OUTPUT_DIR, `flipbook_${cacheKey}`);
        const zipPath = path.join(OUTPUT_DIR, `flipbook_${cacheKey}.zip`);
        
        // Check if already successfully processed
        if (!forceRefresh && fs.existsSync(outputDir) && fs.existsSync(zipPath)) {
            const files = fs.readdirSync(outputDir);
            const htmlFile = files.find(f => f.endsWith('_flipbook.html'));
            const pdfName = htmlFile ? htmlFile.replace('_flipbook.html', '') : 'document';
            
            const existingEntry = conversionHistory.find(h => h.id === cacheKey);
            const thumbnailUrl = existingEntry ? existingEntry.thumbnail_url : getThumbnailUrl(cacheKey, 0, pdfName);
            
            console.log(`[Cache] HIT for ${normalizedUrl}`);
            
            return res.json({
                success: true,
                cached: true,
                title: pdfName,
                html_url: `/output/flipbook_${cacheKey}/${htmlFile}`,
                zip_url: `/output/flipbook_${cacheKey}.zip`,
                thumbnail_url: thumbnailUrl
            });
        }
        
        // 🔥 NEW: Check if already processing or failed
        const status = await isUrlAlreadyProcessing(normalizedUrl);
        
        if (status.processing) {
            return res.status(409).json({
                error: 'Already processing',
                message: 'This PDF URL is already being processed',
                job_id: status.jobId,
                progress_url: `/api/progress/${status.jobId}`,
                status: 'queued_or_active'
            });
        }
        
        if (status.failed && !forceRefresh) {
            return res.status(422).json({
                error: 'Previously failed',
                message: 'This PDF URL failed to process before. Use &rc=1 to retry.',
                failed_job_id: status.failedJobId,
                failed_at: new Date(status.failedAt).toISOString(),
                retry_command: `${req.protocol}://${req.get('host')}${req.originalUrl}&rc=1`
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
        
        res.json({
            success: true,
            cached: false,
            job_id: job.id,
            message: 'Processing started',
            progress_url: `/api/progress/${job.id}`,
            status_url: `https://${DOMAIN}/api/progress/${job.id}`,
            estimated_time: '2-5 minutes depending on PDF size'
        });
        
        job.finished().then(result => {
            console.log(`[Job ${job.id}] completed successfully`);
        }).catch(error => {
            console.error(`[Job ${job.id}] failed:`, error.message);
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

// Add function to check existing upload jobs
async function isUploadAlreadyProcessing(filename, fileSize) {
    const waiting = await pdfQueue.getWaiting();
    const active = await pdfQueue.getActive();
    const fiveMinutesAgo = Date.now() - 300000;
    
    for (const job of [...waiting, ...active]) {
        if (job.data.source === 'upload' && 
            job.data.originalName === filename && 
            job.timestamp > fiveMinutesAgo) {
            return { processing: true, jobId: job.id };
        }
    }
    
    return { processing: false };
}

// Then modify the /api/upload endpoint
app.post('/api/upload', upload.single('pdf'), async (req, res) => {
    if (req.fileValidationError) {
        return res.status(400).json({ error: req.fileValidationError });
    }
    
    if (!req.file) {
        return res.status(400).json({ error: 'No PDF file uploaded. Please send a file with field name "pdf".' });
    }
    
    const uploadedFile = req.file;
    const originalName = uploadedFile.originalname;
    
    // 🔥 NEW: Check if same file is already being processed
    const status = await isUploadAlreadyProcessing(originalName, uploadedFile.size);
    
    if (status.processing) {
        // Clean up the uploaded file
        if (fs.existsSync(uploadedFile.path)) {
            fs.unlinkSync(uploadedFile.path);
        }
        
        return res.status(409).json({
            error: 'Already processing',
            message: `This file "${originalName}" is already being processed`,
            job_id: status.jobId,
            progress_url: `/api/progress/${status.jobId}`
        });
    }
    
    const cacheKey = crypto.createHash('md5').update(originalName + Date.now()).digest('hex');
    
    console.log(`[Upload] Received: ${originalName} (${uploadedFile.size} bytes)`);
    
    try {
        const job = await pdfQueue.add({
            pdfPath: uploadedFile.path,
            cacheKey: cacheKey,
            originalName: originalName,
            source: 'upload'
        });
        
        console.log(`[Upload] Added job ${job.id} for ${originalName}`);
        
        res.json({
            success: true,
            job_id: job.id,
            message: 'PDF uploaded and queued for processing'
        });
        
        job.finished().then(result => {
            console.log(`[Upload] Job ${job.id} completed successfully`);
        }).catch(error => {
            console.error(`[Upload] Job ${job.id} failed:`, error.message);
        });
        
    } catch (error) {
        console.error('[Upload Error]', error.message);
        if (uploadedFile.path && fs.existsSync(uploadedFile.path)) {
            fs.unlinkSync(uploadedFile.path);
        }
        res.status(500).json({
            error: 'Failed to queue PDF',
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

// Cleanup old failed jobs periodically (every hour)
setInterval(async () => {
    try {
        const failed = await pdfQueue.getFailed();
        const oneHourAgo = Date.now() - 3600000;
        
        for (const job of failed) {
            if (job.timestamp < oneHourAgo) {
                await job.remove();
                console.log(`[Cleanup] Removed old failed job ${job.id}`);
            }
        }
    } catch (error) {
        console.error('[Cleanup] Error:', error.message);
    }
}, 3600000); // Run every hour

// This allows users to exchange metatag og:image template from default to custom
app.post('/api/og/upload-template', upload.single('file'), async (req, res) => {
    if (!req.file) {
        return res.status(400).json({ error: 'No file uploaded' });
    }
    
    // Check file extension
    if (!req.file.originalname.endsWith('.js')) {
        fs.unlinkSync(req.file.path);
        return res.status(400).json({ error: 'Only .js files allowed' });
    }
    
    const generatorPath = '/opt/flipbook-api/og-generator.js';
    const backupPath = `/opt/flipbook-api/og-generator.backup.${Date.now()}.js`;
    
    try {
        // Create backup
        if (fs.existsSync(generatorPath)) {
            fs.copyFileSync(generatorPath, backupPath);
        }
        
        // Replace with new file
        fs.copyFileSync(req.file.path, generatorPath);
        
        // Clean up temp file
        fs.unlinkSync(req.file.path);
        
        // Restart PM2
        const { exec } = require('child_process');
        exec('pm2 restart flipbook-api', (error, stdout, stderr) => {
            if (error) {
                console.error('Restart error:', error);
            } else {
                console.log('API restarted:', stdout);
            }
        });
        
        res.json({
            success: true,
            message: 'OG template updated! API restarting...',
            backup: backupPath
        });
        
    } catch (error) {
        // Restore from backup if something failed
        if (fs.existsSync(backupPath)) {
            fs.copyFileSync(backupPath, generatorPath);
        }
        if (req.file && fs.existsSync(req.file.path)) {
            fs.unlinkSync(req.file.path);
        }
        res.status(500).json({ error: error.message });
    }
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`✅ PDF to FlipBook API running on port ${PORT}`);
    console.log(`   API Base: http://localhost:${PORT}/api/convert`);
    console.log(`   Upload: POST /api/upload`);
    console.log(`   History: GET /api/history`);
    console.log(`   Progress: GET /api/progress/:jobId`);
    console.log(`   OG Image: GET /api/og/:flipbookId`);
    console.log(`   Queue: 3 concurrent conversions`);
    console.log(`   ⚠️  Web UI is served by nginx at /var/www/flipbook/web/`);
    if (API_TOKEN) {
        console.log(`   Authentication: REQUIRED (token set)`);
    } else {
        console.log(`   Authentication: DISABLED (public access)`);
    }
});
EOF

cat > /var/www/flipbook/web/og-upload.html << 'UPLOAD_HTML'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>OG Template Manager - Upload Custom Design</title>
    <style>
        body {
            background: #1a1a2e;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            color: white;
            padding: 40px;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
        }
        .card {
            background: rgba(30,30,50,0.9);
            backdrop-filter: blur(10px);
            padding: 30px;
            border-radius: 16px;
            margin-bottom: 20px;
            border: 1px solid rgba(255,255,255,0.1);
        }
        h1 {
            color: #667eea;
            margin-bottom: 10px;
        }
        h2 {
            color: #667eea;
            font-size: 20px;
            margin: 20px 0 15px 0;
        }
        h3 {
            color: #667eea;
            font-size: 18px;
            margin: 15px 0 10px 0;
        }
        input, button {
            width: 100%;
            padding: 12px;
            margin: 10px 0;
            border-radius: 8px;
        }
        input {
            background: rgba(0,0,0,0.3);
            border: 1px solid rgba(255,255,255,0.2);
            color: white;
        }
        button {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            cursor: pointer;
            font-weight: bold;
        }
        button:hover {
            transform: translateY(-2px);
        }
        .status {
            margin-top: 20px;
            padding: 12px;
            border-radius: 8px;
            display: none;
        }
        .success { background: rgba(16,185,129,0.2); border: 1px solid #10b981; color: #10b981; }
        .error { background: rgba(239,68,68,0.2); border: 1px solid #ef4444; color: #ef4444; }
        .info { background: rgba(102,126,234,0.2); border: 1px solid #667eea; color: #667eea; display: block; }
        .rule-list, .guide-list {
            margin-left: 20px;
            line-height: 1.8;
        }
        .rule-list li, .guide-list li {
            margin-bottom: 8px;
        }
        code {
            background: rgba(0,0,0,0.5);
            padding: 2px 6px;
            border-radius: 4px;
            font-family: monospace;
            font-size: 13px;
        }
        .download-btn {
            display: inline-block;
            background: #10b981;
            padding: 10px 20px;
            border-radius: 8px;
            text-decoration: none;
            color: white;
            margin-top: 10px;
        }
        .download-btn:hover {
            background: #059669;
        }
        hr {
            border-color: rgba(255,255,255,0.1);
            margin: 20px 0;
        }
        .backup-note {
            background: rgba(239,68,68,0.1);
            border-left: 4px solid #ef4444;
            padding: 15px;
            margin-top: 15px;
            border-radius: 8px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="card">
            <h1>🎨 OG Template Manager</h1>
            <p>Customize how your flipbook preview looks on <strong>Discord, Twitter, Facebook, and WhatsApp</strong>.</p>
        </div>

        <div class="card">
            <h2>📋 Rules for Your <code>og-generator.js</code> File</h2>
            <ul class="rule-list">
                <li>✅ <strong>Must be a valid <code>.js</code> file</strong> - Only JavaScript files are accepted.</li>
                <li>✅ <strong>Must export <code>generateOGImage</code> and <code>getOGCacheKey</code></strong> - Your file needs <code>module.exports = { generateOGImage, getOGCacheKey };</code></li>
                <li>✅ <strong>Must use <code>React.createElement</code></strong> - Return JSX-style elements for the image.</li>
                <li>✅ <strong>Must return a 1200x630 PNG</strong> - Use <code>new ImageResponse(element, { width: 1200, height: 630 });</code></li>
                <li>❌ <strong>No external network calls</strong> - The function runs on the server; avoid <code>fetch</code> or <code>axios</code>.</li>
                <li>❌ <strong>No file system access</strong> - Don't use <code>fs</code> module.</li>
                <li>❌ <strong>No <code>console.log</code></strong> - It can break the image generation.</li>
            </ul>
        </div>

        <div class="card">
            <h2>📖 How to Create a Custom Template</h2>
            <ol class="guide-list">
                <li>Download the <strong>current default template</strong> using the button below.</li>
                <li>Edit the <code>React.createElement</code> styles (fonts, colors, layout, blur amount, image size, etc.).</li>
                <li><strong>Test it locally</strong> by uploading below. The API will <strong>automatically restart</strong>.</li>
                <li>Test the result by sharing a flipbook link on Discord or visiting <code>/api/og/YOUR_FLIPBOOK_ID</code>.</li>
                <li>If something breaks, the backup is saved automatically (check the success message for the backup path).</li>
            </ol>
            
            <div style="text-align: center; margin: 20px 0;">
                <a href="/templates/og-design-default.js" download class="download-btn">📥 Download Default Template (og-design-default.js)</a>
            </div>
        </div>

        <div class="card">
            <h2>⬆️ Upload Your Custom Template</h2>
            <p>Upload a custom <code>og-generator.js</code> file to replace the current design.</p>
            
            <input type="file" id="fileInput" accept=".js">
            <button onclick="uploadTemplate()">🚀 Upload & Restart API</button>
            
            <div id="status" class="status"></div>
            
            <div class="backup-note">
                <strong>⚠️ Automatic Backup:</strong> The system creates a backup before replacing your file.<br>
                Backup path: <code>/opt/flipbook-api/og-generator.backup.[timestamp].js</code>
            </div>
        </div>

        <div class="card">
            <h2>🔄 Alternative Methods</h2>
            <p><strong>Via SSH (Manual):</strong></p>
            <code style="display: block; background: #000; padding: 10px; border-radius: 6px; margin: 10px 0;">nano /opt/flipbook-api/og-generator.js</code>
            <code style="display: block; background: #000; padding: 10px; border-radius: 6px; margin: 10px 0;">pm2 restart flipbook-api</code>
            
            <p><strong>Via cURL (Command Line):</strong></p>
            <code style="display: block; background: #000; padding: 10px; border-radius: 6px; margin: 10px 0;">curl -X POST https://flipbook.gitgpt.chat/api/og/upload-template -F "file=@my-custom-og.js"</code>
            
            <hr>
            <a href="/og-preview.html" style="color: #667eea;">🔍 Preview OG Image</a> | 
            <a href="/api/og/stats" target="_blank" style="color: #667eea;">📊 OG Stats</a> |
            <a href="/api/history" target="_blank" style="color: #667eea;">📚 Flipbook History</a>
        </div>
    </div>
    
    <script>
        async function uploadTemplate() {
            const fileInput = document.getElementById('fileInput');
            const statusDiv = document.getElementById('status');
            
            // Check if file is selected
            if (!fileInput.files[0]) {
                statusDiv.className = 'status error';
                statusDiv.textContent = '❌ Please select a .js file';
                statusDiv.style.display = 'block';
                setTimeout(() => { statusDiv.style.display = 'none'; }, 5000);
                return;
            }
            
            const file = fileInput.files[0];
            
            // Validate file extension
            if (!file.name.endsWith('.js')) {
                statusDiv.className = 'status error';
                statusDiv.textContent = '❌ File must have a .js extension';
                statusDiv.style.display = 'block';
                setTimeout(() => { statusDiv.style.display = 'none'; }, 5000);
                return;
            }
            
            // Validate file size (max 1MB)
            if (file.size > 1024 * 1024) {
                statusDiv.className = 'status error';
                statusDiv.textContent = '❌ File too large. Maximum size is 1MB.';
                statusDiv.style.display = 'block';
                setTimeout(() => { statusDiv.style.display = 'none'; }, 5000);
                return;
            }
            
            // Basic content validation
            const fileContent = await file.text();
            if (!fileContent.includes('generateOGImage') || !fileContent.includes('module.exports')) {
                statusDiv.className = 'status error';
                statusDiv.textContent = '❌ Invalid file. Must export generateOGImage function. See rules above.';
                statusDiv.style.display = 'block';
                setTimeout(() => { statusDiv.style.display = 'none'; }, 8000);
                return;
            }
            
            const formData = new FormData();
            formData.append('file', file);
            
            statusDiv.className = 'status';
            statusDiv.textContent = '⏳ Uploading and restarting API... This may take 10-15 seconds.';
            statusDiv.style.display = 'block';
            
            try {
                const response = await fetch('/api/og/upload-template', {
                    method: 'POST',
                    body: formData
                });
                const result = await response.json();
                
                if (result.success) {
                    statusDiv.className = 'status success';
                    statusDiv.innerHTML = '✅ Template updated successfully!<br>🔄 API restarting...<br>📁 Backup saved: ' + result.backup;
                    fileInput.value = '';
                    setTimeout(() => {
                        statusDiv.style.display = 'none';
                    }, 8000);
                } else {
                    throw new Error(result.error || 'Unknown error');
                }
            } catch (error) {
                statusDiv.className = 'status error';
                statusDiv.innerHTML = '❌ Upload failed: ' + error.message + '<br>⚠️ Your previous template is still intact.';
                setTimeout(() => {
                    statusDiv.style.display = 'none';
                }, 8000);
            }
        }
    </script>
</body>
</html>
UPLOAD_HTML

echo "✅ Upload page created at: https://flipbook.gitgpt.chat/og-upload.html"

# Create templates directory and default template for download
mkdir -p /var/www/flipbook/web/templates
cp /opt/flipbook-api/og-generator.js /var/www/flipbook/web/templates/og-design-default.js
chmod 644 /var/www/flipbook/web/templates/og-design-default.js

echo "✅ Default template available at: https://flipbook.gitgpt.chat/templates/og-design-default.js"

# Create OG preview HTML file for testing
cat > /var/www/flipbook/web/og-preview.html << 'OG_PREVIEW'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OG Image Preview</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            background: #1a1a2e;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            padding: 40px;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
        }
        .container {
            max-width: 1000px;
            width: 100%;
        }
        h1 {
            color: white;
            text-align: center;
            margin-bottom: 30px;
            font-size: 28px;
        }
        .og-preview {
            width: 100%;
            max-width: 800px;
            margin: 0 auto;
            aspect-ratio: 1200 / 630;
            background: #1a1a2e;
            border-radius: 16px;
            overflow: hidden;
            box-shadow: 0 20px 40px rgba(0,0,0,0.4);
            position: relative;
        }
        .og-effect {
            width: 100%;
            height: 100%;
            position: relative;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .blur-bg {
            position: absolute;
            top: -10%;
            left: -10%;
            width: 120%;
            height: 120%;
            background-size: cover;
            background-position: center;
            filter: blur(20px);
            opacity: 0.9;
        }
        .dark-overlay {
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.5);
        }
        .content {
            position: relative;
            z-index: 2;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            width: 80%;
            height: 85%;
            text-align: center;
        }
        .first-page {
            max-width: 70%;
            max-height: 85%;
            object-fit: contain;
            border-radius: 12px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.3);
            border: 2px solid rgba(255,255,255,0.1);
        }
        .title {
            font-size: 28px;
            font-weight: bold;
            color: white;
            margin-top: 20px;
            text-shadow: 0 2px 4px rgba(0,0,0,0.5);
        }
        .metadata {
            display: flex;
            gap: 24px;
            margin-top: 12px;
            color: #ddd;
            font-size: 16px;
            text-shadow: 0 1px 2px rgba(0,0,0,0.5);
        }
        .info {
            margin-top: 30px;
            background: rgba(255,255,255,0.1);
            border-radius: 12px;
            padding: 20px;
            color: #ccc;
        }
        .info h3 {
            color: #667eea;
            margin-bottom: 10px;
        }
        .info code {
            background: rgba(0,0,0,0.5);
            padding: 2px 6px;
            border-radius: 4px;
            font-family: monospace;
        }
        .input-group {
            margin-top: 20px;
            display: flex;
            gap: 10px;
        }
        .input-group input {
            flex: 1;
            padding: 12px;
            border-radius: 8px;
            border: 1px solid rgba(255,255,255,0.2);
            background: rgba(0,0,0,0.3);
            color: white;
            font-size: 14px;
        }
        .input-group button {
            padding: 12px 24px;
            background: #667eea;
            color: white;
            border: none;
            border-radius: 8px;
            cursor: pointer;
        }
        .input-group button:hover {
            background: #5a67d8;
        }
        .error-note {
            margin-top: 20px;
            padding: 15px;
            background: rgba(255,100,100,0.2);
            border-left: 4px solid #ff6666;
            border-radius: 8px;
            color: #ffaaaa;
        }
        .success-note {
            margin-top: 20px;
            padding: 15px;
            background: rgba(100,255,100,0.2);
            border-left: 4px solid #66ff66;
            border-radius: 8px;
            color: #aaffaa;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎨 OG Image Preview</h1>
        
        <div class="og-preview">
            <div class="og-effect">
                <div class="blur-bg" id="blurBg"></div>
                <div class="dark-overlay"></div>
                <div class="content">
                    <img class="first-page" id="firstPageImg" alt="First page preview">
                    <div class="title" id="titleText">Official Xbox Magazine, Issue 1</div>
                    <div class="metadata" id="metadataText">
                        <span>📄 140 pages</span>
                        <span>📰 Flipbook</span>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="input-group">
            <input type="text" id="flipbookId" placeholder="Enter Flipbook ID (e.g., f8c61e41842267e99d06f431872a9484)">
            <button onclick="loadPreview()">Load Preview</button>
        </div>
        
        <div class="info">
            <h3>📖 How it works:</h3>
            <ul style="margin-left: 20px; line-height: 1.6;">
                <li><strong>Blurred background:</strong> Enlarged + blurred version of page 1</li>
                <li><strong>Center image:</strong> Actual page 1 (clear, not blurred)</li>
                <li><strong>Text overlay:</strong> Title, page count over dark overlay</li>
                <li><strong>Result:</strong> No black bars, professional look like WhatsApp portrait videos</li>
            </ul>
        </div>
        
        <div id="errorMsg" class="error-note" style="display: none;">
            ⚠️ Image not loading! The first page PNG may not exist or the URL is incorrect.
        </div>
        
        <div id="successMsg" class="success-note" style="display: none;">
            ✅ Image loaded successfully! This is what your OG image will look like.
        </div>
    </div>
    
    <script>
        const FLIPBOOK_URL = window.location.origin;
        
        async function loadPreview() {
            const flipbookId = document.getElementById('flipbookId').value.trim();
            const errorMsg = document.getElementById('errorMsg');
            const successMsg = document.getElementById('successMsg');
            const imgElement = document.getElementById('firstPageImg');
            const blurBg = document.getElementById('blurBg');
            const titleElement = document.getElementById('titleText');
            const metadataElement = document.getElementById('metadataText');
            
            if (!flipbookId) {
                errorMsg.textContent = '❌ Please enter a Flipbook ID';
                errorMsg.style.display = 'block';
                successMsg.style.display = 'none';
                return;
            }
            
            errorMsg.style.display = 'none';
            successMsg.style.display = 'none';
            
            // Get flipbook info from history
            try {
                const response = await fetch(`${FLIPBOOK_URL}/api/history`);
                const data = await response.json();
                const flipbook = data.history.find(h => h.id === flipbookId);
                
                if (flipbook) {
                    const title = flipbook.display_title || flipbook.title || 'Flipbook';
                    const pageCount = flipbook.page_count || 0;
                    const firstPageUrl = `${FLIPBOOK_URL}/output/flipbook_${flipbook.id}/${flipbook.title}_page_1.png`;
                    
                    titleElement.textContent = title.substring(0, 60);
                    metadataElement.innerHTML = `<span>📄 ${pageCount} pages</span><span>📰 Flipbook</span>`;
                    
                    // Test image
                    const testImg = new Image();
                    testImg.onload = function() {
                        imgElement.src = firstPageUrl;
                        blurBg.style.backgroundImage = `url('${firstPageUrl}')`;
                        successMsg.style.display = 'block';
                        errorMsg.style.display = 'none';
                        console.log('✅ Image loaded:', firstPageUrl);
                    };
                    testImg.onerror = function() {
                        imgElement.src = '';
                        blurBg.style.backgroundImage = '';
                        errorMsg.innerHTML = '⚠️ First page image not found. Make sure the PDF has been converted.';
                        errorMsg.style.display = 'block';
                        successMsg.style.display = 'none';
                        console.error('❌ Failed to load:', firstPageUrl);
                    };
                    testImg.src = firstPageUrl;
                } else {
                    errorMsg.innerHTML = `❌ Flipbook ID "${flipbookId}" not found. Check /api/history for valid IDs.`;
                    errorMsg.style.display = 'block';
                    successMsg.style.display = 'none';
                }
            } catch (err) {
                errorMsg.innerHTML = `❌ Error: ${err.message}`;
                errorMsg.style.display = 'block';
                successMsg.style.display = 'none';
            }
        }
        
        // Auto-load first flipbook on page load
        async function autoLoadFirst() {
            try {
                const response = await fetch(`${FLIPBOOK_URL}/api/history`);
                const data = await response.json();
                if (data.history && data.history.length > 0) {
                    document.getElementById('flipbookId').value = data.history[0].id;
                    loadPreview();
                }
            } catch (err) {
                console.log('Auto-load failed:', err);
            }
        }
        
        autoLoadFirst();
    </script>
</body>
</html>
OG_PREVIEW

echo "✅ OG preview page created at: https://flipbook.gitgpt.chat/og-preview.html"

# ============= CREATE WEB UI WITH TABLE VIEW =============
log "Creating web UI with TABLE VIEW at /var/www/flipbook/web/..."

cat > /var/www/flipbook/web/index.html << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes">
    <link rel="icon" href="https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/pdf_flipbook.png" type="image/png">
    <link rel="apple-touch-icon" href="https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/pdf_flipbook.png" sizes="180x180">
    <link rel="icon" type="image/png" href="https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/pdf_flipbook.png" sizes="192x192">
    <link rel="icon" type="image/png" href="https://raw.githubusercontent.com/igiteam/pdftoflipbook/refs/heads/main/pdf_flipbook.png" sizes="512x512">
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
        
        /* URL Input Section */
        .url-section {
            margin: 20px 0;
            text-align: center;
            position: relative;
        }
        .divider {
            border-top: 1px solid rgba(255,255,255,0.1);
            margin: 20px 0;
            position: relative;
        }
        .divider span {
            position: relative;
            top: -12px;
            background: rgba(30,30,50,0.9);
            padding: 0 15px;
            color: #888;
            font-size: 14px;
        }
        .url-input {
            width: 100%;
            padding: 14px 16px;
            border-radius: 12px;
            border: 1px solid rgba(255,255,255,0.2);
            background: rgba(0,0,0,0.3);
            color: white;
            font-size: 14px;
            transition: all 0.3s ease;
        }
        .url-input:focus {
            outline: none;
            border-color: #667eea;
            background: rgba(0,0,0,0.5);
        }
        .url-input::placeholder {
            color: #666;
        }
        .url-hint {
            font-size: 11px;
            color: #666;
            margin-top: 8px;
        }
        
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
        
        /* TABLE VIEW for History */
        .table-wrapper { overflow-x: auto; margin-top: 20px; }
        .data-table {
            width: 100%;
            border-collapse: collapse;
            font-size: 14px;
        }
        .data-table th {
            text-align: left;
            padding: 16px 12px;
            background: rgba(0,0,0,0.4);
            color: #667eea;
            border-bottom: 2px solid rgba(102,126,234,0.3);
        }
        .data-table td {
            padding: 16px 12px;
            border-bottom: 1px solid rgba(255,255,255,0.08);
            vertical-align: middle;
        }
        .data-table tr:hover { background: rgba(102,126,234,0.1); }
        .thumbnail-cell { width: 70px; text-align: center; }
        .thumbnail-img {
            width: 50px;
            height: 50px;
            object-fit: cover;
            border-radius: 8px;
        }
        .link-cell a, .zip-cell a {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 6px 12px;
            border-radius: 8px;
            text-decoration: none;
        }
        .link-cell a { color: #10b981; background: rgba(16,185,129,0.1); }
        .link-cell a:hover { background: rgba(16,185,129,0.2); }
        .zip-cell a { color: #667eea; background: rgba(102,126,234,0.1); }
        .zip-cell a:hover { background: rgba(102,126,234,0.2); }
        .delete-cell button {
            background: rgba(239,68,68,0.15);
            border: 1px solid rgba(239,68,68,0.3);
            color: #ef4444;
            cursor: pointer;
            padding: 6px 12px;
            border-radius: 8px;
        }
        .delete-cell button:hover { background: rgba(239,68,68,0.3); }
        .timestamp { font-size: 11px; color: #666; white-space: nowrap; }
        .empty-row td { text-align: center; padding: 60px; color: #666; }
        
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
        .footer a { color: #667eea; text-decoration: none; cursor: pointer; }
        .footer a:hover { text-decoration: underline; }
        
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(10px); }
            to { opacity: 1; transform: translateY(0); }
        }
        
        @media (max-width: 768px) {
            .container { padding: 12px; }
            .header h1 { font-size: 32px; }
            .drop-zone { padding: 30px 20px; }
            .btn { padding: 10px 20px; font-size: 14px; }
            .data-table { font-size: 12px; }
            .thumbnail-cell { width: 50px; }
            .thumbnail-img { width: 35px; height: 35px; }
        }
    </style>
</head>
<body>
    <div class="container">   
        <div class="card">
            <h2>📄 Upload PDF or Enter URL</h2>
            
            <!-- Drop Zone for File Upload -->
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
            
            <!-- OR Divider -->
            <div class="divider">
                <span>OR</span>
            </div>
            
            <!-- URL Input Section -->
            <div class="url-section">
                <input type="url" id="pdfUrlInput" class="url-input" placeholder="https://example.com/document.pdf">
                <div class="url-hint">Enter a public PDF URL to convert directly</div>
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
                <div class="log-line log-info">✨ Ready! Drag & drop a PDF or enter a URL to start</div>
            </div>
            
            <div class="result-area" id="resultArea">
                <h3 style="margin-bottom: 15px;">🎉 Conversion Complete!</h3>
                <div class="result-links" id="resultLinks"></div>
            </div>
        </div>
        
        <div class="card" id="historyCard">
            <h2>📋 Converted PDFs</h2>
            <div class="table-wrapper">
                <table class="data-table">
                    <thead>
                        <tr><th>Cover</th><th>Title</th><th>HTML</th><th>ZIP</th><th>Created</th><th></th></tr>
                    </thead>
                    <tbody id="historyBody">
                        <tr class="empty-row"><td colspan="6">No flipbooks yet. Upload your first PDF!</td></tr>
                    </tbody>
                </table>
            </div>
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
                <strong>Check progress:</strong>
                <div class="code-block" id="progressExample"></div>
            </div>
        </div>
        
        <div class="footer">
            Powered by Turn.js | PDF to FlipBook v2.1 (OG Image Edition)<br>
            <a href="/api/history" target="_blank">📰 History</a> | 
            <a href="/api/jobs" target="_blank">📊 All Jobs</a> | 
            <a href="/health" target="_blank">💚 Health Check</a> | 
            <a href="/queue/stats" target="_blank">📈 Queue Stats</a> | 
            <a href="/api/og/stats" target="_blank">🖼️ OG Stats</a>
            <a href="/og-upload.html" target="_blank">🏞 OG Template Manager</a>
        </div>
    </div>
    <script>
        let currentFile = null;
        let currentPdfUrl = null;
        let isProcessing = false;
        let progressInterval = null;
        let currentJobId = null;
        
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
        
        function formatDate(timestamp) {
            if (!timestamp) return 'N/A';
            return new Date(timestamp * 1000).toLocaleString();
        }
        
        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }
        
        function showConversionResult(result) {
            const resultLinks = document.getElementById('resultLinks');
            resultLinks.innerHTML = `
                <a href="${result.html_url}" class="result-link" target="_blank">📖 View Flipbook</a>
                <a href="${result.zip_url}" class="result-link" target="_blank">📦 Download ZIP</a>
                ${result.thumbnail_url ? `<a href="${result.thumbnail_url}" class="result-link" target="_blank">🖼️ Thumbnail</a>` : ''}
            `;
            document.getElementById('resultArea').classList.add('show');
            addLog(`🎉 Conversion complete! View your flipbook at: ${result.html_url}`, 'success');
        }
        
        async function loadHistory() {
            try {
                const response = await fetch('/api/history');
                const data = await response.json();
                const history = data.history || [];
                const tbody = document.getElementById('historyBody');
                
                if (history.length === 0) {
                    tbody.innerHTML = '<tr class="empty-row"><td colspan="6">No flipbooks yet. Upload your first PDF!</td></tr>';
                    return;
                }
                
                tbody.innerHTML = history.map(item => `
                    <tr>
                        <td class="thumbnail-cell">${item.thumbnail_url ? `<img src="${item.thumbnail_url}" class="thumbnail-img" onerror="this.src='data:image/svg+xml,%3Csvg xmlns=%27http://www.w3.org/2000/svg%27 width=%2750%27 height=%2750%27%3E%3Crect width=%2750%27 height=%2750%27 fill=%27%23333%27/%3E%3Ctext x=%2750%25%27 y=%2750%25%27 text-anchor=%27middle%27 dy=%27.3em%27 fill=%27%23666%27%3E📄%3C/text%3E%3C/svg%3E'">` : '<div style="width:50px;height:50px;background:rgba(255,255,255,0.1);border-radius:8px;display:flex;align-items:center;justify-content:center;">📄</div>'}</td>
                        <td>${escapeHtml(item.display_title || item.title)}</td>
                        <td class="link-cell"><a href="${item.html_url}" target="_blank">📖 View</a></td>
                        <td class="zip-cell"><a href="${item.zip_url}" target="_blank">📦 ZIP</a></td>
                        <td class="timestamp">${formatDate(item.timestamp)}</td>
                        <td class="delete-cell"><button onclick="deleteFlipbook('${item.id}')">🗑️ Delete</button></td>
                    </tr>
                `).join('');
            } catch (error) {
                console.error('Failed to load history:', error);
            }
        }
        
        async function deleteFlipbook(id) {
            if (!confirm('Delete this flipbook? This cannot be undone.')) return;
            try {
                const response = await fetch(`/api/history/${id}`, { method: 'DELETE' });
                if (response.ok) {
                    addLog('Flipbook deleted successfully', 'success');
                    loadHistory();
                } else {
                    addLog('Failed to delete flipbook', 'error');
                }
            } catch (error) {
                addLog(`Failed to delete: ${error.message}`, 'error');
            }
        }
        
        function startProgressTracking(jobId) {
            if (progressInterval) clearInterval(progressInterval);
            
            progressInterval = setInterval(async () => {
                try {
                    const response = await fetch(`/api/progress/${jobId}`);
                    const progress = await response.json();
                    
                    if (progress.percent !== undefined) {
                        document.getElementById('progressFill').style.width = `${progress.percent}%`;
                        
                        let text = '';
                        if (progress.stage === 'converting' && progress.currentPage && progress.totalPages) {
                            text = `🎨 Converting page ${progress.currentPage}/${progress.totalPages} (${progress.percent}%)`;
                        } else if (progress.stage === 'downloading') {
                            text = `⬇️ Downloading PDF... (${progress.percent}%)`;
                        } else if (progress.stage === 'analyzing') {
                            text = `🔍 Analyzing PDF... (${progress.percent}%)`;
                        } else if (progress.stage === 'starting') {
                            text = `🚀 Starting conversion... (${progress.percent}%)`;
                        } else if (progress.stage === 'uploaded') {
                            text = `📤 File uploaded, processing... (${progress.percent}%)`;
                        } else if (progress.stage === 'complete') {
                            text = `✅ Complete! (${progress.percent}%)`;
                        } else if (progress.stage === 'error') {
                            text = `❌ Error: ${progress.error || 'Unknown error'}`;
                        } else {
                            text = `${progress.stage || 'Processing'}... ${progress.percent}%`;
                        }
                        
                        document.getElementById('progressText').textContent = text;
                        
                        if (progress.stage === 'complete') {
                            clearInterval(progressInterval);
                            progressInterval = null;
                            document.getElementById('progressFill').style.width = '100%';
                            addLog('✅ Conversion complete!', 'success');
                            loadHistory();
                            setTimeout(() => {
                                document.getElementById('progressContainer').style.display = 'none';
                                isProcessing = false;
                                document.getElementById('convertBtn').disabled = false;
                            }, 2000);
                        } else if (progress.stage === 'error') {
                            clearInterval(progressInterval);
                            progressInterval = null;
                            addLog(`❌ Conversion failed: ${progress.error}`, 'error');
                            setTimeout(() => {
                                document.getElementById('progressContainer').style.display = 'none';
                                isProcessing = false;
                                document.getElementById('convertBtn').disabled = false;
                            }, 3000);
                        }
                    }
                } catch (error) {
                    console.error('Progress tracking error:', error);
                }
            }, 1000);
        }
        
        async function convertPDF() {
            if (isProcessing) return;
            
            // Determine mode: URL or File
            const isUrlMode = currentPdfUrl && currentPdfUrl.trim() !== '' && !currentFile;
            
            if (!isUrlMode && !currentFile) {
                addLog('Please select a PDF file or enter a URL first', 'error');
                return;
            }
            
            isProcessing = true;
            currentJobId = null;
            document.getElementById('convertBtn').disabled = true;
            document.getElementById('progressContainer').style.display = 'block';
            document.getElementById('resultArea').classList.remove('show');
            document.getElementById('progressFill').style.width = '0%';
            document.getElementById('progressText').textContent = isUrlMode ? 'Starting URL conversion...' : 'Preparing upload...';
            
            if (isUrlMode) {
                // URL MODE - Call /api/convert endpoint
                addLog(`Converting PDF from URL: ${currentPdfUrl}`, 'info');
                
                try {
                    const tokenParam = apiToken ? `&token=${apiToken}` : '';
                    const response = await fetch(`/api/convert?url=${encodeURIComponent(currentPdfUrl)}${tokenParam}`);
                    const result = await response.json();
                    
                    if (result.success) {
                        if (result.cached) {
                            addLog(`✅ Using cached version!`, 'success');
                            showConversionResult(result);
                            isProcessing = false;
                            document.getElementById('convertBtn').disabled = false;
                            document.getElementById('progressContainer').style.display = 'none';
                            loadHistory();
                        } else if (result.job_id) {
                            currentJobId = result.job_id;
                            addLog(`✅ Conversion started! Job ID: ${result.job_id}`, 'success');
                            addLog(`📊 Tracking progress...`, 'info');
                            startProgressTracking(result.job_id);
                        } else {
                            addLog(`❌ Failed to start conversion`, 'error');
                            isProcessing = false;
                            document.getElementById('convertBtn').disabled = false;
                            setTimeout(() => {
                                document.getElementById('progressContainer').style.display = 'none';
                            }, 2000);
                        }
                    } else {
                        addLog(`❌ Error: ${result.error || result.message || 'Unknown error'}`, 'error');
                        isProcessing = false;
                        document.getElementById('convertBtn').disabled = false;
                        setTimeout(() => {
                            document.getElementById('progressContainer').style.display = 'none';
                        }, 2000);
                    }
                } catch (error) {
                    addLog(`❌ Error: ${error.message}`, 'error');
                    isProcessing = false;
                    document.getElementById('convertBtn').disabled = false;
                    setTimeout(() => {
                        document.getElementById('progressContainer').style.display = 'none';
                    }, 2000);
                }
            } else {
                // FILE UPLOAD MODE
                const formData = new FormData();
                formData.append('pdf', currentFile);
                
                addLog(`Uploading PDF: ${currentFile.name} (${formatFileSize(currentFile.size)})`, 'info');
                
                try {
                    const xhr = new XMLHttpRequest();
                    
                    xhr.upload.addEventListener('progress', (e) => {
                        if (e.lengthComputable) {
                            const percentComplete = Math.round((e.loaded / e.total) * 100);
                            document.getElementById('progressFill').style.width = `${percentComplete}%`;
                            document.getElementById('progressText').textContent = `📤 Uploading: ${percentComplete}% (${formatFileSize(e.loaded)} / ${formatFileSize(e.total)})`;
                            
                            if (percentComplete % 25 === 0 && percentComplete > 0) {
                                addLog(`Upload progress: ${percentComplete}%`, 'info');
                            }
                        }
                    });
                    
                    xhr.onload = async () => {
                        if (xhr.status === 200) {
                            const result = JSON.parse(xhr.responseText);
                            
                            if (result.success && result.job_id) {
                                currentJobId = result.job_id;
                                addLog(`✅ Upload complete! Processing started (Job ID: ${result.job_id})`, 'success');
                                addLog(`📊 Tracking progress in real-time...`, 'info');
                                startProgressTracking(result.job_id);
                            } else {
                                addLog(`❌ Upload failed: ${result.error || 'Unknown error'}`, 'error');
                                isProcessing = false;
                                document.getElementById('convertBtn').disabled = false;
                                setTimeout(() => {
                                    document.getElementById('progressContainer').style.display = 'none';
                                }, 2000);
                            }
                        } else {
                            addLog(`❌ Upload failed: HTTP ${xhr.status}`, 'error');
                            isProcessing = false;
                            document.getElementById('convertBtn').disabled = false;
                            setTimeout(() => {
                                document.getElementById('progressContainer').style.display = 'none';
                            }, 2000);
                        }
                    };
                    
                    xhr.onerror = () => {
                        addLog(`❌ Upload failed: Network error`, 'error');
                        isProcessing = false;
                        document.getElementById('convertBtn').disabled = false;
                        setTimeout(() => {
                            document.getElementById('progressContainer').style.display = 'none';
                        }, 2000);
                    };
                    
                    xhr.open('POST', '/api/upload');
                    xhr.send(formData);
                    
                } catch (error) {
                    addLog(`❌ Error: ${error.message}`, 'error');
                    isProcessing = false;
                    document.getElementById('convertBtn').disabled = false;
                    setTimeout(() => {
                        document.getElementById('progressContainer').style.display = 'none';
                    }, 2000);
                }
            }
        }
        
        // Drag & Drop handlers
        function handleDrop(e) {
            e.preventDefault();
            document.getElementById('dropZone').classList.remove('drag-over');
            const files = e.dataTransfer.files;
            if (files.length > 0 && files[0].type === 'application/pdf') {
                currentFile = files[0];
                currentPdfUrl = null;
                document.getElementById('pdfUrlInput').value = '';
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
                    currentPdfUrl = null;
                    document.getElementById('pdfUrlInput').value = '';
                    document.getElementById('fileName').textContent = currentFile.name;
                    document.getElementById('fileSize').textContent = formatFileSize(currentFile.size);
                    document.getElementById('fileInfo').classList.add('show');
                    document.getElementById('convertBtn').disabled = false;
                    addLog(`PDF selected: ${currentFile.name}`, 'success');
                }
            };
            input.click();
        }
        
        // URL Input handler
        const pdfUrlInput = document.getElementById('pdfUrlInput');
        pdfUrlInput.addEventListener('input', function() {
            const url = this.value.trim();
            if (url !== '') {
                currentPdfUrl = url;
                currentFile = null;
                document.getElementById('fileInfo').classList.remove('show');
                document.getElementById('convertBtn').disabled = false;
                addLog(`URL entered: ${url}`, 'info');
            } else {
                currentPdfUrl = null;
                document.getElementById('convertBtn').disabled = true;
            }
        });
        
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
            zip_url: "/output/flipbook_hash.zip",
            thumbnail_url: "/weserv/?url=..."
        }, null, 2);
        document.getElementById('curlExample').textContent = `curl -X POST ${domain}/api/upload -F "pdf=@document.pdf"`;
        document.getElementById('progressExample').textContent = `${domain}/api/progress/YOUR_JOB_ID`;
        
        // Event listeners
        document.getElementById('dropZone').addEventListener('dragover', handleDragOver);
        document.getElementById('dropZone').addEventListener('dragleave', handleDragLeave);
        document.getElementById('dropZone').addEventListener('drop', handleDrop);
        document.getElementById('dropZone').addEventListener('click', selectFile);
        document.getElementById('convertBtn').addEventListener('click', convertPDF);
        document.getElementById('clearLogsBtn').addEventListener('click', clearLogs);
        
        // Load history on page load and refresh every 10 seconds
        loadHistory();
        setInterval(loadHistory, 10000);
        
        addLog('Web UI ready! Drag & drop a PDF or enter a URL', 'success');
        addLog('✨ Real-time progress tracking enabled', 'success');
        addLog('🖼️ OG images will be generated automatically for social sharing', 'success');
        addLog('📊 Queue supports up to 3 concurrent conversions', 'info');
    </script>
</body>
</html>
HTML_EOF



# Create PM2 ecosystem file with DOMAIN_NAME
log "Creating PM2 ecosystem configuration..."
cat > /opt/ecosystem.config.js << EOF
module.exports = {
    apps: [
        {
            name: 'flipbook-api',
            cwd: '/opt/flipbook-api',
            script: 'server.js',
            interpreter: 'node',
            node_args: '--max-old-space-size=${NODE_MEMORY}',
            watch: false,
            instances: 1,
            exec_mode: 'fork',
            max_memory_restart: '${NODE_MEMORY}M',
            env: {
                NODE_ENV: 'production',
                PORT: 3000,
                API_TOKEN: '$API_TOKEN',
                DOMAIN_NAME: '$DOMAIN_NAME',
                NODE_VERSION: '22',
                DISCORD_WEBHOOKS: '$DISCORD_WEBHOOKS'
            }
        }
    ]
};
EOF

# Start PM2 service
log "Starting PM2 service..."
pm2 delete flipbook-api 2>/dev/null || true
pm2 start /opt/ecosystem.config.js
pm2 save
pm2 startup

# Create edit script for OG template
cat > /usr/local/bin/edit-og << 'EDIT_SCRIPT'
#!/bin/bash
echo "========================================="
echo "  OG Image Template Editor"
echo "========================================="
echo ""
echo "File: /opt/flipbook-api/og-template.html"
echo ""
echo "Variables you can use:"
echo "  {{TITLE}}      - Flipbook title"
echo "  {{PAGE_COUNT}} - Number of pages"
echo "  {{THUMBNAIL}}  - Cover image URL"
echo "  {{DOMAIN}}     - Your website"
echo "  {{DATE}}       - Creation date"
echo ""
echo "Opening editor..."
sleep 1

nano /opt/flipbook-api/og-template.html

echo ""
echo "Template saved! Restarting API..."
pm2 restart flipbook-api
echo ""
echo "✅ Done! Test with: curl -s -o test.png https://$(cat /opt/flipbook-api/domain.txt 2>/dev/null)/api/og/YOUR_ID"
EDIT_SCRIPT

chmod +x /usr/local/bin/edit-og

# Save domain for the edit script
echo "$DOMAIN_NAME" > $FLIPBOOK_DIR/domain.txt
log "✅ Created edit-og command"

# Create OG test script
cat > /opt/test-og.sh << 'TEST_OG'
#!/bin/bash
DOMAIN=$(cat /opt/flipbook-api/domain.txt 2>/dev/null)
if [ -z "$DOMAIN" ]; then
    echo "Domain not found"
    exit 1
fi

echo "=== OG Image Test ==="
echo ""

# Get first flipbook ID
FLIPBOOK_ID=$(curl -s "https://$DOMAIN/api/history" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$FLIPBOOK_ID" ]; then
    echo "❌ No flipbooks found. Upload a PDF first."
    exit 1
fi

echo "Testing with ID: $FLIPBOOK_ID"
echo ""

# Test direct OG endpoint
echo "1. Testing direct OG endpoint..."
curl -s -o /tmp/og-direct.png "https://$DOMAIN/api/og/$FLIPBOOK_ID"
if [ -f /tmp/og-direct.png ] && [ $(stat -c%s /tmp/og-direct.png) -gt 10000 ]; then
    echo "   ✅ Direct OG: $(du -h /tmp/og-direct.png | cut -f1)"
else
    echo "   ❌ Direct OG failed"
fi

# Test via Weserv
echo "2. Testing OG via Weserv (cached)..."
curl -s -o /tmp/og-weserv.png "https://$DOMAIN/weserv/?url=https://$DOMAIN/api/og/$FLIPBOOK_ID&w=600&h=315"
if [ -f /tmp/og-weserv.png ] && [ $(stat -c%s /tmp/og-weserv.png) -gt 5000 ]; then
    echo "   ✅ Weserv OG: $(du -h /tmp/og-weserv.png | cut -f1)"
else
    echo "   ❌ Weserv OG failed"
fi

# Test OG stats
echo "3. Testing OG stats endpoint..."
curl -s "https://$DOMAIN/api/og/stats" | python3 -m json.tool 2>/dev/null | head -10

echo ""
echo "URLs:"
echo "  Direct: https://$DOMAIN/api/og/$FLIPBOOK_ID"
echo "  Weserv: https://$DOMAIN/weserv/?url=https://$DOMAIN/api/og/$FLIPBOOK_ID&w=1200&h=630"
echo ""
echo "To edit template: edit-og"
TEST_OG

chmod +x /opt/test-og.sh
log "✅ Created OG test script at /opt/test-og.sh"

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

# Create nginx configuration with Weserv proxy
log "Creating nginx reverse proxy configuration with Weserv support..."

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
    
    # Weserv image processing proxy
    location /weserv/ {
        rewrite ^/weserv/(.*) /$1 break;
        proxy_pass http://127.0.0.1:8080/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_cache_valid 200 30d;
        add_header X-Cache-Status $upstream_cache_status;
        expires 30d;
    }
    
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
    
    # OG Image Generation endpoint
    location /api/og/ {
        proxy_pass http://127.0.0.1:3000/api/og/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_cache_valid 200 30d;
        expires 30d;
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
        
        # Important: Preserve query parameters (like ?url=...)
        proxy_set_header X-Original-URI $request_uri;
        
        # Add CORS headers for API access
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, DELETE, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization,X-API-Token' always;
        
        # Handle preflight requests
        if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, DELETE, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization,X-API-Token';
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
        }
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
    
    # Weserv image processing proxy
    location /weserv/ {
        rewrite ^/weserv/(.*) /$1 break;
        proxy_pass http://127.0.0.1:8080/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_cache_valid 200 30d;
        add_header X-Cache-Status $upstream_cache_status;
        expires 30d;
    }
    
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
    
    # OG Image Generation endpoint
    location /api/og/ {
        proxy_pass http://127.0.0.1:3000/api/og/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_cache_valid 200 30d;
        expires 30d;
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
Requires=redis-server.service docker.service
After=redis-server.service docker.service network-online.target nginx.service
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

# Check Weserv
log "Testing Weserv..."
sleep 3
if curl -s "http://localhost:8080/?il" 2>/dev/null | grep -q "svg\|png\|jpg"; then
    log "✅ Weserv is working"
else
    warn "Weserv may not be responding correctly"
fi

# Test OG endpoint
log "Testing OG endpoint..."
sleep 2
if curl -s "http://localhost:3000/api/og/stats" 2>/dev/null | grep -q "version"; then
    log "✅ OG endpoint working"
else
    warn "OG endpoint may need manual check"
fi

# Test progress endpoint
log "Testing progress endpoint..."
if curl -s "http://localhost:3000/api/progress/test123" | grep -q "percent"; then
    log "✅ Progress tracking endpoint working"
else
    warn "Progress endpoint may need manual check"
fi

# Create monitoring script with Weserv check
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

# Check Weserv container
if ! docker ps --format "{{.Names}}" | grep -q weserv; then
    log_message "Weserv not running - restarting"
    docker rm -f weserv 2>/dev/null
    docker run -d --name weserv --restart unless-stopped -p 8080:80 -e MEMORY_LIMIT=256M ghcr.io/weserv/images:5.x
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

echo "=== PDF to FlipBook API Test Suite v2.1 (OG Image Edition) ==="
echo "Domain: $DOMAIN_NAME"
echo "SSL Enabled: $SSL_ENABLED"
echo "Weserv: Enabled"
echo "OG Images: Enabled (@vercel/og)"
echo "Progress Tracking: Enabled"
echo "Table View: Enabled"
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

# Test 3: Weserv endpoint
echo "3. Testing Weserv endpoint..."
curl -s -o /dev/null -w "%{http_code}" "$PROTOCOL://$DOMAIN_NAME/weserv/?url=https://$DOMAIN_NAME/favicon.ico&w=100" | grep -q "200\|302" && echo "   ✅ Weserv endpoint working" || echo "   ❌ Weserv endpoint not working"

# Test 4: OG endpoint
echo "4. Testing OG endpoint..."
curl -s "$PROTOCOL://$DOMAIN_NAME/api/og/stats" | grep -q "version" && echo "   ✅ OG endpoint working" || echo "   ❌ OG endpoint failed"

# Test 5: Progress endpoint
echo "5. Testing progress endpoint..."
curl -s "$PROTOCOL://$DOMAIN_NAME/api/progress/test123" | grep -q "percent" && echo "   ✅ Progress endpoint working" || echo "   ❌ Progress endpoint failed"

# Test 6: API Convert endpoint (JSON)
echo "6. Testing API convert endpoint..."
curl -s "$PROTOCOL://$DOMAIN_NAME/api/convert?url=$TEST_URL" | grep -q "success" && echo "   ✅ API convert working" || echo "   ❌ API convert failed"

# Test 7: Queue stats (JSON)
echo "7. Testing queue stats (JSON)..."
curl -s "$PROTOCOL://$DOMAIN_NAME/queue/stats" | grep -q "waiting" && echo "   ✅ Queue stats working" || echo "   ❌ Queue stats failed"

# Test 8: History API (JSON)
echo "8. Testing history API (JSON)..."
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
echo "  Progress: $PROTOCOL://$DOMAIN_NAME/api/progress/JOB_ID"
echo "  OG Stats: $PROTOCOL://$DOMAIN_NAME/api/og/stats"
echo "  Queue:   $PROTOCOL://$DOMAIN_NAME/queue/stats"
echo ""
echo "Architecture: WineJS-style (API serves JSON only, nginx serves static HTML)"
echo "Enhanced Features: Weserv thumbnails, Progress tracking, Favicons, Table View, OG Images (@vercel/og)"
EOF

chmod +x /opt/test-flipbook.sh

# Create quick test
cat > /opt/quick-test.sh << 'EOF'
#!/bin/bash
DOMAIN_NAME="$DOMAIN_NAME"
SSL_ENABLED=$SSL_ENABLED

# Fix: Properly set PROTOCOL
if [ "$SSL_ENABLED" = "true" ]; then
    PROTOCOL="https"
else
    PROTOCOL="http"
fi

echo "Quick FlipBook Test (OG Image Edition)"
echo "=========================================="
echo ""

echo "1. Testing API (JSON)..."
curl -s "$PROTOCOL://$DOMAIN_NAME/health" | grep -q "OK" && echo "   ✅ API OK (JSON)" || echo "   ❌ API FAILED"

echo "2. Testing Web UI (HTML served by nginx)..."
curl -s "$PROTOCOL://$DOMAIN_NAME/" | grep -q "PDF to FlipBook" && echo "   ✅ Web UI OK (static HTML)" || echo "   ❌ Web UI FAILED"

echo "3. Testing Weserv..."
curl -s -o /dev/null -w "   ✅ Weserv: HTTP %{http_code}\n" "$PROTOCOL://$DOMAIN_NAME/weserv/?url=https://$DOMAIN_NAME/favicon.ico&w=100"

echo "4. Testing OG endpoint..."
curl -s "$PROTOCOL://$DOMAIN_NAME/api/og/stats" | head -c 200 && echo "..."

echo "5. Testing API endpoints..."
curl -s "$PROTOCOL://$DOMAIN_NAME/queue/stats" | python3 -m json.tool 2>/dev/null | head -5 || curl -s "$PROTOCOL://$DOMAIN_NAME/queue/stats"

echo ""
echo "Architecture:"
echo "  - Web UI:  nginx serving /var/www/flipbook/web/ (TABLE VIEW)"
echo "  - API:     Node.js on port 3000 (JSON only)"
echo "  - Output:  nginx serving /var/www/flipbook/output/"
echo "  - Weserv:  Docker container on port 8080 (thumbnails)"
echo "  - OG:      @vercel/og for social preview images"
echo ""
echo "Web UI: $PROTOCOL://$DOMAIN_NAME/"
echo "API:    $PROTOCOL://$DOMAIN_NAME/api/convert?url=YOUR_PDF_URL"
echo "Upload: curl -X POST $PROTOCOL://$DOMAIN_NAME/api/upload -F \"pdf=@document.pdf\""
echo "OG:     $PROTOCOL://$DOMAIN_NAME/api/og/YOUR_FLIPBOOK_ID"
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
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      PDF TO FLIPBOOK API v2.1 SETUP COMPLETE!                    ║${NC}"
echo -e "${GREEN}║      Enhanced Features: Weserv + Progress + Table View + OG     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
log "Your PDF to FlipBook server is ready!"
echo ""
info "🌐 Web Interface (Static HTML with TABLE VIEW - served by nginx):"
if [ "$SSL_ENABLED" = true ]; then
    echo "  🔒 https://$DOMAIN_NAME/"
else
    echo "  🌐 http://$DOMAIN_NAME/"
fi
echo ""
info "🔌 API Endpoints (JSON only - served by Node.js):"
echo "  • GET  /api/convert?url=PDF_URL       - Convert PDF by URL"
echo "  • POST /api/upload                     - Upload PDF file"
echo "  • GET  /api/history                    - View conversion history"
echo "  • GET  /api/progress/:jobId           - Track conversion progress"
echo "  • GET  /api/og/:flipbookId            - Generate OG preview image"
echo "  • GET  /api/og/stats                  - OG image stats"
echo "  • GET  /queue/stats                    - Queue statistics"
echo "  • POST /cache/clear-all                - Clear all cached flipbooks"
echo ""
info "🖼️ Enhanced Features:"
echo "  • 🐳 Weserv container - Dynamic on-demand thumbnails"
echo "  • 🎨 @vercel/og - Beautiful social media preview images"
echo "  • 📊 Progress tracking - Real-time conversion status"
echo "  • 📋 Table View - Clean tabular history with cover images"
echo "  • 🎯 Favicons - Custom bookmark icons in flipbook HTML"
echo ""
info "🎨 OG Image Customization:"
echo "  • Web Uploader:   https://$DOMAIN_NAME/og-upload.html"
echo "  • Default Template: https://$DOMAIN_NAME/templates/og-design-default.js"
echo "  • Edit via SSH:   nano /opt/flipbook-api/og-generator.js"
echo "  • Preview OG:     https://$DOMAIN_NAME/api/og/YOUR_FLIPBOOK_ID"
echo ""
info "📢 Discord Webhook Management:"
if [ -n "$DISCORD_WEBHOOKS" ]; then
    echo "  • Current: $(echo $DISCORD_WEBHOOKS | tr ',' '\n' | wc -l) webhook(s) configured"
else
    echo "  • Current: No webhooks configured"
fi
echo "  • Add webhooks:   export DISCORD_WEBHOOKS=\"url1,url2\" && pm2 restart flipbook-api --update-env"
echo "  • Verify:         pm2 env 0 | grep DISCORD"
echo ""
info "Architecture (WineJS-style + Enhanced):"
echo "  📁 Web UI:  /var/www/flipbook/web/     - Served by nginx (static, TABLE VIEW)"
echo "  📁 Output:  /var/www/flipbook/output/  - Served by nginx (static)"
echo "  🔧 API:     /opt/flipbook-api/         - Node.js JSON API on port 3000"
echo "  🐳 Weserv:  Docker container on port 8080 - Dynamic thumbnails"
echo "  🎨 OG:      @vercel/og on Node.js 22  - Social preview images"
echo ""
info "Examples:"
if [ -n "$API_TOKEN" ]; then
    echo "  Web UI: https://$DOMAIN_NAME/?token=$API_TOKEN"
    echo "  API:    https://$DOMAIN_NAME/api/convert?url=https://example.com/doc.pdf&token=$API_TOKEN"
    echo "  Upload: curl -X POST https://$DOMAIN_NAME/api/upload -F \"pdf=@doc.pdf\" -H \"X-API-Token: $API_TOKEN\""
    echo "  OG:     https://$DOMAIN_NAME/api/og/FLIPBOOK_ID"
    echo "  Progress: https://$DOMAIN_NAME/api/progress/JOB_ID"
else
    echo "  Web UI: https://$DOMAIN_NAME/"
    echo "  API:    https://$DOMAIN_NAME/api/convert?url=https://example.com/doc.pdf"
    echo "  Upload: curl -X POST https://$DOMAIN_NAME/api/upload -F \"pdf=@document.pdf\""
    echo "  OG:     https://$DOMAIN_NAME/api/og/FLIPBOOK_ID"
    echo "  Progress: https://$DOMAIN_NAME/api/progress/JOB_ID"
fi
echo ""
info "Management:"
echo "  /opt/quick-test.sh             # Quick test"
echo "  /opt/test-flipbook.sh          # Full test"
echo "  /opt/test-og.sh                # OG image test"
echo "  edit-og                        # Edit OG template"
echo "  docker logs weserv             # View Weserv logs"
echo "  docker restart weserv          # Restart Weserv"
echo "  pm2 logs flipbook-api          # View API logs"
echo "  pm2 restart flipbook-api       # Restart API service"
echo "  systemctl restart nginx        # Restart web server"
echo ""
info "Output Location:"
echo "  HTML: https://$DOMAIN_NAME/output/flipbook_HASH/filename_flipbook.html"
echo "  ZIP:  https://$DOMAIN_NAME/output/flipbook_HASH.zip"
echo "  OG:   https://$DOMAIN_NAME/api/og/FLIPBOOK_ID"
echo "  Thumbnail: https://$DOMAIN_NAME/weserv/?url=https://$DOMAIN_NAME/output/flipbook_HASH/page_1.png&w=100&h=100"

# Final restart
log "Performing final restart..."
systemctl restart nginx
pm2 restart all

echo ""
log "✨ Setup complete! Your PDF to FlipBook server is ready to use!"
log "🌐 Open https://$DOMAIN_NAME/ in your browser to start converting PDFs!"
log "🔧 API is pure JSON at https://$DOMAIN_NAME/api/convert?url=PDF_URL"
log "🎨 OG images auto-generated for social sharing at https://$DOMAIN_NAME/api/og/YOUR_ID"
log "📁 Web UI is static HTML served by nginx with TABLE VIEW"
log "🖼️ Thumbnails generated on-demand by Weserv"
echo ""

# Display architecture summary with new components
echo -e "${CYAN}Updated Architecture (with Weserv + OG Images):${NC}"
echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│  nginx (port 443/80)                                            │"
echo "│    ├── /             → /var/www/flipbook/web/ (TABLE VIEW)      │"
echo "│    ├── /api/*        → http://127.0.0.1:3000/api/               │"
echo "│    ├── /api/og/*     → http://127.0.0.1:3000/api/og/            │"
echo "│    ├── /weserv/*     → http://127.0.0.1:8080/                   │"
echo "│    └── /output/*     → /var/www/flipbook/output/                │"
echo "│                                                                 │"
echo "│  Node.js API (port 3000) - Enhanced                             │"
echo "│    ├── /api/convert      (JSON)                                 │"
echo "│    ├── /api/upload       (JSON)                                 │"
echo "│    ├── /api/history      (JSON) - WITH thumbnail_url            │"
echo "│    ├── /api/progress     (JSON) - REAL-TIME TRACKING            │"
echo "│    ├── /api/og/:id       (PNG)  - @vercel/og SOCIAL PREVIEW     │"
echo "│    └── /queue/stats      (JSON)                                 │"
echo "│                                                                 │"
echo "│  Docker: Weserv (port 8080) - Dynamic image transformer         │"
echo "│    └── Converts page PNGs → Thumbnails on-demand                │"
echo "└─────────────────────────────────────────────────────────────────┘"

# This is the complete integrated script with all OG image generation features properly placed. Key changes made:
#     Node.js 22 instead of 18 (required for @vercel/og)
#     Added dependencies: @vercel/og, react, react-dom
#     Created OG template file (og-template.html) - editable HTML template for OG images
#     Created OG generator module (og-generator.js) - handles image generation using @vercel/og
#     Added OG endpoint in the main server.js - /api/og/:flipbookId
#     Added OG stats endpoint - /api/og/stats
#     Updated generateFlipbookHTML function - includes proper OG meta tags with Weserv-cached OG image URLs
#     Added nginx location block for /api/og/ with caching
#     Created edit script (edit-og) - easy template editing
#     Created test script (/opt/test-og.sh) - test OG image generation

# The OG images will:
#     Use the editable HTML template
#     Include flipbook title, page count, thumbnail (if available), and domain
#     Be cached for 1 year
#     Work seamlessly with Weserv for CDN caching
#     Auto-include in every generated flipbook's meta tags

# When someone requests the OG image (Discord, Twitter, Facebook)

# They call: https://{domain}/api/og/f8c61e41842267e99d06f431872a9484
# 1. This triggers the endpoint in server.js:

# app.get('/api/og/:flipbookId', async (req, res) => {
#     // Find the flipbook in history
#     const flipbook = conversionHistory.find(h => h.id === flipbookId);
    
#     // THIS LINE calls your og meta image generator
#     const { buffer, cacheKey, contentType } = await generateOGImage(flipbook, DOMAIN);
    
#     // Return the PNG image
#     res.send(buffer);
# });

# 2. generateOGImage is in og-generator.js:

# async function generateOGImage(flipbook, domain) {
#     // Gets the first page PNG
#     const firstPageUrl = `https://${domain}/output/flipbook_${flipbook.id}/${flipbook.title}_page_1.png`;
    
#     // Creates your og meta image design (blurred background + clear center)
#     const element = React.createElement(...);
    
#     // Renders to PNG
#     const response = new ImageResponse(element, { width: 1200, height: 630 });
    
#     return { buffer: Buffer.from(buffer) };
# }

# Current setup:
# Discord requests → /api/og/ID → generateOGImage() → Returns PNG
#                                     ↑
#                             This creates the blurred background + clear center

# HTML meta tag (ogImageWeserv):

# https://{domain}/weserv/?url=https://{domain}/api/og/ID&w=1200&h=630
#                                     ↑
#                             This calls the endpoint above