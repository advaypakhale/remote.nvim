#!/bin/bash

# remote-nvim.sh - Set up isolated Neovim on remote machines via SSH

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# Constants
# ============================================================================

REMOTE_DIR="~/.remote-nvim"
CACHE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/remote.nvim/cache"

# Binary URLs
NVIM_APPIMAGE_URL="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage"
RIPGREP_URL="https://github.com/BurntSushi/ripgrep/releases/download/14.1.0/ripgrep-14.1.0-x86_64-unknown-linux-musl.tar.gz"
FD_URL="https://github.com/sharkdp/fd/releases/download/v10.3.0/fd-v10.3.0-x86_64-unknown-linux-musl.tar.gz"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Default Options
# ============================================================================

CONFIG_DIR=""
VERBOSE=false
SKIP_CONFIRM=false
SSH_OPTS=""

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

show_help() {
    cat <<EOF
remote-nvim.sh - Set up isolated Neovim on remote machines via SSH

Usage:
    ./remote-nvim.sh setup [user@]host [OPTIONS]
    ./remote-nvim.sh sync [user@]host [OPTIONS]
    ./remote-nvim.sh cleanup [user@]host [OPTIONS]
    ./remote-nvim.sh --help

Commands:
    setup       Initial setup of Neovim on remote host
    sync        Sync config files to remote host
    cleanup     Remove Neovim installation from remote host

Options:
    --config-dir PATH       Path to local nvim config (default: ~/.config/nvim)
    --ssh-opts "OPTIONS"    SSH options to use (e.g., "-i key.pem -p 2222")
    --yes                   Skip confirmation prompts
    -v, --verbose           Verbose output
    -h, --help              Show this help message

Examples:
    # Setup with default config location
    ./remote-nvim.sh setup user@remote-host

    # Setup with SSH config alias
    ./remote-nvim.sh setup myserver

    # Setup with custom SSH options (PEM file, custom port)
    ./remote-nvim.sh setup user@host --ssh-opts "-i ~/.ssh/mykey.pem -p 2222"

    # Setup with custom config
    ./remote-nvim.sh setup myserver --config-dir ~/my-nvim-config

    # Sync config changes
    ./remote-nvim.sh sync myserver

    # Cleanup
    ./remote-nvim.sh cleanup myserver

SSH Configuration:
    For complex setups (PEM files, custom ports, jump hosts), you can:
    
    1. Use --ssh-opts flag (shown above), or
    2. Add to ~/.ssh/config (recommended for reuse):
    
       Host myserver
           HostName 192.168.1.100
           User ubuntu
           IdentityFile ~/.ssh/mykey.pem
           Port 2222
       
       Then simply use: ./remote-nvim.sh setup myserver

After setup, SSH into your remote host and run:
    ~/.remote-nvim/rnvim <file>

Or add to PATH for convenience.

Note: Binaries are cached in $CACHE_DIR
      Delete this directory to force re-download on next setup.

EOF
}

check_dependencies() {
    log_verbose "Checking local dependencies..."

    local missing_deps=()

    if ! command -v ssh &>/dev/null; then
        missing_deps+=("ssh")
    fi

    if ! command -v curl &>/dev/null; then
        missing_deps+=("curl")
    fi

    if ! command -v tar &>/dev/null; then
        missing_deps+=("tar")
    fi

    if ! command -v rsync &>/dev/null; then
        log_warning "rsync not found, will use scp as fallback"
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi

    log_verbose "All dependencies satisfied"
}

test_ssh_connection() {
    local host="$1"
    log_verbose "Testing SSH connection to $host..."

    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 $SSH_OPTS "$host" "echo 'Connection test successful'" &>/dev/null; then
        log_error "Cannot connect to $host via SSH"
        exit 1
    fi

    log_verbose "SSH connection successful"
}

validate_config_dir() {
    if [ -z "$CONFIG_DIR" ]; then
        CONFIG_DIR="$HOME/.config/nvim"
    fi

    if [ ! -d "$CONFIG_DIR" ]; then
        log_error "Config directory does not exist: $CONFIG_DIR"
        log_error "Specify with --config-dir or ensure ~/.config/nvim exists"
        exit 1
    fi

    # Check for init.lua or init.vim
    if [ ! -f "$CONFIG_DIR/init.lua" ] && [ ! -f "$CONFIG_DIR/init.vim" ]; then
        log_error "No init.lua or init.vim found in $CONFIG_DIR"
        exit 1
    fi

    log_verbose "Using config directory: $CONFIG_DIR"
}

ensure_cache_dir() {
    if [ ! -d "$CACHE_DIR" ]; then
        log_verbose "Creating cache directory: $CACHE_DIR"
        mkdir -p "$CACHE_DIR" || {
            log_error "Failed to create cache directory"
            exit 1
        }
    fi
}

