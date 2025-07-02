#!/bin/bash
#
# Module: System Validation and Detection
# Purpose: Hardware validation, system checks, and safety detection functions
# Dependencies: core.sh, ui.sh

#######################################
# Load dependencies
#######################################
if [[ -z "${SCRIPT_DIR:-}" ]]; then
  readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
# Source core.sh and ui.sh only if not already loaded
if [[ -z "${CORE_VERSION:-}" ]]; then
  source "${SCRIPT_DIR}/lib/core.sh"
fi
if [[ -z "${UI_VERSION:-}" ]]; then
  source "${SCRIPT_DIR}/lib/ui.sh"
fi

#######################################
# Validation module constants
#######################################
readonly VALIDATION_VERSION="1.0"

#######################################
# Check if running as the root user (required for installation).
# Automatically escalates privileges using sudo if available.
# Provides clear error messages and guidance for privilege issues.
# Globals:
#   EUID - User ID to check for root privileges
# Arguments:
#   $@ - All command line arguments to preserve for sudo escalation
# Outputs:
#   Instructions for gaining root access if needed
#   Attempts automatic sudo escalation
# Returns:
#   0 if running as root, exits if cannot gain privileges
#######################################
check_root() {
  if [[ $EUID -ne 0 ]]; then
    # Try to relaunch with sudo, preserving all arguments
    if command -v sudo >/dev/null 2>&1; then
      ui_status "info" "Attempting to escalate privileges with sudo..."
      exec sudo "$0" "$@"
    else
      ui_status "error" "Root privileges required for installation"
      ui_status "info" "This installer needs to modify system partitions"
      ui_status "error" "sudo not available - please run as root"
      echo "Please run: sudo $0"
      exit 1
    fi
  fi
  log "INFO" "Root privileges confirmed"
}

#######################################
# Verify UEFI boot mode is enabled on the system.
# Modern installer requires UEFI for proper EFI partition management.
# Provides detailed instructions for enabling UEFI if needed.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Error messages and UEFI setup instructions if legacy mode detected
# Returns:
#   0 if UEFI mode confirmed, exits with 1 if legacy BIOS detected
#######################################
check_uefi() {
  if [[ ! -d /sys/firmware/efi ]]; then
    ui_status "error" "UEFI Boot Mode Required"
    echo
    ui_status "warn" "Your computer is using legacy BIOS mode"
    ui_status "info" "This installer only supports UEFI systems"
    echo
    ui_section "To Enable UEFI Mode"
    ui_status "arrow" "Restart your computer"
    ui_status "arrow" "Enter BIOS/UEFI settings (F2, F12, or Delete)"
    ui_status "arrow" "Enable UEFI boot mode"
    ui_status "arrow" "Disable Legacy/CSM mode"
    ui_status "arrow" "Boot from KDE Neon USB in UEFI mode"
    exit 1
  fi
  ui_status "success" "UEFI boot mode confirmed"
  log "INFO" "UEFI boot mode confirmed"
}

#######################################
# Test network connectivity required for package downloads.
# Installer needs internet access for updates and driver installation.
# Provides clear explanation of network requirements.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Network connectivity status and requirements if connection fails
# Returns:
#   0 if network available, exits with error if no connectivity
#######################################
check_network() {
  ui_status "info" "Checking internet connection..."
  
  if ! ping -c 1 8.8.8.8 &> /dev/null; then
    ui_status "error" "Internet Connection Required"
    echo
    ui_section "Network Requirements"
    ui_status "info" "Download updated packages"
    ui_status "info" "Install graphics drivers"
    ui_status "info" "Configure system updates"
    echo
    ui_status "warn" "Please connect to the internet and try again"
    error_exit "Network connectivity required for installation"
  fi
  
  ui_status "success" "Internet connection confirmed"
  log "INFO" "Network connectivity confirmed"
}

#######################################
# Check for global Windows EFI entries (system-wide detection).
# Detects Windows Boot Manager and Microsoft EFI entries to prevent
# accidental overwrites during dual-boot scenarios.
# Globals:
#   show_win - Flag to control Windows detection display
# Arguments:
#   None
# Outputs:
#   Windows detection warnings if show_win flag is enabled
# Returns:
#   0 if Windows detected, 1 if no Windows found
#######################################
detect_windows_efi() {
  # Method 1: Check for Windows Boot Manager in EFI
  if efibootmgr | grep -i "Windows Boot Manager" &> /dev/null; then
    if [[ "${show_win:-false}" == "true" ]]; then
      log "WARN" "Windows Boot Manager detected in EFI"
    fi
    return 0
  fi

  # Method 2: Check for Microsoft EFI entries
  if efibootmgr | grep -i "Microsoft" &> /dev/null; then
    if [[ "${show_win:-false}" == "true" ]]; then
      log "WARN" "Microsoft EFI entry detected"
    fi
    return 0
  fi

  return 1
}

