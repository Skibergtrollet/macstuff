#!/bin/bash

set -e

echo "======================================"
echo " Installing developer tools for macOS"
echo "======================================"

# --------------------------------------------------
# 1. Install Homebrew
# --------------------------------------------------

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew not found. Installing Homebrew..."

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Apple Silicon
    if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
else
    echo "Homebrew already installed."
fi


# --------------------------------------------------
# 2. Ensure Homebrew is available in this shell
# --------------------------------------------------

if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -f /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi


# --------------------------------------------------
# 3. Update Homebrew
# --------------------------------------------------

echo ""
echo "Updating Homebrew..."
brew update


# --------------------------------------------------
# 4. Install Git
# --------------------------------------------------

echo ""
if command -v git >/dev/null 2>&1; then
    echo "Git already installed:"
    git --version
else
    echo "Installing Git..."
    brew install git
fi


# --------------------------------------------------
# 5. Install GitHub CLI
# --------------------------------------------------

echo ""
if command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI already installed:"
    gh --version | head -1
else
    echo "Installing GitHub CLI..."
    brew install gh
fi


# --------------------------------------------------
# 6. Install Azure CLI
# --------------------------------------------------

echo ""
if command -v az >/dev/null 2>&1; then
    echo "Azure CLI already installed:"
    az version --output table
else
    echo "Installing Azure CLI..."
    brew update
    brew install azure-cli
fi


# --------------------------------------------------
# 7. Validation
# --------------------------------------------------

echo ""
echo "======================================"
echo " Installation complete"
echo "======================================"

echo ""
echo "Git:"
git --version

echo ""
echo "GitHub CLI:"
gh --version | head -1

echo ""
echo "Azure CLI:"
az version --output table

echo ""
echo "======================================"
echo " Next steps"
echo "======================================"
echo ""
echo "GitHub login:"
echo "  gh auth login"
echo ""
echo "Azure login:"
echo "  az login"
echo ""