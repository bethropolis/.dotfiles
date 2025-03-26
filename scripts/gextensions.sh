#!/bin/bash

# Script to manage GNOME Shell Extensions
# - Dumps installed extensions to a text file
# - Can install extensions from the dumped file, downloading and cleaning up zip files

EXTENSIONS_FILE="$HOME/lists/gnome_extensions.txt"
CACHE_DIR="/tmp/gnome_extensions_cache"

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Check dependencies
check_dependencies() {
  local missing=0

  # Check for GNOME Shell
  if ! command -v gnome-shell &>/dev/null; then
    echo -e "${RED}✘ Error: GNOME Shell is not installed.${NC}"
    missing=$((missing + 1))
  fi

  # Check for gnome-extensions CLI
  if ! command -v gnome-extensions &>/dev/null; then
    echo -e "${RED}✘ Error: gnome-extensions CLI tool not found.${NC}"
    missing=$((missing + 1))
  fi

  # Check for curl for downloading
  if ! command -v curl &>/dev/null; then
    echo -e "${RED}✘ Error: curl is not installed. Please install curl.${NC}"
    missing=$((missing + 1))
  fi

  # Check for jq for JSON parsing
  if ! command -v jq &>/dev/null; then
    echo -e "${RED}✘ Error: jq is not installed. Please install jq.${NC}"
    missing=$((missing + 1))
  fi

  return $missing
}

# Function to display usage information
show_usage() {
  echo -e "${BOLD}${CYAN}======= GNOME Extensions Manager =======${NC}"
  echo -e "${YELLOW}Usage:${NC} $0 [--install] [--browser-sync]"
  echo -e "  ${GREEN}Without arguments:${NC} Dumps installed GNOME extensions to ${BOLD}$EXTENSIONS_FILE${NC}"
  echo -e "  ${GREEN}--install:${NC} Installs extensions from ${BOLD}$EXTENSIONS_FILE${NC}"
  echo -e "  ${GREEN}--browser-sync:${NC} Sync extensions from browser to GNOME"
  exit 1
}

# Function to show progress
show_progress() {
  local current=$1
  local total=$2
  local percent=$((current * 100 / total))
  local completed=$((percent / 2))
  local remaining=$((50 - completed))

  printf "${BLUE}["
  printf "%${completed}s" | tr ' ' '#'
  printf "%${remaining}s" | tr ' ' ' '
  printf "] ${YELLOW}%3d%%${NC} (%d/%d)\r" $percent $current $total
}

# Dump installed extensions
dump_extensions() {
  echo -e "\n${BOLD}${CYAN}======= Dumping GNOME Extensions =======${NC}\n"

  check_dependencies || exit 1

  echo -e "${YELLOW}⟳ Retrieving installed GNOME extensions...${NC}"

  # Dump extension IDs and names
  gnome-extensions list --enabled | while read -r extension; do
    extension_name=$(gnome-extensions info "$extension" | grep "Name:" | cut -d: -f2 | xargs)
    echo "$extension:$extension_name"
  done >"$EXTENSIONS_FILE"

  if [ $? -eq 0 ]; then
    ext_count=$(wc -l <"$EXTENSIONS_FILE")
    echo -e "${GREEN}✓ Successfully dumped ${BOLD}$ext_count${NC}${GREEN} GNOME extensions to ${BOLD}$EXTENSIONS_FILE${NC}"

    # Show sample extensions
    echo -e "\n${PURPLE}First few extensions:${NC}"
    head -n 5 "$EXTENSIONS_FILE" | while read -r ext; do
      echo -e "  ${CYAN}•${NC} $ext"
    done

    # If more than 5 extensions
    if [ $ext_count -gt 5 ]; then
      echo -e "${YELLOW}  ... and $(($ext_count - 5)) more${NC}"
    fi

    echo -e "\n${GREEN}✓ Extension dump completed successfully!${NC}"
  else
    echo -e "${RED}✘ Error: Failed to dump GNOME extensions.${NC}"
    exit 1
  fi
}

# Function to get GNOME Shell version
get_shell_version() {
  gnome-shell --version | cut -d' ' -f3
}

# Function to fetch download URL for an extension
fetch_download_url() {
  local uuid=$1
  local shell_version=$(get_shell_version)

  echo -e "${YELLOW}⟳ Fetching extension info for ${BOLD}$uuid${NC}...${NC}"

  local info_json=$(curl -sS "https://extensions.gnome.org/extension-info/?uuid=$uuid&shell_version=$shell_version")
  if [ -z "$info_json" ]; then
    echo -e "${RED}✘ Error: Failed to fetch extension info for ${BOLD}$uuid${NC}"
    return 1
  fi

  local download_url=$(echo "$info_json" | jq -r ".download_url")
  if [ "$download_url" == "null" ] || [ -z "$download_url" ]; then
    echo -e "${RED}✘ Error: No download URL found for ${BOLD}$uuid${NC} (possibly incompatible version)"
    return 1
  fi

  echo "https://extensions.gnome.org$download_url"
}