#######################################
# Detect Windows installation on specified drive for dual-boot safety.
# Comprehensive detection using multiple methods to prevent data loss.
# Checks NTFS partitions, Windows directories, and EFI signatures.
# Globals:
#   None
# Arguments:
#   $1: Drive path to check (e.g., /dev/nvme0n1)
# Outputs:
#   Detailed logging of Windows detection methods and results
# Returns:
#   0 if Windows installation detected, 1 if no Windows found
#######################################
detect_windows() {
  local drive="$1"

  # Check partitions for Windows signatures
  local partition
  for partition in "${drive}"p*; do
    if [[ -b "$partition" ]]; then
      local fs_type
      local label
      fs_type=$(blkid -o value -s TYPE "$partition" 2> /dev/null || echo "")
      label=$(blkid -o value -s LABEL "$partition" 2> /dev/null || echo "")

      # Method 1: Check for Windows-specific filesystem signatures
      if [[ "$fs_type" == "ntfs" ]]; then
        # Mount temporarily to check for Windows directories
        local temp_mount="/tmp/win_check_$$"
        mkdir -p "$temp_mount"
        if mount -t ntfs -o ro "$partition" "$temp_mount" 2> /dev/null; then
          # Check for Windows directory structure
          if [[ -d "$temp_mount/Windows" ]] || [[ -d "$temp_mount/windows" ]] \
             || [[ -f "$temp_mount/bootmgr" ]] || [[ -f "$temp_mount/BOOTMGR" ]] \
             || [[ -d "$temp_mount/System Volume Information" ]]; then
            umount "$temp_mount" 2> /dev/null
            rmdir "$temp_mount" 2> /dev/null
            log "INFO" "Windows installation detected on $partition"
            return 0
          fi
          umount "$temp_mount" 2> /dev/null
        fi
        rmdir "$temp_mount" 2> /dev/null

        # Even if we can't mount, NTFS is suspicious
        log "INFO" "NTFS partition found on $partition - potential Windows"
        return 0
      fi

      # Method 2: Check for Windows-specific labels
      if [[ "$label" =~ ^(Windows|System|Recovery|Microsoft)$ ]]; then
        log "INFO" "Windows-related partition label detected: $label"
        return 0
      fi

      # Method 3: Check for EFI system partition with Windows content
      if [[ "$fs_type" == "vfat" ]] && [[ "$label" =~ ^(EFI|SYSTEM)$ ]]; then
        local temp_mount="/tmp/efi_check_$$"
        mkdir -p "$temp_mount"
        if mount -t vfat -o ro "$partition" "$temp_mount" 2> /dev/null; then
          # Check for Microsoft boot files in the EFI partition
          if [[ -d "$temp_mount/EFI/Microsoft" ]]; then
            umount "$temp_mount" 2> /dev/null
            rmdir "$temp_mount" 2> /dev/null
            log "INFO" "Microsoft EFI directory found on $partition"
            return 0
          fi
          umount "$temp_mount" 2> /dev/null
        fi
        rmdir "$temp_mount" 2> /dev/null
      fi
    fi
  done

  return 1
}

#######################################
# Check for existing KDE entries in EFI boot manager.
# Manages boot entry conflicts and provides user control over
# duplicate or orphaned entries from previous installations.
# Globals:
#   dry_run - Flag to control actual vs simulated operations
#   target_drive - Drive being used for current installation
# Arguments:
#   None
# Outputs:
#   Professional UI for boot entry management decisions
#   Lists existing KDE entries with drive information
# Returns:
#   Always returns 0 (handles errors internally)
#######################################
check_existing_kde_entries() {
  local kde_entries
  kde_entries=$(efibootmgr | grep -i "KDE" || true)
  
  if [[ -n "$kde_entries" ]]; then
    ui_section "Existing KDE Boot Entries Found"
    echo "$kde_entries"
    echo
    
    # Parse entries and separate by drive
    local target_entries=()
    local other_entries=()
    
    while IFS= read -r line; do
      if [[ -n "$line" ]]; then
        local boot_num
        boot_num=$(echo "$line" | grep -o "Boot[0-9A-F]*" | sed 's/Boot//')
        
        # Get detailed entry info
        local entry_details
        entry_details=$(efibootmgr -v | grep "Boot${boot_num}" || true)
        
        if [[ "$entry_details" =~ $target_drive ]]; then
          target_entries+=("$boot_num")
        else
          other_entries+=("$boot_num:$line")
        fi
      fi
    done <<< "$kde_entries"
    
    # Handle entries on target drive (automatic removal)
    if [[ ${#target_entries[@]} -gt 0 ]]; then
      ui_status "warn" "Found ${#target_entries[@]} KDE entries on target drive"
      ui_status "info" "These will be automatically removed to prevent conflicts"
      
      for boot_num in "${target_entries[@]}"; do
        if [[ "${dry_run:-false}" == "false" ]]; then
          execute_cmd "efibootmgr -b $boot_num -B" \
                     "Removing KDE boot entry $boot_num"
        else
          echo "[DRY-RUN] Would remove boot entry: $boot_num"
        fi
      done
    fi
    
    # Handle entries on other drives (user choice)
    if [[ ${#other_entries[@]} -gt 0 ]]; then
      ui_section "KDE Entries on Other Drives"
      ui_status "info" "Found KDE entries on other drives:"
      
      for entry in "${other_entries[@]}"; do
        local boot_num="${entry%%:*}"
        local description="${entry#*:}"
        ui_field "Entry $boot_num" "$description"
      done
      
      echo
      ui_status "warn" "These may be from previous installations"
      
      if [[ "${dry_run:-false}" == "false" ]]; then
        local remove_others
        remove_others=$(ui_input "Remove entries from other drives?" "n" "confirm")
        
        if [[ "$remove_others" == "y" ]]; then
          for entry in "${other_entries[@]}"; do
            local boot_num="${entry%%:*}"
            execute_cmd "efibootmgr -b $boot_num -B" \
                       "Removing KDE boot entry $boot_num"
          done
          ui_status "success" "Removed KDE entries from other drives"
        else
          ui_status "info" "Keeping existing entries on other drives"
        fi
      else
        echo "[DRY-RUN] Would prompt: Remove entries from other drives? (y/n)"
      fi
    fi
  else
    ui_status "info" "No existing KDE boot entries found"
  fi
}