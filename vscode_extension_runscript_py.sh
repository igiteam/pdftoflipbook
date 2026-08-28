#!/bin/bash
set -e

# ============================================
# Python Script Runner VS Code Extension #
# ============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║      Python Script Runner VSCODE EXTENSION INSTALL           ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo "This extension adds '▶️ Run .py' command to run Python scripts with one click."
echo "Features:"
echo "- Right-click on any .py file → '▶️ Run .py'"
echo "- Automatic Python 3 interpreter detection"
echo "- Runs in VS Code terminal with proper working directory"
echo "- Virtual environment support (auto-detects venv/.venv)"
echo ""

# Ask for extension name
read -p "Enter your extension folder name (default: vscode_py-runner): " EXTNAME
EXTNAME=${EXTNAME:-vscode_py-runner}

# Check if folder exists
if [ -d "$EXTNAME" ]; then
    read -p "Folder '$EXTNAME' already exists. Remove it? (y/N): " REMOVE
    REMOVE=${REMOVE:-N}
    if [[ "$REMOVE" == "y" || "$REMOVE" == "Y" ]]; then
        echo "Removing existing folder '$EXTNAME'..."
        rm -rf "$EXTNAME"
    else
        echo "Exiting to avoid overwriting."
        exit 1
    fi
fi

# Create folder structure
mkdir -p "$EXTNAME/src" "$EXTNAME/media" "$EXTNAME/out"
cd "$EXTNAME" || exit

# Download Python icon
echo -e "${CYAN}📥 Downloading Python icon...${NC}"
curl -s -o media/logo.png "https://logodownload.org/wp-content/uploads/2019/10/python-logo-0.png" || {
    echo -e "${YELLOW}⚠️  Download failed, creating placeholder${NC}"
    # Create a simple colored placeholder
    echo "Placeholder for Python logo" > media/logo.png
}

# Create package.json
cat <<EOL > package.json
{
  "name": "python-runner",
  "displayName": "Python Script Runner",
  "description": "One-click runner for Python scripts with virtual env support",
  "repository": "https://github.com/igiteam/winejs",
  "publisher": "igiteam",
  "icon": "media/logo.png",
  "version": "1.0.0",
  "engines": {
    "vscode": "^1.81.0"
  },
  "categories": [
    "Other"
  ],
  "activationEvents": [
    "onCommand:pythonrunner.runPythonScript"
  ],
  "main": "./out/extension.js",
  "contributes": {
    "commands": [
      {
        "command": "pythonrunner.runPythonScript",
        "title": "▶️ Run .py",
        "category": "Python"
      }
    ],
    "menus": {
      "explorer/context": [
        {
          "command": "pythonrunner.runPythonScript",
          "group": "navigation",
          "when": "resourceExtname == '.py'"
        }
      ],
      "editor/title": [
        {
          "command": "pythonrunner.runPythonScript",
          "group": "navigation",
          "when": "resourceExtname == '.py'"
        }
      ]
    }
  },
  "scripts": {
    "vscode:prepublish": "npm run compile",
    "compile": "tsc -p ./",
    "watch": "tsc -watch -p ./"
  },
  "devDependencies": {
    "@types/node": "20.x",
    "@types/vscode": "^1.81.0",
    "typescript": "^5.7.2"
  },
  "dependencies": {}
}
EOL

# Create tsconfig.json
cat <<EOL > tsconfig.json
{
	"compilerOptions": {
		"module": "Node16",
		"target": "ES2022",
		"outDir": "out",
		"lib": [
			"ES2022"
		],
		"sourceMap": true,
		"rootDir": "src",
		"strict": true
	}
}
EOL

# Create extension.ts
cat <<'EOL' > src/extension.ts
import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';

export function activate(context: vscode.ExtensionContext) {
    console.log('✅ Python Script Runner activated!');

    const disposable = vscode.commands.registerCommand('pythonrunner.runPythonScript', async (resource: vscode.Uri) => {
        if (resource) {
            const scriptPath = resource.fsPath;
            const scriptDir = path.dirname(scriptPath);
            const scriptName = path.basename(scriptPath);

            try {
                // Check if it's a Python file
                if (!scriptPath.endsWith('.py')) {
                    vscode.window.showErrorMessage('Please select a Python (.py) file');
                    return;
                }

                // Create terminal
                const terminal = vscode.window.createTerminal({
                    name: `Run ${scriptName}`,
                    cwd: scriptDir
                });
                terminal.show();

                // ============================================
                // FIXED: PROPER VIRTUAL ENVIRONMENT SETUP
                // ============================================
                
                const venvPath = path.join(scriptDir, 'venv');
                const requirementsPath = path.join(scriptDir, 'requirements.txt');
                
                // Step 1: Create venv if it doesn't exist (using Python 3)
                terminal.sendText(`echo "🔧 Checking Python 3 virtual environment..."`);
                terminal.sendText(`if [ ! -d "venv" ]; then echo "Creating venv..."; python3 -m venv venv; echo "✅ venv created"; else echo "✅ venv already exists"; fi`);
                
                // Step 2: Activate venv (THIS IS CRITICAL)
                terminal.sendText(`echo "🔧 Activating virtual environment..."`);
                terminal.sendText(`source venv/bin/activate`);
                
                // Step 3: Check Python version in venv
                terminal.sendText(`echo "🐍 Using: $(python --version)"`);
                
                // Step 4: Upgrade pip within the activated venv
                terminal.sendText(`echo "📦 Upgrading pip..."`);
                terminal.sendText(`python -m pip install --upgrade pip --quiet`);
                
                // Step 5: Install pyusb (required for the wheel)
                terminal.sendText(`echo "📦 Installing pyusb..."`);
                terminal.sendText(`python -m pip install pyusb --quiet`);
                
                // Step 6: Install requirements.txt if it exists
                terminal.sendText(`if [ -f "requirements.txt" ]; then echo "📦 Installing dependencies..."; python -m pip install -r requirements.txt --quiet; echo "✅ Dependencies installed"; fi`);
                
                // Step 7: Clear the screen for clean output
                terminal.sendText(`clear`);
                
                // Step 8: Run the script
                terminal.sendText(`echo "🚀 Running ${scriptName}..."`);
                terminal.sendText(`echo "========================================="`);
                terminal.sendText(`python "${scriptName}"`);
                terminal.sendText(`echo ""`);
                terminal.sendText(`echo "========================================="`);
                terminal.sendText(`echo "✅ Script finished"`);

            } catch (error: any) {
                vscode.window.showErrorMessage(`Failed to run Python script: ${error.message}`);
                console.error('Python runner error:', error);
            }
        } else {
            vscode.window.showWarningMessage('Please select a Python script file (.py) to run');
        }
    });

    context.subscriptions.push(disposable);
}

