#!/bin/bash

# =====================================
# Configuration and Setup
# =====================================

# Get the absolute path of the dotfiles directory
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Define user's home directory for clarity
HOME_DIR="$HOME"
# Define backup directory with timestamp (will only be created if needed)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="$HOME/.dotfiles_backup_$TIMESTAMP"
# Track if we've created a backup directory
BACKUP_CREATED=false

# apps, packages, extensions
FLATPAKS_SCRIPT="$HOME/scripts/flatpaks.sh"
GNOME_EXTENSION_SCRIPT="$HOME/scripts/gextensions.sh"
INSTALL_FLATPAKS=false
INSTALL_EXTENSIONS=false
BROWSER_SYNC=false

# List of directories to handle specially
# These directories won't be replaced, instead their contents will be symlinked
SPECIAL_DIRS=(
  ".config"
  ".local/share"
  ".local/bin"
  ".config/nvim"  # Nvim lua directory for plugins
  # Add more directories here as needed
)

# Default files to always ignore
DEFAULT_IGNORES=(
  "install.sh"
  ".git"
  ".gitignore"
  "README.md"
  "LICENSE"
)

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

show_usage() {
  echo -e "${BOLD}${CYAN}======= Dotfiles Installation Manager =======${NC}"
  echo -e "${YELLOW}Usage:${NC} $0 [options]"
  echo -e "Options:"
  echo -e "  ${GREEN}--install-flatpaks${NC}    Install Flatpak applications"
  echo -e "  ${GREEN}--install-extensions${NC}  Install GNOME extensions"
  echo -e "  ${GREEN}--browser-sync${NC}        Sync extensions from browser"
  echo -e "\nNormal operation installs dotfiles only"
  exit 1
}

# Check if git is available
check_git() {
  if ! command -v git >/dev/null 2>&1; then
    warn "Git is not installed. Will use basic ignore rules only."
    return 1
  fi
  return 0
}

