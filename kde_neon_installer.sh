#!/bin/bash

# KDE Neon Automated Installer
# Based on extracted Calamares installation commands
# Author: Generated from installation log analysis
# License: GPL-3.0

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/install.conf"
DEFAULT_LOG_FILE="${SCRIPT_DIR}/kde-install-$(date +%Y%m%d-%H%M%S).log"

# Global variables
DRY_RUN=false
LOG_FILE="$DEFAULT_LOG_FILE"
CUSTOM_CONFIG=""
FORCE_MODE=false
DEBUG=false
TARGET_DRIVE=""
INSTALL_ROOT="/target"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    
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
            [[ "$DEBUG" == "true" ]] && echo -e "${BLUE}DEBUG: $message${NC}"
            ;;
    esac
}

error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Command execution wrapper
execute_cmd() {
    local cmd="$1"
    local description="${2:-}"
    
    if [[ -n "$description" ]]; then
        log "INFO" "$description"
    fi
    
    log "DEBUG" "Executing: $cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    if ! eval "$cmd" 2>&1 | tee -a "$LOG_FILE"; then
        error_exit "Command failed: $cmd"
    fi
}

# Help function
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

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --log-path)
                LOG_FILE="$2"
                shift 2
                ;;
            --config)
                CUSTOM_CONFIG="$2"
                shift 2
                ;;
            --force)
                FORCE_MODE=true
                shift
                ;;
            --debug)
                DEBUG=true
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

# System validation functions
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root"
    fi
}

check_uefi() {
    if [[ ! -d /sys/firmware/efi ]]; then
        error_exit "UEFI boot mode required. Legacy BIOS not supported."
    fi
    log "INFO" "UEFI boot mode confirmed"
}

check_network() {
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        error_exit "Network connectivity required for installation"
    fi
    log "INFO" "Network connectivity confirmed"
}

# Drive enumeration and filtering
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