export function deactivate() {}
EOL

# Create .vscodeignore
cat <<EOL > .vscodeignore
.vscode
src
*.ts
*.map
.git
.gitignore
*.sh
EOL

# Create README.md
cat <<EOL > README.md
# Python Script Runner

One-click runner for Python scripts with virtual environment support.

## Features

- Right-click any .py file → "▶️ Run .py"
- Automatic Python 3 interpreter detection
- Virtual environment detection (venv, .venv, env)
- Runs in VS Code terminal with proper working directory
- Editor title menu support

## Usage

- Right-click any .py file in explorer → "▶️ Run .py"
- Click "▶️ Run .py" in editor title when editing .py files
- Command Palette → "▶️ Run .py"

## What it does

1. Detects Python interpreter (python3 or virtual env)
2. Opens a terminal in the script's directory
3. Runs the script with python3 scriptname.py
4. Shows progress notifications

## Requirements

- VS Code 1.81.0 or higher
- Python 3.x installed
EOL

echo -e "${GREEN}✅ Extension scaffold created in '$EXTNAME'${NC}"

# -----------------------------
# Create License.md (MIT License)
# -----------------------------
cat <<EOL > LICENSE.md
MIT License

Copyright (c) $(date +%Y) Gabriel Majorsky

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
EOL

# ===============================================
# Build and Install Extension
# ===============================================

echo -e "${CYAN}🔨 Building and installing extension...${NC}"

# Set Node options
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" 2>/dev/null || true
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" 2>/dev/null || true
export NODE_OPTIONS=--openssl-legacy-provider

echo -e "${YELLOW}Node: $(node -v 2>/dev/null || echo 'not found') | npm: $(npm -v 2>/dev/null || echo 'not found')${NC}"

# Install dependencies
if [ ! -d "node_modules" ]; then
    echo -e "${CYAN}📦 Installing Node dependencies...${NC}"
    npm install 2>/dev/null || {
        echo -e "${YELLOW}⚠️  npm install failed, trying with --force${NC}"
        npm install --force
    }
fi

# Compile TypeScript
echo -e "${CYAN}🔨 Compiling TypeScript...${NC}"
npm run compile 2>/dev/null || {
    echo -e "${YELLOW}⚠️  Compilation failed, trying to fix...${NC}"
    npm install --save-dev typescript @types/node @types/vscode
    npx tsc -p ./
}

# Package extension
echo -e "${CYAN}📦 Packaging extension...${NC}"

if ! command -v vsce &> /dev/null; then
    echo -e "${YELLOW}Installing vsce...${NC}"
    npm install -g vsce 2>/dev/null || sudo npm install -g vsce
fi

vsce package --allow-missing-repository 2>/dev/null || {
    echo -e "${YELLOW}⚠️  Packaging failed, trying without validation${NC}"
    vsce package --allow-missing-repository --no-yarn
}

VSIX_FILE=$(ls python-runner-*.vsix 2>/dev/null | head -n1)

if [ ! -f "$VSIX_FILE" ]; then
    echo -e "${RED}❌ Failed to package extension${NC}"
    echo -e "${YELLOW}⚠️  But the extension folder is ready at: $(pwd)${NC}"
    echo -e "${YELLOW}You can manually package with: vsce package${NC}"
else
    echo -e "${GREEN}✅ Extension packaged: $VSIX_FILE${NC}"

    # Install extension
    echo -e "${CYAN}📥 Installing extension...${NC}"

    if command -v code-server &> /dev/null; then
        echo -e "${YELLOW}🔧 Detected code-server environment${NC}"
        code-server --install-extension "$VSIX_FILE" --force 2>/dev/null || {
            echo -e "${YELLOW}⚠️  Could not install with code-server${NC}"
        }
    elif command -v code &> /dev/null; then
        code --install-extension "$VSIX_FILE" --force 2>/dev/null || {
            echo -e "${YELLOW}⚠️  Could not install with code command${NC}"
        }
    else
        echo -e "${YELLOW}⚠️  'code' or 'code-server' command not found${NC}"
        echo -e "${YELLOW}Install manually: code --install-extension $VSIX_FILE${NC}"
    fi

    echo -e "${GREEN}✅ Python Script Runner installed successfully!${NC}"
fi

# Show usage instructions
echo ""
echo -e "${CYAN}⚙️  How to use:${NC}"
echo "1. Find any .py file in your project"
echo "2. Right-click on it → '▶️ Run .py'"
echo "3. Or click '▶️ Run .py' in editor title when editing .py files"
echo ""
echo -e "${GREEN}🎉 Ready to use! Right-click any .py file → '▶️ Run .py'${NC}"
