#!/bin/bash

# Script to manage Flatpak applications with colorful output
# - Dumps installed Flatpaks to a text file
# - Can install Flatpaks from the dumped file

FLATPAK_FILE="$HOME/lists/flatpaks.txt"

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to display usage information
show_usage() {
  echo -e "${BOLD}${CYAN}======= Flatpak Manager =======${NC}"
  echo -e "${YELLOW}Usage:${NC} $0 [--install]"
  echo -e "  ${GREEN}Without arguments:${NC} Dumps installed Flatpak applications to ${BOLD}$FLATPAK_FILE${NC}"
  echo -e "  ${GREEN}--install:${NC} Installs Flatpak applications from ${BOLD}$FLATPAK_FILE${NC}"
  exit 1
}

# Function for showing progress
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

# Function to dump installed Flatpak applications
dump_flatpaks() {
  echo -e "\n${BOLD}${CYAN}======= Dumping Flatpak Applications =======${NC}\n"

  # Check if flatpak is installed
  if ! command -v flatpak &>/dev/null; then
    echo -e "${RED}✘ Error: Flatpak is not installed. Please install Flatpak first.${NC}"
    exit 1
  fi

  echo -e "${YELLOW}⟳ Retrieving installed Flatpak applications...${NC}"

  # Get list of installed applications and save to file
  flatpak list --app --columns=application >"$FLATPAK_FILE"

  if [ $? -eq 0 ]; then
    app_count=$(wc -l <"$FLATPAK_FILE")
    echo -e "${GREEN}✓ Successfully dumped ${BOLD}$app_count${NC}${GREEN} Flatpak applications to ${BOLD}$FLATPAK_FILE${NC}"

    # Show sample of applications
    echo -e "\n${PURPLE}First few applications:${NC}"
    head -n 5 "$FLATPAK_FILE" | while read -r app; do
      echo -e "  ${CYAN}•${NC} $app"
    done

    # If there are more than 5 apps
    if [ $app_count -gt 5 ]; then
      echo -e "${YELLOW}  ... and $(($app_count - 5)) more${NC}"
    fi

    echo -e "\n${GREEN}✓ Dump completed successfully!${NC}"
  else
    echo -e "${RED}✘ Error: Failed to dump Flatpak applications.${NC}"
    exit 1
  fi
}

# Function to install Flatpak applications from file
install_flatpaks() {
  echo -e "\n${BOLD}${CYAN}======= Installing Flatpak Applications =======${NC}\n"

  # Check if flatpak is installed
  if ! command -v flatpak &>/dev/null; then
    echo -e "${RED}✘ Error: Flatpak is not installed. Please install Flatpak first.${NC}"
    exit 1
  fi

  # Check if file exists
  if [ ! -f "$FLATPAK_FILE" ]; then
    echo -e "${RED}✘ Error: ${BOLD}$FLATPAK_FILE${NC}${RED} not found. Please run the script without arguments first to create it.${NC}"
    exit 1
  fi

  # Count total applications to install
  total=$(grep -v "^$" "$FLATPAK_FILE" | wc -l)
  current=0
  success=0
  failed=0

  echo -e "${YELLOW}⟳ Found ${BOLD}$total${NC}${YELLOW} applications to install${NC}\n"

  # Read file line by line and install each application
  while IFS= read -r app_id; do
    # Skip empty lines
    if [ -z "$app_id" ]; then
      continue
    fi

    current=$((current + 1))
    echo -e "${BLUE}[$current/$total]${NC} Installing ${BOLD}$app_id${NC}..."
    show_progress $current $total

    # Install the application
    if flatpak install --assumeyes flathub "$app_id" &>/tmp/flatpak_install_output; then
      success=$((success + 1))
      echo -e "${GREEN}✓ Successfully installed ${BOLD}$app_id${NC}"
    else
      failed=$((failed + 1))
      echo -e "${RED}✘ Failed to install ${BOLD}$app_id${NC}"
      echo -e "${YELLOW}  Error details:${NC}"
      cat /tmp/flatpak_install_output | grep -i error | head -n 2 | sed 's/^/    /'
    fi

    # Display a separator between installations
    echo -e "${PURPLE}------------------------------------------------${NC}"
  done <"$FLATPAK_FILE"

  # Final summary
  echo -e "\n${BOLD}${CYAN}======= Installation Summary =======${NC}"
  echo -e "${GREEN}✓ Successfully installed: ${BOLD}$success${NC}${GREEN} applications${NC}"
  if [ $failed -gt 0 ]; then
    echo -e "${RED}✘ Failed to install: ${BOLD}$failed${NC}${RED} applications${NC}"
  fi
  echo -e "${BLUE}Total processed: ${BOLD}$total${NC}${BLUE} applications${NC}"
  echo -e "\n${GREEN}✓ Flatpak installation completed!${NC}"
}

# Check for terminal compatibility with colors
if ! [ -t 1 ]; then
  # If not running in a terminal, disable colors
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  PURPLE=''
  CYAN=''
  BOLD=''
  NC=''
fi

# Main script logic
if [ "$1" = "--install" ]; then
  install_flatpaks
elif [ "$#" -eq 0 ]; then
  dump_flatpaks
else
  show_usage
fi
