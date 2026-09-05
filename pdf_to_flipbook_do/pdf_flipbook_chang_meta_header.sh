#!/bin/bash

# ============================================
# FlipBook Shelf Meta Tags Updater
# Changes title and meta tags ONLY
# ============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}📝 FlipBook Shelf Meta Tags Updater${NC}"
echo ""

# Get domain
if [ -f "/opt/flipbook-api/domain.txt" ]; then
    DOMAIN=$(cat /opt/flipbook-api/domain.txt)
else
    read -p "Enter your domain: " DOMAIN
fi

SERVER_JS="/opt/flipbook-api/server.js"

if [ ! -f "$SERVER_JS" ]; then
    echo -e "${RED}❌ Server.js not found${NC}"
    exit 1
fi

# Get new values
echo ""
read -p "Enter new shelf title: " NEW_TITLE
read -p "Enter new description: " NEW_DESC
read -p "Enter icon URL (optional): " NEW_ICON

# Backup
cp "$SERVER_JS" "$SERVER_JS.backup.$(date +%s)"

# Update title in generateMagazineShelf
sed -i "s/generateMagazineShelf(\"[^\"]*\"/generateMagazineShelf(\"$NEW_TITLE\"/g" "$SERVER_JS"

# Update HTML title tag
sed -i "s/<title>[^<]*<\/title>/<title>$NEW_TITLE - Shelf Archive<\/title>/g" "$SERVER_JS"

# Update OG title
sed -i "s/<meta property=\"og:title\" content=\"[^\"]*\"/<meta property=\"og:title\" content=\"$NEW_TITLE - Shelf Archive\"/g" "$SERVER_JS"

# Update OG description
sed -i "s/<meta property=\"og:description\" content=\"[^\"]*\"/<meta property=\"og:description\" content=\"$NEW_DESC\"/g" "$SERVER_JS"

# Update Twitter title
sed -i "s/<meta name=\"twitter:title\" content=\"[^\"]*\"/<meta name=\"twitter:title\" content=\"$NEW_TITLE - Shelf Archive\"/g" "$SERVER_JS"

# Update Twitter description
sed -i "s/<meta name=\"twitter:description\" content=\"[^\"]*\"/<meta name=\"twitter:description\" content=\"$NEW_DESC\"/g" "$SERVER_JS"

# Update icon if provided
if [ -n "$NEW_ICON" ]; then
    sed -i "s|<link rel=\"icon\" href=\"[^\"]*\"|<link rel=\"icon\" href=\"$NEW_ICON\"|g" "$SERVER_JS"
    sed -i "s|<link rel=\"apple-touch-icon\" href=\"[^\"]*\"|<link rel=\"apple-touch-icon\" href=\"$NEW_ICON\"|g" "$SERVER_JS"
fi

# Restart
pm2 restart flipbook-api 2>/dev/null || systemctl restart flipbook

echo ""
echo -e "${GREEN}✅ Updated!${NC}"
echo -e "${CYAN}🌐 https://$DOMAIN/api/shelf${NC}"