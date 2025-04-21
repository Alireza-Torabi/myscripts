#!/bin/bash

# ========================
# Install Dependencies
# ========================

# Install translate-shell if not available
if ! command -v trans &> /dev/null; then
    echo "Installing translation tool (translate-shell)..."
    sudo apt update
    sudo apt install -y translate-shell
fi

# Install gdown if not available
if ! command -v gdown &> /dev/null; then
    echo "gdown not found. Installing..."
    sudo apt install -y python3-pip
    pip3 install gdown
fi

# ========================
# Language Setup
# ========================

# Function to check if Google Translate is accessible
function can_translate() {
    command -v trans &>/dev/null && ping -c1 -W1 translate.googleapis.com &>/dev/null
}

# Prompt for language
echo "🌐 Enter your language code (e.g., en, fa, fr, de, es, ar):"
read -p "> " lang_code

use_translate=false
if can_translate; then
    use_translate=true
else
    echo "⚠️ Google Translate is not available. Prompts will be in English."
    lang_code="en"
fi

# Translation function with fallback
translate() {
    local text="$1"
    if $use_translate; then
        trans -brief :"$lang_code" "$text"
    else
        echo "$text"
    fi
}

# ========================
# Prompt & Download
# ========================

read -p "$(translate 'Enter Google Drive shared link (e.g., https://drive.google.com/file/d/FILE_ID/view?usp=sharing):') " drive_link
echo "$(translate 'Drive link:') $drive_link"

read -p "$(translate 'Enter the desired file name (with extension, e.g., myfile.zip):') " file_name
if [ -z "$file_name" ]; then
    echo "$(translate 'No file name provided. Exiting.')"
    exit 1
fi

read -p "$(translate 'Enter the download path (press Enter to use current folder):') " download_path
if [ -z "$download_path" ]; then
    read -p "$(translate 'You did not provide a path. Download to current folder? (y/n):') " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "$(translate 'Download canceled.')"
        exit 1
    fi
    download_path="."
fi

mkdir -p "$download_path"
output_file="${download_path}/${file_name}"

echo "$(translate 'Downloading file...')"
gdown --fuzzy "$drive_link" -O "$output_file"

if [ $? -eq 0 ]; then
    echo "$(translate '✅ Download complete:') $output_file"
else
    echo "$(translate '❌ Download failed. Please make sure the file is publicly accessible and the link is correct.')"
fi