ensure_nvim_cached() {
    local cached_binary="$CACHE_DIR/nvim"

    if [ -f "$cached_binary" ]; then
        log_info "Using cached Neovim AppImage"
        log_verbose "Cached at: $cached_binary"
    else
        log_info "Downloading Neovim AppImage..."
        if ! curl -fsSL -o "$cached_binary" "$NVIM_APPIMAGE_URL"; then
            log_error "Failed to download Neovim AppImage"
            rm -f "$cached_binary"
            exit 1
        fi
        chmod u+x "$cached_binary"
        log_success "Neovim AppImage downloaded and cached"
    fi
}

ensure_ripgrep_cached() {
    local cached_binary="$CACHE_DIR/rg"

    if [ -f "$cached_binary" ]; then
        log_info "Using cached ripgrep binary"
        log_verbose "Cached at: $cached_binary"
    else
        log_info "Downloading ripgrep..."

        local temp_dir=$(mktemp -d)
        local tar_file="$temp_dir/ripgrep.tar.gz"

        if ! curl -fsSL -o "$tar_file" "$RIPGREP_URL"; then
            log_error "Failed to download ripgrep"
            rm -rf "$temp_dir"
            exit 1
        fi

        log_verbose "Extracting ripgrep..."
        tar -xf "$tar_file" -C "$temp_dir" || {
            log_error "Failed to extract ripgrep archive"
            rm -rf "$temp_dir"
            exit 1
        }

        # Find the rg binary in the extracted archive
        local rg_binary=$(find "$temp_dir" -name "rg" -type f | head -n 1)

        if [ -z "$rg_binary" ]; then
            log_error "Could not find rg binary in archive"
            rm -rf "$temp_dir"
            exit 1
        fi

        cp "$rg_binary" "$cached_binary"
        chmod u+x "$cached_binary"
        rm -rf "$temp_dir"

        log_success "ripgrep downloaded and cached"
    fi
}

ensure_fd_cached() {
    local cached_binary="$CACHE_DIR/fd"

    if [ -f "$cached_binary" ]; then
        log_info "Using cached fd binary"
        log_verbose "Cached at: $cached_binary"
    else
        log_info "Downloading fd..."

        local temp_dir=$(mktemp -d)
        local tar_file="$temp_dir/fd.tar.gz"

        if ! curl -fsSL -o "$tar_file" "$FD_URL"; then
            log_error "Failed to download fd"
            rm -rf "$temp_dir"
            exit 1
        fi

        log_verbose "Extracting fd..."
        tar -xf "$tar_file" -C "$temp_dir" || {
            log_error "Failed to extract fd archive"
            rm -rf "$temp_dir"
            exit 1
        }

        # Find the fd binary in the extracted archive
        local fd_binary=$(find "$temp_dir" -name "fd" -type f | head -n 1)

        if [ -z "$fd_binary" ]; then
            log_error "Could not find fd binary in archive"
            rm -rf "$temp_dir"
            exit 1
        fi

        cp "$fd_binary" "$cached_binary"
        chmod u+x "$cached_binary"
        rm -rf "$temp_dir"

        log_success "fd downloaded and cached"
    fi
}

ensure_binaries_cached() {
    ensure_cache_dir
    ensure_nvim_cached
    ensure_ripgrep_cached
    ensure_fd_cached
}

# ============================================================================
# Core Functions
# ============================================================================

setup_remote() {
    local host="$1"

    log_info "Setting up remote Neovim on $host..."

    # Validate config
    validate_config_dir

    # Ensure all binaries are cached locally
    ensure_binaries_cached

    # Create remote directory structure
    log_info "Creating remote directory structure..."
    ssh $SSH_OPTS "$host" "mkdir -p $REMOTE_DIR/{bin,config}" || {
        log_error "Failed to create remote directories"
        exit 1
    }

    # Transfer binaries to remote
    log_info "Transferring binaries to remote..."

    # Transfer Neovim
    scp $SSH_OPTS "$CACHE_DIR/nvim" "$host:$REMOTE_DIR/bin/nvim" || {
        log_error "Failed to transfer Neovim"
        exit 1
    }

    # Transfer ripgrep
    scp $SSH_OPTS "$CACHE_DIR/rg" "$host:$REMOTE_DIR/bin/rg" || {
        log_error "Failed to transfer ripgrep"
        exit 1
    }

    # Transfer fd
    scp $SSH_OPTS "$CACHE_DIR/fd" "$host:$REMOTE_DIR/bin/fd" || {
        log_error "Failed to transfer fd"
        exit 1
    }

    # Ensure binaries are executable on remote
    ssh $SSH_OPTS "$host" "chmod u+x $REMOTE_DIR/bin/nvim $REMOTE_DIR/bin/rg $REMOTE_DIR/bin/fd" || {
        log_error "Failed to set executable permissions on remote binaries"
        exit 1
    }

    # Transfer config files
    log_info "Transferring config files..."
    if command -v rsync &>/dev/null; then
        rsync -avz --delete \
            -e "ssh $SSH_OPTS" \
            --exclude='.git' \
            --exclude='.gitignore' \
            --exclude='lazy-lock.json' \
            "$CONFIG_DIR/" "$host:$REMOTE_DIR/config/nvim/" || {
            log_error "Failed to transfer config files"
            exit 1
        }
    else
        # Fallback to scp
        scp $SSH_OPTS -r "$CONFIG_DIR" "$host:$REMOTE_DIR/config/nvim" || {
            log_error "Failed to transfer config files"
            exit 1
        }
    fi

    # Install wrapper script
    log_info "Installing wrapper script..."
    if [ ! -f "$SCRIPT_DIR/rnvim" ]; then
        log_error "Wrapper script not found: $SCRIPT_DIR/rnvim"
        log_error "Ensure rnvim exists in the scripts directory"
        exit 1
    fi

    scp $SSH_OPTS "$SCRIPT_DIR/rnvim" "$host:$REMOTE_DIR/rnvim" || {
        log_error "Failed to copy wrapper script"
        exit 1
    }

    ssh $SSH_OPTS "$host" "chmod u+x $REMOTE_DIR/rnvim" || {
        log_error "Failed to set wrapper script permissions"
        exit 1
    }

    # Success message
    log_success "Setup complete on $host!"
    echo ""
    echo "To use remote neovim:"
    echo "  1. SSH into the remote host:"
    echo "     ssh $host"
    echo ""
    echo "  2. Run the wrapper script:"
    echo "     ~/.remote-nvim/rnvim <file>"
    echo ""
    echo "Note: Plugins will install automatically on first run (may take 30-60 seconds)"
    echo "      Tools are only added to PATH if not already available on the system"
    echo ""
}