# Function to download extension zip file
download_extension() {
  local uuid=$1
  local download_url=$2
  local zip_file="$CACHE_DIR/$uuid.zip"

  echo -e "${YELLOW}⟳ Downloading ${BOLD}$uuid${NC}...${NC}"

  curl -L "$download_url" --progress-bar -o "$zip_file"

  if [ -f "$zip_file" ] && [ -s "$zip_file" ]; then
    echo -e "${GREEN}✓ Downloaded ${BOLD}$uuid${NC} to ${BOLD}$zip_file${NC}"
    return 0
  else
    echo -e "${RED}✘ Failed to download ${BOLD}$uuid${NC}"
    [ -f "$zip_file" ] && rm "$zip_file"
    return 1
  fi
}

# Install extensions from file
install_extensions() {
  echo -e "\n${BOLD}${CYAN}======= Installing GNOME Extensions =======${NC}\n"

  check_dependencies || exit 1

  # Check if file exists
  if [ ! -f "$EXTENSIONS_FILE" ]; then
    echo -e "${RED}✘ Error: ${BOLD}$EXTENSIONS_FILE${NC}${RED} not found. Run script without arguments first.${NC}"
    exit 1
  fi

  # Create cache directory
  mkdir -p "$CACHE_DIR" || {
    echo -e "${RED}✘ Error: Failed to create cache directory ${BOLD}$CACHE_DIR${NC}"
    exit 1
  }

  # Count total extensions
  total=$(grep -v "^$" "$EXTENSIONS_FILE" | wc -l)
  current=0
  success=0
  failed=0

  echo -e "${YELLOW}⟳ Found ${BOLD}$total${NC}${YELLOW} extensions to install${NC}\n"

  # Read file line by line
  while IFS=: read -r uuid extension_name; do
    # Skip empty lines
    if [ -z "$uuid" ]; then
      continue
    fi

    current=$((current + 1))
    echo -e "${BLUE}[$current/$total]${NC} Processing ${BOLD}$extension_name${NC} (${uuid})..."
    show_progress $current $total

    # Fetch download URL
    download_url=$(fetch_download_url "$uuid")
    if [ $? -ne 0 ]; then
      failed=$((failed + 1))
      echo -e "${RED}✘ Skipping installation due to failure in fetching download URL.${NC}"
      echo -e "${PURPLE}------------------------------------------------${NC}"
      continue
    fi

    # Download the extension zip file
    if download_extension "$uuid" "$download_url"; then
      zip_file="$CACHE_DIR/$uuid.zip"

      # Install the extension
      if gnome-extensions install "$zip_file" &>/tmp/gnome_ext_install; then
        success=$((success + 1))
        echo -e "${GREEN}✓ Successfully installed ${BOLD}$extension_name${NC}"

        # Enable extension
        gnome-extensions enable "$uuid"

        # Clean up the zip file
        rm "$zip_file" && echo -e "${GREEN}✓ Cleaned up ${BOLD}$zip_file${NC}"
      else
        failed=$((failed + 1))
        echo -e "${RED}✘ Failed to install ${BOLD}$extension_name${NC}"
        echo -e "${YELLOW}  Error details:${NC}"
        cat /tmp/gnome_ext_install | grep -i error | head -n 2 | sed 's/^/    /'
      fi
    else
      failed=$((failed + 1))
      echo -e "${RED}✘ Skipping installation due to download failure.${NC}"
    fi

    echo -e "${PURPLE}------------------------------------------------${NC}"
  done <"$EXTENSIONS_FILE"

  # Final summary
  echo -e "\n${BOLD}${CYAN}======= Installation Summary =======${NC}"
  echo -e "${GREEN}✓ Successfully installed: ${BOLD}$success${NC}${GREEN} extensions${NC}"
  if [ $failed -gt 0 ]; then
    echo -e "${RED}✘ Failed to install: ${BOLD}$failed${NC}${RED} extensions${NC}"
  fi
  echo -e "${BLUE}Total processed: ${BOLD}$total${NC}${BLUE} extensions${NC}"
  echo -e "\n${GREEN}✓ GNOME Extension installation completed!${NC}"
}

# Browser sync function (placeholder for extension synchronization)
browser_sync() {
  echo -e "\n${BOLD}${CYAN}======= GNOME Extension Browser Sync =======${NC}\n"

  echo -e "${YELLOW}⚠ Note: Browser sync requires manual browser configuration.${NC}"
  echo -e "Steps:"
  echo -e "1. Ensure GNOME Browser Integration is installed"
  echo -e "2. Configure your browser's GNOME extension synchronization"
  echo -e "3. Manually sync extensions from browser to GNOME Shell"

  echo -e "\n${RED}✘ Full browser sync not implemented in this version.${NC}"
}

# Terminal color compatibility check
if ! [ -t 1 ]; then
  # Disable colors if not in terminal
  RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN='' BOLD='' NC=''
fi

# Main script logic
case "$1" in
--install)
  install_extensions
  ;;
--browser-sync)
  browser_sync
  ;;
'')
  dump_extensions
  ;;
*)
  show_usage
  ;;
esac
