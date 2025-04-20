#!/usr/bin/env bash

# Script to manage GNOME Shell Extensions
# - Dumps installed extensions to a text file
# - Installs extensions from the dumped file using gnome-extensions-cli (gext)

EXTENSIONS_FILE="$HOME/lists/gnome_extensions.txt"

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

  # Check for gnome-extensions CLI (used for dumping)
  if ! command -v gnome-extensions &>/dev/null; then
    echo -e "${RED}✘ Error: gnome-extensions CLI tool not found.${NC}"
    missing=$((missing + 1))
  fi

  # Check for gext (gnome-extensions-cli)
  if ! command -v gext &>/dev/null; then
    echo -e "${RED}✘ Error: gext (gnome-extensions-cli) not found.${NC}"
    echo -e "${YELLOW}    Install it from https://github.com/essembeh/gnome-extensions-cli${NC}"
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

# Function to show progress bar
show_progress() {
  local current=$1 total=$2
  local percent=$((current * 100 / total))
  local completed=$((percent / 2))
  local remaining=$((50 - completed))

  printf "${BLUE}["
  printf "%${completed}s" | tr ' ' '#'
  printf "%${remaining}s" | tr ' ' ' '
  printf "] ${YELLOW}%3d%%${NC} (${current}/${total})\r" "$percent" "$current" "$total"
}

# Dump installed extensions (unchanged)
dump_extensions() {
  echo -e "\n${BOLD}${CYAN}======= Dumping GNOME Extensions =======${NC}\n"

  check_dependencies || exit 1

  echo -e "${YELLOW}⟳ Retrieving installed GNOME extensions...${NC}"

  # Dump extension IDs and names
  gnome-extensions list --enabled | while read -r extension; do
    extension_name=$(gnome-extensions info "$extension" \
      | grep "^Name:" \
      | cut -d: -f2 \
      | xargs)
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

    [ "$ext_count" -gt 5 ] && echo -e "${YELLOW}  ... and $((ext_count - 5)) more${NC}"

    echo -e "\n${GREEN}✓ Extension dump completed successfully!${NC}"
  else
    echo -e "${RED}✘ Error: Failed to dump GNOME extensions.${NC}"
    exit 1
  fi
}

# Install extensions using gext
install_extensions() {
  echo -e "\n${BOLD}${CYAN}======= Installing GNOME Extensions =======${NC}\n"

  check_dependencies || exit 1

  # Ensure the list exists
  if [ ! -f "$EXTENSIONS_FILE" ]; then
    echo -e "${RED}✘ Error: ${BOLD}$EXTENSIONS_FILE${NC}${RED} not found. Run script without arguments first.${NC}"
    exit 1
  fi

  total=$(grep -cve '^\s*$' "$EXTENSIONS_FILE")
  current=0
  success=0
  failed=0

  echo -e "${YELLOW}⟳ Found ${BOLD}$total${NC}${YELLOW} extensions to install${NC}\n"

  while IFS=: read -r uuid extension_name; do
    [ -z "$uuid" ] && continue
    current=$((current + 1))
    echo -e "${BLUE}[$current/$total]${NC} Processing ${BOLD}$extension_name${NC} (${uuid})..."
    show_progress "$current" "$total"

    # Install via gext
    if gext install "$uuid" &>/dev/null; then
      success=$((success + 1))
      echo -e "\n${GREEN}✓ Installed ${BOLD}$extension_name${NC}"

      # Enable it
      if gext enable "$uuid" &>/dev/null; then
        echo -e "${GREEN}✓ Enabled ${BOLD}$uuid${NC}"
      else
        echo -e "${YELLOW}⚠ Could not auto‑enable ${BOLD}$uuid${NC}"
      fi
    else
      failed=$((failed + 1))
      echo -e "\n${RED}✘ Failed to install ${BOLD}$extension_name${NC}"
    fi

    echo -e "${PURPLE}------------------------------------------------${NC}"
  done <"$EXTENSIONS_FILE"

  # Summary
  echo -e "\n${BOLD}${CYAN}======= Installation Summary =======${NC}"
  echo -e "${GREEN}✓ Successfully installed: ${BOLD}$success${NC}${GREEN} extensions${NC}"
  [ "$failed" -gt 0 ] && echo -e "${RED}✘ Failed to install: ${BOLD}$failed${NC}${RED} extensions${NC}"
  echo -e "${BLUE}Total processed: ${BOLD}$total${NC}${BLUE} extensions${NC}"
  echo -e "\n${GREEN}✓ GNOME Extension installation completed!${NC}"
}

# Browser sync function (placeholder)
browser_sync() {
  echo -e "\n${BOLD}${CYAN}======= GNOME Extension Browser Sync =======${NC}\n"
  echo -e "${YELLOW}⚠ Note: Browser sync requires manual browser configuration.${NC}"
  echo -e "Steps:"
  echo -e "  1. Ensure GNOME Browser Integration is installed"
  echo -e "  2. Configure your browser's GNOME extension synchronization"
  echo -e "  3. Manually sync extensions from browser to GNOME Shell"
  echo -e "\n${RED}✘ Full browser sync not implemented in this version.${NC}"
}

# Disable colors if stdout is not a TTY
if ! [ -t 1 ]; then
  RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN='' BOLD='' NC=''
fi

# Main logic
case "$1" in
  --install)      install_extensions ;;
  --browser-sync) browser_sync     ;;
  '')             dump_extensions  ;;
  *)              show_usage       ;;
esac

