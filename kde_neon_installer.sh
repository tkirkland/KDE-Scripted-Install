#!/bin/bash

# KDE Neon Automated Installer
# Based on extracted Calamares installation commands
# Author: Generated from installation log analysis
# License: GPL-3.0

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables (initialized in main)
dry_run=false
log_file=""
custom_config=""
force_mode=false
debug=false
target_drive=""
install_root=""

# Log messages with timestamp and color coding
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$log_file"
    
    case "$level" in
        "ERROR")
            echo -e "${RED}ERROR: $message${NC}" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}WARNING: $message${NC}" >&2
            ;;
        "INFO")
            echo -e "${GREEN}INFO: $message${NC}"
            ;;
        "DEBUG")
            [[ "$debug" == "true" ]] && echo -e "${BLUE}DEBUG: $message${NC}"
            ;;
    esac
}

# Exit with error message and status code 1
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Execute command with logging and dry-run support
execute_cmd() {
    local cmd="$1"
    local description="${2:-}"
    
    if [[ -n "$description" ]]; then
        log "INFO" "$description"
    fi
    
    log "DEBUG" "Executing: $cmd"
    
    if [[ "$dry_run" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    if ! eval "$cmd" 2>&1 | tee -a "$log_file"; then
        error_exit "Command failed: $cmd"
    fi
}

# Display help information and usage examples
show_help() {
    cat << EOF
KDE Neon Automated Installer

Usage: $0 [options]

Options:
    --dry-run              Test mode - show what would be done
    --log-path PATH        Custom log file location
    --config PATH          Use custom configuration file
    --force                Skip safety checks (use with caution)
    --debug                Enable debug output
    --help                 Show this help message

Examples:
    $0 --dry-run                    # Test installation without changes
    $0 --log-path /var/log/install.log  # Custom log location
    $0 --config /path/to/custom.conf     # Use custom configuration

EOF
}

# Parse command line arguments and set global variables
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --log-path)
                log_file="$2"
                shift 2
                ;;
            --config)
                custom_config="$2"
                shift 2
                ;;
            --force)
                force_mode=true
                shift
                ;;
            --debug)
                debug=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
}

# Check if running as root user (required for installation)
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root"
    fi
}

# Verify UEFI boot mode is enabled
check_uefi() {
    if [[ ! -d /sys/firmware/efi ]]; then
        error_exit "UEFI boot mode required. Legacy BIOS not supported."
    fi
    log "INFO" "UEFI boot mode confirmed"
}

# Test network connectivity (required for package downloads)
check_network() {
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        error_exit "Network connectivity required for installation"
    fi
    log "INFO" "Network connectivity confirmed"
}

