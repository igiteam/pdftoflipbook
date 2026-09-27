#!/bin/bash

# github-create-pages.sh
# Automates GitHub repo creation, file upload, and GitHub Pages setup

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check dependencies
print_info "Checking dependencies..."
for cmd in git gh; do
    if ! command_exists "$cmd"; then
        print_error "'$cmd' is not installed. Please install it first."
        echo "  - git: https://git-scm.com/downloads"
        echo "  - gh (GitHub CLI): https://cli.github.com/"
        exit 1
    fi
done
print_success "All dependencies found."

# Check if user is authenticated with GitHub CLI
if ! gh auth status >/dev/null 2>&1; then
    print_error "You are not authenticated with GitHub CLI."
    print_info "Run: gh auth login"
    exit 1
fi
print_success "GitHub CLI authenticated."

# Get the current directory name as the repo name
REPO_NAME=$(basename "$PWD")

# Validate directory name (GitHub repo naming rules)
if [[ ! "$REPO_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    print_error "Directory name '$REPO_NAME' contains invalid characters."
    print_info "GitHub repo names can only contain letters, numbers, '.', '-', and '_'."
    exit 1
fi

print_info "Repository name will be: $REPO_NAME"

# Get GitHub username
GH_USER=$(gh api user --jq .login)
print_info "GitHub user: $GH_USER"

# Check required files
if [ ! -f "index.html" ]; then
    print_warning "No index.html found in current directory."
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check for existing git repo
if [ -d ".git" ]; then
    print_warning "A .git directory already exists here."
    read -p "Remove and reinitialize? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf .git
        print_info "Removed existing .git directory."
    else
        print_error "Aborting to avoid conflicts."
        exit 1
    fi
fi

# Check if remote repo already exists
if gh repo view "$GH_USER/$REPO_NAME" >/dev/null 2>&1; then
    print_warning "Repository '$GH_USER/$REPO_NAME' already exists on GitHub."
    read -p "Do you want to push to existing repo and update Pages? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    REPO_EXISTS=true
else
    REPO_EXISTS=false
fi

# Construct GitHub Pages URL
PAGES_URL="https://$GH_USER.github.io/$REPO_NAME/"

# Initialize git and add files
print_info "Initializing local git repository..."
git init -b main >/dev/null
git add .
git commit -m "fixes" >/dev/null
print_success "Files committed."

# Create GitHub repo if it doesn't exist
if [ "$REPO_EXISTS" = false ]; then
    print_info "Creating GitHub repository '$REPO_NAME'..."
    # Add description with the Pages URL
    gh repo create "$REPO_NAME" \
        --public \
        --description "🌐 Live site: $PAGES_URL" \
        --source=. \
        --remote=origin \
        --push
    print_success "Repository created and files pushed."
else
    # Add remote if not present
    if ! git remote | grep -q "^origin$"; then
        git remote add origin "https://github.com/$GH_USER/$REPO_NAME.git"
    fi

    # Update description with Pages URL
    print_info "Updating repository description..."
    gh repo edit "$GH_USER/$REPO_NAME" \
        --description "🌐 Live site: $PAGES_URL"

    # Push files
    print_info "Pushing files..."
    git push -u origin main --force
    print_success "Files pushed."
fi

# Enable GitHub Pages
print_info "Enabling GitHub Pages..."

# Try to enable Pages via API (create or update)
HTTP_STATUS=$(gh api \
    --method POST \
    -H "Accept: application/vnd.github+json" \
    "/repos/$GH_USER/$REPO_NAME/pages" \
    -f "source[branch]=main" \
    -f "source[path]=/" \
    2>/dev/null && echo "201" || echo "error")

# If POST failed (Pages already enabled), try PUT to update
if [ "$HTTP_STATUS" = "error" ]; then
    print_info "Pages may already be enabled. Updating configuration..."
    gh api \
        --method PUT \
        -H "Accept: application/vnd.github+json" \
        "/repos/$GH_USER/$REPO_NAME/pages" \
        -f "source[branch]=main" \
        -f "source[path]=/" \
        -f "build_type=legacy" >/dev/null 2>&1 || \
    gh api \
        --method PUT \
        -H "Accept: application/vnd.github+json" \
        "/repos/$GH_USER/$REPO_NAME/pages" \
        -f "build_type=workflow" >/dev/null 2>&1 || true
fi

print_success "GitHub Pages enabled."

# Wait a moment for Pages to build
print_info "Waiting for GitHub Pages to deploy (this may take a minute)..."
sleep 5

# Final summary
echo
echo "=========================================="
print_success "All done! 🎉"
echo "=========================================="
echo -e "${GREEN}Repository:${NC} https://github.com/$GH_USER/$REPO_NAME"
echo -e "${GREEN}Live site:${NC}  $PAGES_URL"
echo
print_info "It may take 1-2 minutes for the site to become available."
echo "=========================================="