# Drive selection interface
select_target_drive() {
    local drives
    mapfile -t drives < <(enumerate_nvme_drives)
    
    if [[ ${#drives[@]} -eq 1 ]]; then
        TARGET_DRIVE="${drives[0]}"
        log "INFO" "Single drive detected: $TARGET_DRIVE"
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
        
        if [[ "$DRY_RUN" == "true" ]]; then
            TARGET_DRIVE="${drives[0]}"
            log "INFO" "[DRY-RUN] Using first drive: $TARGET_DRIVE"
        else
            read -r -p "Select drive (1-${#drives[@]}): " selection
            if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#drives[@]} ]]; then
                TARGET_DRIVE="${drives[$((selection-1))]}"
            else
                error_exit "Invalid selection"
            fi
        fi
    fi
    
    # Windows detection and safety check
    if detect_windows "$TARGET_DRIVE" && [[ "$FORCE_MODE" == "false" ]]; then
        log "WARN" "Windows installation detected on $TARGET_DRIVE"
        if [[ "$DRY_RUN" == "false" ]]; then
            read -r -p "Continue with installation? This may affect Windows boot. (y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                error_exit "Installation cancelled by user"
            fi
        fi
    fi
    
    log "INFO" "Target drive selected: $TARGET_DRIVE"
}

# Configuration management
load_configuration() {
    local config_file="${CUSTOM_CONFIG:-$CONFIG_FILE}"
    
    if [[ -f "$config_file" ]]; then
        log "INFO" "Loading configuration from: $config_file"
        # shellcheck source=/dev/null
        source "$config_file"
    else
        log "INFO" "No existing configuration found, will prompt for settings"
        return 1
    fi
}

save_configuration() {
    local config_file="${CUSTOM_CONFIG:-$CONFIG_FILE}"
    
    log "INFO" "Saving configuration to: $config_file"
    
    cat > "$config_file" << EOF
# KDE Neon Installation Configuration
# Generated: $(date)

# System settings
TARGET_DRIVE="$TARGET_DRIVE"
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
    
    if [[ "$DRY_RUN" == "false" ]]; then
        chmod 600 "$config_file"
    fi
}

# Installation phase functions
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

phase2_partitioning() {
    log "INFO" "=== Phase 2: Drive Partitioning ==="
    
    local drive="$TARGET_DRIVE"
    
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

phase3_system_installation() {
    log "INFO" "=== Phase 3: System Installation ==="
    
    local drive="$TARGET_DRIVE"
    local root_part="${drive}p2"
    local efi_part="${drive}p1"
    
    # Create mount points
    execute_cmd "mkdir -p $INSTALL_ROOT" "Creating installation root"
    execute_cmd "mkdir -p $INSTALL_ROOT/boot/efi" "Creating EFI mount point"
    
    # Mount partitions
    execute_cmd "mount $root_part $INSTALL_ROOT" "Mounting root partition"
    execute_cmd "mount $efi_part $INSTALL_ROOT/boot/efi" "Mounting EFI partition"
    
    # Copy system files (this would be extracted from the live ISO)
    log "INFO" "Copying system files (this will take several minutes)..."
    execute_cmd "rsync -av --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run --exclude=/tmp --exclude=/mnt --exclude=/media --exclude=/lost+found / $INSTALL_ROOT/" "Copying system files"
    
    # Create essential directories
    for dir in proc sys dev run tmp; do
        execute_cmd "mkdir -p $INSTALL_ROOT/$dir" "Creating /$dir directory"
    done
    
    # Create swap file
    local swap_size="${SWAP_SIZE:-4G}"
    execute_cmd "fallocate -l $swap_size $INSTALL_ROOT/swapfile" "Creating swap file"
    execute_cmd "chmod 600 $INSTALL_ROOT/swapfile" "Setting swap file permissions"
    execute_cmd "mkswap $INSTALL_ROOT/swapfile" "Formatting swap file"
    
    log "INFO" "Phase 3 completed successfully"
}

phase4_bootloader_configuration() {
    log "INFO" "=== Phase 4: Bootloader Configuration ==="
    
    local drive="$TARGET_DRIVE"
    
    # Mount essential filesystems in chroot
    execute_cmd "mount --bind /proc $INSTALL_ROOT/proc" "Binding /proc"
    execute_cmd "mount --bind /sys $INSTALL_ROOT/sys" "Binding /sys"
    execute_cmd "mount --bind /dev $INSTALL_ROOT/dev" "Binding /dev"
    execute_cmd "mount --bind /run $INSTALL_ROOT/run" "Binding /run"
    
    # Install GRUB
    execute_cmd "chroot $INSTALL_ROOT grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id='KDE Neon' $drive" "Installing GRUB bootloader"
    
    # Generate GRUB configuration
    execute_cmd "chroot $INSTALL_ROOT update-grub" "Generating GRUB configuration"
    
    # Update fstab
    local root_uuid
    local efi_uuid
    root_uuid=$(blkid -s UUID -o value "${drive}p2")
    efi_uuid=$(blkid -s UUID -o value "${drive}p1")
    
    cat > "$INSTALL_ROOT/etc/fstab" << EOF
# /etc/fstab: static file system information
UUID=$root_uuid / ext4 defaults 0 1
UUID=$efi_uuid /boot/efi vfat defaults 0 2
/swapfile none swap sw 0 0
EOF
    
    log "INFO" "Phase 4 completed successfully"
}

phase5_system_configuration() {
    log "INFO" "=== Phase 5: System Configuration ==="
    
    # Set timezone to local time
    execute_cmd "chroot $INSTALL_ROOT timedatectl set-local-rtc 1" "Setting system clock to local time"
    
    # Configure locale
    local locale="${LOCALE:-en_US.UTF-8}"
    execute_cmd "chroot $INSTALL_ROOT locale-gen $locale" "Generating locale"
    execute_cmd "chroot $INSTALL_ROOT update-locale LANG=$locale" "Setting system locale"
    
    # Set hostname
    local hostname="${HOSTNAME:-kde-neon}"
    execute_cmd "echo $hostname > $INSTALL_ROOT/etc/hostname" "Setting hostname"
    
    # Remove live system packages
    execute_cmd "chroot $INSTALL_ROOT apt-get --purge -q -y remove calamares neon-live casper" "Removing live system packages"
    execute_cmd "chroot $INSTALL_ROOT apt-get --purge -q -y autoremove" "Cleaning up packages"
    
    # KDE Neon specific configurations
    if [[ -x "/usr/bin/calamares-l10n-helper" ]]; then
        execute_cmd "chroot $INSTALL_ROOT /usr/bin/calamares-l10n-helper" "Configuring localization"
    fi
    
    # Update initramfs
    execute_cmd "chroot $INSTALL_ROOT update-initramfs -u" "Updating initramfs"
    
    # Unmount chroot filesystems
    execute_cmd "umount $INSTALL_ROOT/proc $INSTALL_ROOT/sys $INSTALL_ROOT/dev $INSTALL_ROOT/run" "Unmounting chroot filesystems"
    execute_cmd "umount $INSTALL_ROOT/boot/efi $INSTALL_ROOT" "Unmounting installation partitions"
    
    log "INFO" "Phase 5 completed successfully"
}

# Main installation function
main_installation() {
    log "INFO" "Starting KDE Neon installation process"
    log "INFO" "Target drive: $TARGET_DRIVE"
    log "INFO" "Dry run mode: $DRY_RUN"
    
    phase1_system_preparation
    phase2_partitioning
    phase3_system_installation
    phase4_bootloader_configuration
    phase5_system_configuration
    
    log "INFO" "Installation completed successfully!"
    log "INFO" "System is ready to reboot"
}

# Main script execution
main() {
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log "INFO" "KDE Neon Automated Installer started"
    log "INFO" "Log file: $LOG_FILE"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Load existing configuration if available
    load_configuration || true
    
    # Select target drive
    select_target_drive
    
    # Save configuration for future runs
    save_configuration
    
    # Confirm installation
    if [[ "$DRY_RUN" == "false" ]]; then
        echo -e "\n${YELLOW}Installation Summary:${NC}"
        echo -e "Target Drive: ${GREEN}$TARGET_DRIVE${NC}"
        echo -e "Installation Root: ${GREEN}$INSTALL_ROOT${NC}"
        echo -e "Log File: ${GREEN}$LOG_FILE${NC}"
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