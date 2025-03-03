#!/bin/bash

# =====================================
# Configuration and Setup
# =====================================

# Get the absolute path of the dotfiles directory
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Define user's home directory for clarity
HOME_DIR="$HOME"
# Define backup directory with timestamp (will only be created if needed)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="$HOME/.dotfiles_backup_$TIMESTAMP"
# Track if we've created a backup directory
BACKUP_CREATED=false

# List of directories to handle specially
# These directories won't be replaced, instead their contents will be symlinked
SPECIAL_DIRS=(
    ".config"
    ".local/share"
    ".local/bin"
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
        if [ "$relative_path" = "$dir" ]; then
            return 0
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

# Install contents of a special directory
install_special_dir() {
    local source_dir="$1"
    local base_dir="$2"
    
    info "Setting up symlinks for special directory: $source_dir"
    
    # Create base directory if it doesn't exist
    mkdir -p "$base_dir" || die "Failed to create directory: $base_dir"
    
    # Process all items in the source directory
    if [ -d "$source_dir" ]; then
        for item in "$source_dir"/*; do
            if [ -e "$item" ]; then
                local base_name=$(basename "$item")
                local target="$base_dir/$base_name"
                create_symlink "$item" "$target"
            fi
        done
    else
        warn "Directory not found in dotfiles: $source_dir"
    fi
}

# Install all dotfiles
install_dotfiles() {
    info "Installing dotfiles..."
    
    # First, handle special directories
    for special_dir in "${SPECIAL_DIRS[@]}"; do
        local source_dir="$DOTFILES_DIR/$special_dir"
        local target_dir="$HOME_DIR/$special_dir"
        if [ -d "$source_dir" ]; then
            install_special_dir "$source_dir" "$target_dir"
        fi
    done
    
    # Then handle all other files and directories in the root
    for item in "$DOTFILES_DIR"/*; do
        if [ -e "$item" ]; then
            local base_name=$(basename "$item")
            local target="$HOME_DIR/$base_name"
            
            # Check if this is a special directory
            if is_special_dir "$item"; then
                continue  # Skip special directories as they're already handled
            fi
            
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
    install_dotfiles
    
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