sync_config() {
    local host="$1"

    log_info "Syncing config to $host..."

    # Validate config
    validate_config_dir

    # Check if remote setup exists
    if ! ssh $SSH_OPTS "$host" "[ -d $REMOTE_DIR ]"; then
        log_error "Remote neovim not set up on $host"
        log_error "Run 'setup' command first"
        exit 1
    fi

    # Sync config files
    log_info "Transferring config files..."
    if command -v rsync &>/dev/null; then
        rsync -avz --delete \
            -e "ssh $SSH_OPTS" \
            --exclude='.git' \
            --exclude='.gitignore' \
            --exclude='lazy-lock.json' \
            "$CONFIG_DIR/" "$host:$REMOTE_DIR/config/nvim/" || {
            log_error "Failed to sync config files"
            exit 1
        }
    else
        # Fallback to scp
        ssh $SSH_OPTS "$host" "rm -rf $REMOTE_DIR/config/nvim/*"
        scp $SSH_OPTS -r "$CONFIG_DIR/"* "$host:$REMOTE_DIR/config/nvim/" || {
            log_error "Failed to sync config files"
            exit 1
        }
    fi

    log_success "Config synced to $host"
}

cleanup_remote() {
    local host="$1"

    # Confirmation prompt
    if [ "$SKIP_CONFIRM" = false ]; then
        echo -n "Remove remote neovim from $host? This cannot be undone. (y/N) "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled"
            exit 0
        fi
    fi

    log_info "Cleaning up remote neovim on $host..."

    # Check if installation exists
    if ! ssh $SSH_OPTS "$host" "[ -d $REMOTE_DIR ]"; then
        log_warning "No remote neovim installation found on $host"
        exit 0
    fi

    # Remove installation directory
    log_info "Removing installation directory..."
    ssh $SSH_OPTS "$host" "rm -rf $REMOTE_DIR" || {
        log_error "Failed to remove installation directory"
        exit 1
    }

    log_success "Removed remote neovim from $host"
}

# ============================================================================
# Argument Parsing
# ============================================================================

parse_args() {
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi

    local command="$1"
    shift

    case "$command" in
    --help | -h)
        show_help
        exit 0
        ;;
    setup | sync | cleanup)
        if [ $# -eq 0 ]; then
            log_error "Missing host argument"
            echo ""
            show_help
            exit 1
        fi

        local host="$1"
        shift

        # Parse options
        while [ $# -gt 0 ]; do
            case "$1" in
            --config-dir)
                CONFIG_DIR="$2"
                shift 2
                ;;
            --ssh-opts)
                SSH_OPTS="$2"
                shift 2
                ;;
            --yes)
                SKIP_CONFIRM=true
                shift
                ;;
            -v | --verbose)
                VERBOSE=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
            esac
        done

        # Check dependencies
        check_dependencies

        # Test SSH connection
        test_ssh_connection "$host"

        # Execute command
        case "$command" in
        setup)
            setup_remote "$host"
            ;;
        sync)
            sync_config "$host"
            ;;
        cleanup)
            cleanup_remote "$host"
            ;;
        esac
        ;;
    *)
        log_error "Unknown command: $command"
        echo ""
        show_help
        exit 1
        ;;
    esac
}

# ============================================================================
# Main
# ============================================================================

main() {
    parse_args "$@"
}

main "$@"
