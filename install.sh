#!/bin/bash

# =====================================
# Configuration and Setup
# =====================================

# Get the absolute path of the dotfiles directory
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Define user's config directory
CONFIG_DIR="$HOME/.config"
# Define backup directory with timestamp (will only be created if needed)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="$HOME/.dotfiles_backup_$TIMESTAMP"
# Track if we've created a backup directory
BACKUP_CREATED=false

# =====================================
# Color Definitions for Output
# =====================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =====================================
# Utility Functions
# =====================================

# Print error message and exit
die() {
  echo -e "${RED}Error: $1${NC}" >&2
  exit 1
}

# Print info message
info() {
  echo -e "${BLUE}Info: $1${NC}"
}

# Print success message
success() {
  echo -e "${GREEN}Success: $1${NC}"
}

# Print warning message
warn() {
  echo -e "${YELLOW}Warning: $1${NC}"
}

# =====================================
# Backup Functions
# =====================================

# Create backup of a file or directory if needed
backup_if_needed() {
  local item="$1"

  # Only backup if it's a real directory or file (not a symlink)
  if [ -e "$item" ] && [ ! -L "$item" ]; then
    # Create backup directory if this is our first backup
    if [ "$BACKUP_CREATED" = false ]; then
      mkdir -p "$BACKUP_DIR" || die "Failed to create backup directory"
      BACKUP_CREATED=true
      info "Created backup directory: $BACKUP_DIR"
    fi

    # Create the backup with directory structure
    local backup_path="$BACKUP_DIR${item#$HOME}"
    local parent_dir="$(dirname "$backup_path")"

    mkdir -p "$parent_dir"
    cp -R "$item" "$backup_path"
    success "Backed up: $item -> $backup_path"
    return 0
  fi
  return 1
}

# =====================================
# Installation Functions
# =====================================

# Ensure parent directory exists
ensure_parent_dir() {
  local target_path="$1"
  local parent_dir="$(dirname "$target_path")"
  if [ ! -d "$parent_dir" ]; then
    mkdir -p "$parent_dir" || die "Failed to create directory: $parent_dir"
    success "Created parent directory: $parent_dir"
  fi
}

# Create symlink with safety checks
create_symlink() {
  local source="$1"
  local target="$2"

  # Validate source exists
  if [ ! -e "$source" ]; then
    die "Source does not exist: $source"
  fi

  # Ensure parent directory exists
  ensure_parent_dir "$target"

  # Handle existing target
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ -L "$target" ]; then
      # Remove existing symlink
      rm "$target" || die "Failed to remove existing symlink: $target"
    else
      # Backup real files/directories
      backup_if_needed "$target"
      rm -rf "$target" || die "Failed to remove existing item: $target"
    fi
  fi

  # Create the symlink
  ln -sf "$source" "$target" || die "Failed to create symlink: $target -> $source"
  success "Created symlink: $target -> $source"
}

# Install config directory contents
install_config_dir() {
  info "Setting up .config directory symlinks..."

  # Create .config directory if it doesn't exist
  mkdir -p "$CONFIG_DIR" || die "Failed to create .config directory"

  if [ -d "$DOTFILES_DIR/.config" ]; then
    for item in "$DOTFILES_DIR"/.config/*; do
      if [ -e "$item" ]; then
        base_name=$(basename "$item")
        target="$CONFIG_DIR/$base_name"
        create_symlink "$item" "$target"
      fi
    done
  else
    warn "No .config directory found in dotfiles"
  fi
}

# Install root-level dotfiles
install_root_dotfiles() {
  info "Setting up root-level dotfiles..."

  for item in "$DOTFILES_DIR"/*; do
    base_name=$(basename "$item")

    # Skip special directories and files
    if [[ "$base_name" != ".config" &&
      "$base_name" != "install.sh" &&
      "$base_name" != ".git" &&
      "$base_name" != ".gitignore" &&
      "$base_name" != "." &&
      "$base_name" != ".." ]]; then

      target="$HOME/$base_name"
      create_symlink "$item" "$target"
    fi
  done
}

# =====================================
# Main Installation Process
# =====================================

main() {
  # Print welcome message
  echo "========================================="
  echo "  Dotfiles Installation Script"
  echo "========================================="

  # Check if running from correct directory
  if [ ! -f "$DOTFILES_DIR/install.sh" ]; then
    die "Script must be run from the dotfiles directory"
  fi

  # Install dotfiles
  install_config_dir
  install_root_dotfiles

  # Print completion message
  echo "========================================="
  success "Dotfiles installation completed!"
  if [ "$BACKUP_CREATED" = true ]; then
    echo "Backup location: $BACKUP_DIR"
  fi
  echo "========================================="
}

# =====================================
# Script Execution
# =====================================

# Execute main function with error handling
if ! main "$@"; then
  die "Installation failed!"
fi