# Check if a path is in special directories list
is_special_dir() {
  local check_path="$1"
  local relative_path="${check_path#$DOTFILES_DIR/}"

  for dir in "${SPECIAL_DIRS[@]}"; do
    # Exact match
    if [ "$relative_path" = "$dir" ]; then
      return 0
    fi
    
    # Check if this is a parent of a nested special directory
    # For example, .config is a parent of .config/nvim/lua
    if [[ "$dir" == "$relative_path/"* ]]; then
      return 0
    fi
    
    # Check if this is a nested special directory itself
    if [[ "$relative_path" == "$dir"/* ]]; then
      return 0
    fi
  done
  return 1
}

# Check if a path is an exact match in SPECIAL_DIRS list
is_exactly_special_dir() {
  local path_to_check="$1"
  for sd in "${SPECIAL_DIRS[@]}"; do
    if [ "$path_to_check" = "$sd" ]; then
      return 0 # It is an exact match
    fi
  done
  return 1
}

# =====================================
# GitIgnore Functions
# =====================================

# Check if a file should be ignored based on .gitignore and default rules
should_ignore() {
  local file="$1"
  local relative_path="${file#$DOTFILES_DIR/}"

  # Check default ignores
  for ignore in "${DEFAULT_IGNORES[@]}"; do
    if [[ "$relative_path" == "$ignore" ]]; then
      return 0
    fi
  done

  # If git is available and we're in a git repo, use git check-ignore
  if check_git && [ -d "$DOTFILES_DIR/.git" ]; then
    if git -C "$DOTFILES_DIR" check-ignore -q "$relative_path" 2>/dev/null; then
      return 0
    fi
  fi

  return 1
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
    local backup_path="$BACKUP_DIR${item#$HOME_DIR}"
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

  # Check if file should be ignored
  if should_ignore "$source"; then
    info "Skipping ignored file: $source"
    return 0
  fi

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

# Install all dotfiles
install_dotfiles() {
  info "Installing dotfiles..."

  # First, ensure all directories listed in SPECIAL_DIRS exist in $HOME
  # This creates the target special directories like $HOME/.config and $HOME/.config/nvim
  for sd_rel_path in "${SPECIAL_DIRS[@]}"; do
    local dst_sd_path="$HOME_DIR/$sd_rel_path"
    # mkdir -p will create parent directories as needed and won't error if they exist
    mkdir -p "$dst_sd_path" || die "Failed to create special directory structure: $dst_sd_path"
    # You could add an info message here if desired, e.g.:
    # info "Ensured special directory structure exists: $dst_sd_path"
  done

  # Pass 1: Handle contents of special directories
  # For each directory listed in SPECIAL_DIRS, symlink its children.
  # If a child is itself a special directory, skip it (it will be processed by this same loop).
  for sd_rel_path in "${SPECIAL_DIRS[@]}"; do
    local src_special_dir="$DOTFILES_DIR/$sd_rel_path"
    local dst_special_dir="$HOME_DIR/$sd_rel_path"

    # Source special directory must exist in dotfiles
    [ -d "$src_special_dir" ] || continue

    info "Processing contents of special directory: $sd_rel_path"
    for src_child_item in "$src_special_dir"/*; do
      [ -e "$src_child_item" ] || continue # Skip if no items or item is a broken symlink

      local child_basename=$(basename "$src_child_item")
      # Construct relative path of the child from DOTFILES_DIR root, e.g., ".config/nvim" or ".config/nvim/lua"
      local child_rel_path_from_dotfiles="$sd_rel_path/$child_basename"

      # If this child item itself is listed as a SPECIAL_DIR, skip symlinking it directly.
      # Its own entry in the SPECIAL_DIRS loop will handle its contents.
      if is_exactly_special_dir "$child_rel_path_from_dotfiles"; then
        info "Skipping symlink for $child_basename within $sd_rel_path; it's a special directory itself and its contents will be handled."
        continue
      fi

      # Otherwise, symlink this child into the destination special directory
      create_symlink "$src_child_item" "$dst_special_dir/$child_basename"
    done
  done

  # Pass 2: Handle top-level items from DOTFILES_DIR
  # These are items directly under DOTFILES_DIR (e.g., .bashrc, .gitconfig, or non-special dirs).
  info "Processing top-level items..."
  for src_top_item in "$DOTFILES_DIR"/*; do
    [ -e "$src_top_item" ] || continue # Skip if no items or item is a broken symlink

    local top_item_basename=$(basename "$src_top_item")
    # If this top-level item is itself a special directory, its contents were handled by Pass 1. So, skip.
    is_exactly_special_dir "$top_item_basename" && continue

    create_symlink "$src_top_item" "$HOME_DIR/$top_item_basename"
  done
}

run_flatpaks_install() {
  if [ -x "$FLATPAKS_SCRIPT" ]; then
    info "Starting Flatpak installation..."
    "$FLATPAKS_SCRIPT" --install
    success "Flatpak installation completed"
  else
    warn "Flatpak script not found at $FLATPAKS_SCRIPT"
  fi
}

run_gextensions_install() {
  if [ -x "$GNOME_EXTENSION_SCRIPT" ]; then
    local args="--install"
    [ "$BROWSER_SYNC" = true ] && args+=" --browser-sync"

    "$GNOME_EXTENSION_SCRIPT" $args
  else
    warn "GNOME extension script not found at $GNOME_EXTENSION_SCRIPT"
  fi
}

# =====================================
# Main Installation Process
# =====================================

main() {
  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --install-flatpaks)
      INSTALL_FLATPAKS=true
      shift
      ;;
    --install-extensions)
      INSTALL_EXTENSIONS=true
      shift
      ;;
    --browser-sync)
      BROWSER_SYNC=true
      shift
      ;;
    *)
      show_usage

      die "Unknown option: $1"
      ;;
    esac
  done

  # Existing installation checks
  echo "========================================="
  echo "  Dotfiles Installation Script"
  echo "========================================="

  if [ ! -f "$DOTFILES_DIR/install.sh" ]; then
    die "Script must be run from the dotfiles directory"
  fi

  # Install dotfiles
  install_dotfiles

  # Run additional installations based on flags
  if [ "$INSTALL_FLATPAKS" = true ]; then
    run_flatpaks_install
  fi

  if [ "$INSTALL_EXTENSIONS" = true ]; then
    run_gextensions_install
  fi

  # Print completion message
  echo "========================================="
  success "Installation process completed!"
  [ "$BACKUP_CREATED" = true ] && echo "Backup location: $BACKUP_DIR"
  [ "$INSTALL_FLATPAKS" = true ] && echo "Flatpaks installed from: $FLATPAK_LIST"
  [ "$INSTALL_EXTENSIONS" = true ] && echo "Extensions installed from: $GNOME_EXTENSION_LIST"
  echo "========================================="
}
# =====================================
# Script Execution
# =====================================

# Execute main function with error handling
if ! main "$@"; then
  die "Installation failed!"
fi