# Find and list available internal NVMe drives
enumerate_nvme_drives() {
    local drives=()
    
    log "INFO" "Enumerating NVMe drives..."
    
    for drive in /dev/nvme*n*; do
        if [[ -b "$drive" && ! "$drive" =~ nvme[0-9]+n[0-9]+p[0-9]+ ]]; then
            # Check if it's an internal drive (not USB)
            local drive_name
            drive_name=$(basename "$drive")
            local sys_path="/sys/block/$drive_name"
            
            if [[ -e "$sys_path" ]]; then
                local removable
                removable=$(cat "$sys_path/removable" 2>/dev/null || echo "0")
                if [[ "$removable" == "0" ]]; then
                    drives+=("$drive")
                    log "DEBUG" "Found internal NVMe drive: $drive"
                fi
            fi
        fi
    done
    
    if [[ ${#drives[@]} -eq 0 ]]; then
        error_exit "No suitable NVMe drives found"
    fi
    
    printf '%s\n' "${drives[@]}"
}

# Detect Windows installation on specified drive for dual-boot safety
detect_windows() {
    local drive="$1"
    log "INFO" "Checking for Windows installation on $drive"
    
    # Check for Windows Boot Manager
    if efibootmgr | grep -i "Windows Boot Manager" &>/dev/null; then
        log "WARN" "Windows Boot Manager detected in EFI"
        return 0
    fi
    
    # Check partitions for Windows signatures
    for partition in "${drive}"p*; do
        if [[ -b "$partition" ]]; then
            local fs_type
            local label
            fs_type=$(blkid -o value -s TYPE "$partition" 2>/dev/null || echo "")
            label=$(blkid -o value -s LABEL "$partition" 2>/dev/null || echo "")
            
            if [[ "$fs_type" == "ntfs" ]] || [[ "$label" =~ ^(Windows|System|Recovery) ]]; then
                log "WARN" "Windows partition detected: $partition ($fs_type, $label)"
                return 0
            fi
        fi
    done
    
    return 1
}

# Interactive drive selection with Windows detection and safety checks
select_target_drive() {
    local drives
    mapfile -t drives < <(enumerate_nvme_drives)
    
    if [[ ${#drives[@]} -eq 1 ]]; then
        target_drive="${drives[0]}"
        log "INFO" "Single drive detected: $target_drive"
    else
        log "INFO" "Multiple drives detected:"
        for i in "${!drives[@]}"; do
            local drive="${drives[$i]}"
            local size
            local size_gb
            local model
            size=$(lsblk -b -d -o SIZE "$drive" 2>/dev/null | tail -n1)
            size_gb=$((size / 1024 / 1024 / 1024))
            model=$(lsblk -d -o MODEL "$drive" 2>/dev/null | tail -n1)
            
            echo "  $((i+1)). $drive - ${size_gb}GB - $model"
        done
        
        if [[ "$dry_run" == "true" ]]; then
            target_drive="${drives[0]}"
            log "INFO" "[DRY-RUN] Using first drive: $target_drive"
        else
            read -r -p "Select drive (1-${#drives[@]}): " selection
            if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#drives[@]} ]]; then
                target_drive="${drives[$((selection-1))]}"
            else
                error_exit "Invalid selection"
            fi
        fi
    fi
    
    # Windows detection and safety check
    if detect_windows "$target_drive" && [[ "$force_mode" == "false" ]]; then
        log "WARN" "Windows installation detected on $target_drive"
        if [[ "$dry_run" == "false" ]]; then
            read -r -p "Continue with installation? This may affect Windows boot. (y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                error_exit "Installation cancelled by user"
            fi
        fi
    fi
    
    log "INFO" "Target drive selected: $target_drive"
}

# Load configuration from file if it exists
load_configuration() {
    local config_file="${custom_config:-$DEFAULT_CONFIG_FILE}"
    
    if [[ -f "$config_file" ]]; then
        log "INFO" "Loading configuration from: $config_file"
        # shellcheck source=/dev/null
        source "$config_file"
    else
        log "INFO" "No existing configuration found, will prompt for settings"
        return 1
    fi
}

# Save current installation configuration to file
save_configuration() {
    local config_file="${custom_config:-$DEFAULT_CONFIG_FILE}"
    
    log "INFO" "Saving configuration to: $config_file"
    
    cat > "$config_file" << EOF
# KDE Neon Installation Configuration
# Generated: $(date)

# System settings
TARGET_DRIVE="$target_drive"
LOCALE="${LOCALE:-en_US.UTF-8}"
TIMEZONE="${TIMEZONE:-UTC}"
KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT:-us}"

# User settings
USERNAME="${USERNAME:-user}"
HOSTNAME="${HOSTNAME:-kde-neon}"

# Storage settings
SWAP_SIZE="${SWAP_SIZE:-4G}"
ROOT_FS="${ROOT_FS:-ext4}"

# Network settings  
NETWORK_CONFIG="${NETWORK_CONFIG:-dhcp}"
EOF
    
    if [[ "$dry_run" == "false" ]]; then
        chmod 600 "$config_file"
    fi
}

# Phase 1: System preparation, validation, and package installation
phase1_system_preparation() {
    log "INFO" "=== Phase 1: System Preparation ==="
    
    check_root
    check_uefi
    check_network
    
    # Update package database
    execute_cmd "apt-get update" "Updating package database"
    
    # Install required packages
    execute_cmd "apt-get install -y parted gdisk dosfstools e2fsprogs" "Installing partitioning tools"
    
    log "INFO" "Phase 1 completed successfully"
}

# Phase 2: Create GPT partitions and format filesystems
phase2_partitioning() {
    log "INFO" "=== Phase 2: Drive Partitioning ==="
    
    local drive="$target_drive"
    
    # Unmount any existing partitions
    execute_cmd "umount ${drive}p* 2>/dev/null || true" "Unmounting existing partitions"
    
    # Create new GPT partition table
    execute_cmd "parted -s $drive mklabel gpt" "Creating GPT partition table"
    
    # Create EFI system partition (512MB)
    execute_cmd "parted -s $drive mkpart primary fat32 1MiB 513MiB" "Creating EFI system partition"
    execute_cmd "parted -s $drive set 1 esp on" "Setting EFI system partition flag"
    
    # Create root partition (remaining space)
    execute_cmd "parted -s $drive mkpart primary ext4 513MiB 100%" "Creating root partition"
    
    # Wait for kernel to recognize partitions
    execute_cmd "partprobe $drive" "Refreshing partition table"
    execute_cmd "sleep 2" "Waiting for partition recognition"
    
    # Format EFI partition
    execute_cmd "mkfs.fat -F32 -n EFI ${drive}p1" "Formatting EFI partition"
    
    # Format root partition
    execute_cmd "mkfs.ext4 -F -L KDE-Neon ${drive}p2" "Formatting root partition"
    
    log "INFO" "Phase 2 completed successfully"
}

# Phase 3: Mount filesystems, copy system files, and create swap
phase3_system_installation() {
    log "INFO" "=== Phase 3: System Installation ==="
    
    local drive="$target_drive"
    local root_part="${drive}p2"
    local efi_part="${drive}p1"
    
    # Create mount points
    execute_cmd "mkdir -p $install_root" "Creating installation root"
    execute_cmd "mkdir -p $install_root/boot/efi" "Creating EFI mount point"
    
    # Mount partitions
    execute_cmd "mount $root_part $install_root" "Mounting root partition"
    execute_cmd "mount $efi_part $install_root/boot/efi" "Mounting EFI partition"
    
    # Copy system files (this would be extracted from the live ISO)
    log "INFO" "Copying system files (this will take several minutes)..."
    execute_cmd "rsync -av --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run --exclude=/tmp --exclude=/mnt --exclude=/media --exclude=/lost+found / $install_root/" "Copying system files"
    
    # Create essential directories
    for dir in proc sys dev run tmp; do
        execute_cmd "mkdir -p $install_root/$dir" "Creating /$dir directory"
    done
    
    # Create swap file
    local swap_file_size="${swap_size:-4G}"
    execute_cmd "fallocate -l $swap_file_size $install_root/swapfile" "Creating swap file"
    execute_cmd "chmod 600 $install_root/swapfile" "Setting swap file permissions"
    execute_cmd "mkswap $install_root/swapfile" "Formatting swap file"
    
    log "INFO" "Phase 3 completed successfully"
}

# Phase 4: Install GRUB bootloader and configure fstab
phase4_bootloader_configuration() {
    log "INFO" "=== Phase 4: Bootloader Configuration ==="
    
    local drive="$target_drive"
    
    # Mount essential filesystems in chroot
    execute_cmd "mount --bind /proc $install_root/proc" "Binding /proc"
    execute_cmd "mount --bind /sys $install_root/sys" "Binding /sys"
    execute_cmd "mount --bind /dev $install_root/dev" "Binding /dev"
    execute_cmd "mount --bind /run $install_root/run" "Binding /run"
    
    # Install GRUB
    execute_cmd "chroot $install_root grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id='KDE Neon' $drive" "Installing GRUB bootloader"
    
    # Generate GRUB configuration
    execute_cmd "chroot $install_root update-grub" "Generating GRUB configuration"
    
    # Update fstab
    local root_uuid
    local efi_uuid
    root_uuid=$(blkid -s UUID -o value "${drive}p2")
    efi_uuid=$(blkid -s UUID -o value "${drive}p1")
    
    cat > "$install_root/etc/fstab" << EOF
# /etc/fstab: static file system information
UUID=$root_uuid / ext4 defaults 0 1
UUID=$efi_uuid /boot/efi vfat defaults 0 2
/swapfile none swap sw 0 0
EOF
    
    log "INFO" "Phase 4 completed successfully"
}

# Phase 5: Configure locale, hostname, and cleanup live packages
phase5_system_configuration() {
    log "INFO" "=== Phase 5: System Configuration ==="
    
    # Set timezone to local time
    execute_cmd "chroot $install_root timedatectl set-local-rtc 1" "Setting system clock to local time"
    
    # Configure locale
    local locale="${LOCALE:-en_US.UTF-8}"
    execute_cmd "chroot $install_root locale-gen $locale" "Generating locale"
    execute_cmd "chroot $install_root update-locale LANG=$locale" "Setting system locale"
    
    # Set hostname
    local hostname="${HOSTNAME:-kde-neon}"
    execute_cmd "echo $hostname > $install_root/etc/hostname" "Setting hostname"
    
    # Remove live system packages
    execute_cmd "chroot $install_root apt-get --purge -q -y remove calamares neon-live casper" "Removing live system packages"
    execute_cmd "chroot $install_root apt-get --purge -q -y autoremove" "Cleaning up packages"
    
    # KDE Neon specific configurations
    if [[ -x "/usr/bin/calamares-l10n-helper" ]]; then
        execute_cmd "chroot $install_root /usr/bin/calamares-l10n-helper" "Configuring localization"
    fi
    
    # Update initramfs
    execute_cmd "chroot $install_root update-initramfs -u" "Updating initramfs"
    
    # Unmount chroot filesystems
    execute_cmd "umount $install_root/proc $install_root/sys $install_root/dev $install_root/run" "Unmounting chroot filesystems"
    execute_cmd "umount $install_root/boot/efi $install_root" "Unmounting installation partitions"
    
    log "INFO" "Phase 5 completed successfully"
}

# Execute all installation phases in sequence
main_installation() {
    log "INFO" "Starting KDE Neon installation process"
    log "INFO" "Target drive: $target_drive"
    log "INFO" "Dry run mode: $dry_run"
    
    phase1_system_preparation
    phase2_partitioning
    phase3_system_installation
    phase4_bootloader_configuration
    phase5_system_configuration
    
    log "INFO" "Installation completed successfully!"
    log "INFO" "System is ready to reboot"
}

# Main script entry point with argument parsing and installation flow
main() {
    # Initialize constants
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    readonly SCRIPT_DIR="$script_dir"
    readonly DEFAULT_CONFIG_FILE="${SCRIPT_DIR}/install.conf"
    readonly DEFAULT_INSTALL_ROOT="/target"
    
    # Initialize global variables
    install_root="$DEFAULT_INSTALL_ROOT"
    
    # Parse command line arguments first
    parse_arguments "$@"
    
    # Set default log file if not specified
    if [[ -z "$log_file" ]]; then
        log_file="${SCRIPT_DIR}/logs/kde-install-$(date +%Y%m%d-%H%M%S).log"
    fi
    
    # Initialize logging
    mkdir -p "$(dirname "$log_file")"
    
    log "INFO" "KDE Neon Automated Installer started"
    log "INFO" "Log file: $log_file"
    
    # Load existing configuration if available
    load_configuration || true
    
    # Select target drive
    select_target_drive
    
    # Save configuration for future runs
    save_configuration
    
    # Confirm installation
    if [[ "$dry_run" == "false" ]]; then
        echo -e "\n${YELLOW}Installation Summary:${NC}"
        echo -e "Target Drive: ${GREEN}$target_drive${NC}"
        echo -e "Installation Root: ${GREEN}$install_root${NC}"
        echo -e "Log File: ${GREEN}$log_file${NC}"
        echo
        
        read -r -p "Proceed with installation? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log "INFO" "Installation cancelled by user"
            exit 0
        fi
    fi
    
    # Run main installation
    main_installation
    
    log "INFO" "KDE Neon Automated Installer completed"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi