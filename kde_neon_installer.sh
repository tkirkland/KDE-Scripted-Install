#!/bin/bash

# KDE Neon Automated Installer
# Based on extracted Calamares installation commands
# Author: Generated from installation log analysis
# License: GPL-3.0
# Version: 2.0

set -euo pipefail


#######################################
# Global constants - Google Style Compliant
#######################################
readonly VERSION="2.0"

#######################################
# Module loading function - Google Style Compliant
#######################################
load_modules() {
  local script_dir lib_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  lib_dir="${script_dir}/lib"
  
  # Source required modules
  source "${lib_dir}/core.sh"
  source "${lib_dir}/ui.sh"
  source "${lib_dir}/validation.sh"
  source "${lib_dir}/hardware.sh"
  source "${lib_dir}/config.sh"
  source "${lib_dir}/network.sh"
  
  # Module loading complete - no additional globals needed
}

# Display help information and usage examples
show_help() {
  cat << EOF
KDE Neon Automated Installer v$VERSION

Usage: $0 [options]

Options:
  --dry-run              Test mode - show what would be done
  --log-path PATH        Custom log file location
  --config PATH          Use custom configuration file
  --force                Skip Windows detection safety checks (DANGEROUS: may overwrite Windows)
  --debug                Show detailed technical output during installation
  --show-win             Show drives containing Windows in selection (normally hidden for safety)
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
        export debug=true
        shift
        ;;
      --show-win)
        show_win=true
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

# Check if running as the root user (required for installation)
check_root() {
  if [[ $EUID -ne 0 ]]; then
    # Try to relaunch with sudo, preserving all arguments
    if command -v sudo >/dev/null 2>&1; then
      echo "Attempting to relaunch with sudo..."
      exec sudo "$0" "$@"
    else
      echo -e "${RED}Root privileges required${NC}"
      echo "This installer needs to modify system partitions and install software."
      echo -e "${RED}Error: sudo not available${NC}"
      echo "Please run as root or install sudo, then run: sudo $0"
      exit 1
    fi
  fi
}

# Verify UEFI boot mode is enabled
check_uefi() {
  if [[ ! -d /sys/firmware/efi ]]; then
    echo -e "${RED}UEFI Boot Mode Required${NC}"
    echo "This installer only works on computers booted in UEFI mode."
    echo "Your computer appears to be using legacy BIOS mode."
    echo ""
    echo "To fix this:"
    echo "  1. Restart your computer"
    echo "  2. Enter BIOS/UEFI settings (usually F2, F12, or Delete during boot)"
    echo "  3. Enable UEFI boot mode and disable Legacy/CSM mode"
    echo "  4. Boot from the KDE Neon USB in UEFI mode"
    exit 1
  fi
  log "INFO" "UEFI boot mode confirmed"
}

# Test network connectivity (required for package downloads)
check_network() {
  echo "Checking internet connection..."
  if ! ping -c 1 8.8.8.8 &> /dev/null; then
    echo -e "${RED}Internet Connection Required${NC}"
    echo "KDE Neon installation needs internet access to:"
    echo "  • Download updated packages"
    echo "  • Install graphics drivers"
    echo "  • Configure system updates"
    echo ""
    echo "Please connect to the internet and try again."
    error_exit "Network connectivity required for installation"
  fi
  echo -e "${GREEN}✓ Internet connection confirmed${NC}"
  log "INFO" "Network connectivity confirmed"
}

# Hardware detection functions are now in lib/hardware.sh

# Check for global Windows EFI entries (system-wide, not drive-specific)
detect_windows_efi() {
  # Method 1: Check for Windows Boot Manager in EFI
  if efibootmgr | grep -i "Windows Boot Manager" &> /dev/null; then
    if [[ $show_win == "true"   ]]; then
      log "WARN" "Windows Boot Manager detected in EFI"
    fi
    return 0
  fi

  # Method 2: Check for Microsoft EFI entries
  if efibootmgr | grep -i "Microsoft" &> /dev/null; then
    if [[ $show_win == "true"   ]]; then
      log "WARN" "Microsoft EFI entry detected"
    fi
    return 0
  fi

  return 1
}

# Detect Windows installation on a specified drive for dual-boot safety
detect_windows() {
  local drive="$1"

  # Check partitions for Windows signatures
  local partition
  for partition in "${drive}"p*; do
    if [[ -b $partition   ]]; then
      local fs_type
      local label
      fs_type=$(blkid -o value -s TYPE "$partition" 2> /dev/null || echo "")
      label=$(blkid -o value -s LABEL "$partition" 2> /dev/null || echo "")
      # uuid=$(blkid -o value -s UUID "$partition" 2> /dev/null || echo "")

      
      # Method 4: Check for Windows-specific filesystem signatures
      if [[ $fs_type == "ntfs"   ]]; then
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
            # Windows installation detected on partition
            return 0
          fi
          umount "$temp_mount" 2> /dev/null
        fi
        rmdir "$temp_mount" 2> /dev/null

        # Even if we can't mount, NTFS is suspicious
        # NTFS partition found - potential Windows installation
        return 0
      fi

      # Method 5: Check for Windows-specific labels
      if [[ $label =~ ^(Windows|System|Recovery|Microsoft)$   ]]; then
        # Windows-related partition label detected
        return 0
      fi

      # Method 6: Check for EFI system partition with Windows content
      if [[ $fs_type == "vfat"   ]] && [[ $label =~ ^(EFI|SYSTEM)$   ]]; then
        local temp_mount="/tmp/efi_check_$$"
        mkdir -p "$temp_mount"
        if mount -t vfat -o ro "$partition" "$temp_mount" 2> /dev/null; then
          # Check for Microsoft boot files in the EFI partition
          if [[ -d "$temp_mount/EFI/Microsoft" ]]; then
            umount "$temp_mount" 2> /dev/null
            rmdir "$temp_mount" 2> /dev/null
            # Windows EFI boot files detected
            return 0
          fi
          umount "$temp_mount" 2> /dev/null
        fi
        rmdir "$temp_mount" 2> /dev/null
      fi
    fi
  done

  # Method 7: Check for Windows Registry hives or hiberfil.sys
  for partition in "${drive}"p*; do
    if [[ -b $partition   ]]; then
      # Use file command to check for Windows-specific file signatures
      if command -v file > /dev/null 2>&1; then
        # Check for NTFS volume with the Windows boot sector
        local fs_sig
        fs_sig=$(file -s "$partition" 2> /dev/null | grep -i "ntfs\|windows\|microsoft")
        if [[ -n $fs_sig   ]]; then
          # Windows filesystem signature detected
          return 0
        fi
      fi
    fi
  done

  # No Windows installation detected on this drive
  return 1
}

# Check existing KDE entries and prompt user about non-target-drive entries
check_existing_kde_entries() {
  local target_drive="$1"
  local target_efi_partition="${target_drive}p1"
  
  log "INFO" "Checking for existing KDE boot entries..."
  
  # Get current entries and exclude our newly created "KDE Neon" entry
  local all_kde_entries
  all_kde_entries=$(efibootmgr -v | grep -E "(KDE|neon)" || true)
  
  # Filter out the newly created entry (bootloader-id "KDE Neon")
  local kde_entries_info
  kde_entries_info=$(echo "$all_kde_entries" | grep -v "KDE Neon" || true)
  
  if [[ -z "$kde_entries_info" ]]; then
    log "INFO" "No existing KDE boot entries found"
    return 0
  fi
  
  # Parse entries and separate target-drive vs. other-drive entries
  local target_drive_entries=()
  local other_drive_entries=()
  local entry_details=()
  local line
  
  while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      local boot_num
      boot_num=$(echo "$line" | sed -n 's/Boot\([0-9A-F]\{4\}\).*/\1/p')
      local boot_name
      boot_name=$(echo "$line" | sed -n 's/Boot[0-9A-F]\{4\}[*]*[ ]*\([^[:space:]]*\).*/\1/p' || echo "Unknown")
      local boot_path
      boot_path=$(echo "$line" | grep -o 'HD([^)]*)' || echo "Unknown")
      
      if [[ -n "$boot_num" ]]; then
        # Try to determine if this entry references our target drive
        # This is a best-effort approach since EFI paths can be complex
        local references_target="false"
        
        # Check if the EFI partition path matches our target
        if [[ "$boot_path" == *"$target_efi_partition"* ]] || [[ "$boot_path" == *"$(basename "$target_drive")"* ]]; then
          references_target="true"
        fi
        
        if [[ "$references_target" == "true" ]]; then
          target_drive_entries+=("$boot_num")
        else
          other_drive_entries+=("$boot_num")
          entry_details+=("Boot$boot_num: $boot_name ($boot_path)")
        fi
      fi
    fi
  done <<< "$kde_entries_info"
  
  # Remove entries that reference our target drive (old installations to the same drive)
  if [[ ${#target_drive_entries[@]} -gt 0 ]]; then
    log "INFO" "Found ${#target_drive_entries[@]} existing KDE entries on target drive $target_drive"
    local entry_id
    for entry_id in "${target_drive_entries[@]}"; do
      if [[ -n "$entry_id" ]]; then
        execute_cmd "efibootmgr -b $entry_id -B" "Removing previous KDE entry on target drive (Boot$entry_id)"
      fi
    done
  fi
  
  # Prompt user about entries on other drives
  if [[ ${#other_drive_entries[@]} -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}Found ${#other_drive_entries[@]} existing KDE boot entries on other drives:${NC}"
    echo ""
    local detail
    for detail in "${entry_details[@]}"; do
      echo "  $detail"
    done
    echo ""
    echo -e "${YELLOW}Important Notes:${NC}"
    echo "• These entries are NOT from the current installation (which targets $target_drive)"
    echo "• These may be legitimate KDE installations on other drives"
    echo "• It is YOUR responsibility to determine which entries are valid"
    echo "• The new KDE entry for this installation will be created separately"
    echo ""
    
    if [[ $dry_run == "false" ]]; then
      echo ""
      echo "To remove boot entries, enter list numbers separated by spaces (or 'none' to keep all):"
      local i
      for i in "${!entry_details[@]}"; do
        echo "  $((i+1)). ${entry_details[$i]}"
      done
      echo ""
      local selected_entries
      local boot_num
      read -p "Enter numbers to remove (e.g., 1 3): " -r selected_entries
      
      if [[ "$selected_entries" != "none" ]] && [[ -n "$selected_entries" ]]; then
          local list_num
          for list_num in $selected_entries; do
            # Validate list number and convert to array index
            if [[ "$list_num" =~ ^[0-9]+$ ]] && (( list_num >= 1 && list_num <= ${#entry_details[@]} )); then
              local array_index=$((list_num - 1))
              local boot_entry="${entry_details[$array_index]}"
              # Extract the boot number from the entry (Boot#### format)
              boot_num=$(echo "$boot_entry" | grep -o 'Boot[0-9A-Fa-f]\{4\}' | sed 's/Boot//')
              execute_cmd "efibootmgr -b $boot_num -B" "Removing selected KDE entry (Boot$boot_num)"
            else
              log "WARN" "Invalid selection: $list_num (must be 1-${#entry_details[@]})"
            fi
          done
        fi
    else
      echo "[DRY-RUN] Would prompt user about removing these entries"
    fi
  fi
  
  return 0
}

# Configure network settings based on user choice
configure_network_settings() {
  log "INFO" "Configuring network settings: $network_config"
  
  case "$network_config" in
    dhcp)
      configure_dhcp_network
      ;;
    static)
      configure_static_network
      ;;
    manual)
      configure_manual_network
      ;;
    *)
      log "WARN" "Unknown network configuration: $network_config, using DHCP"
      configure_dhcp_network
      ;;
  esac
}

# Configure DHCP network using systemd-networkd
configure_dhcp_network() {
  log "INFO" "Setting up DHCP network configuration"
  
  # Create a systemd-networkd configuration for DHCP
  local network_config_dir="$install_root/etc/systemd/network"
  execute_cmd "mkdir -p $network_config_dir" "Creating systemd-networkd config directory"
  
  # Create DHCP configuration for wired interfaces
  if [[ $dry_run == "true" ]]; then
    echo "[DRY-RUN] Would create DHCP network configuration in $network_config_dir/20-wired.network"
    [[ -n "$static_domain_search" ]] && echo "  Domain Search: $static_domain_search"
    [[ -n "$static_dns_suffix" ]] && echo "  DNS Suffix: $static_dns_suffix"
  else
    cat > "$network_config_dir/20-wired.network" << 'EOF'
[Match]
Name=en*
Name=eth*

[Network]
DHCP=yes
IPForward=no

[DHCP]
UseDNS=yes
UseNTP=yes
EOF

    # Add domain search entries if provided
    local domain
    if [[ -n "$static_domain_search" ]]; then
      for domain in $static_domain_search; do
        echo "Domains=$domain" >> "$network_config_dir/20-wired.network"
      done
    fi
    
    # Add DNS suffix entries if provided
    local suffix
    if [[ -n "$static_dns_suffix" ]]; then
      for suffix in $static_dns_suffix; do
        echo "Domains=$suffix" >> "$network_config_dir/20-wired.network"
      done
    fi

    log "INFO" "Created DHCP network configuration"
    [[ -n "$static_domain_search" ]] && log "INFO" "Added domain search: $static_domain_search"
    [[ -n "$static_dns_suffix" ]] && log "INFO" "Added DNS suffix: $static_dns_suffix"
  fi
  
  # Enable systemd-networkd
  execute_cmd "chroot $install_root systemctl enable systemd-networkd" "Enabling systemd-networkd"
  execute_cmd "chroot $install_root systemctl enable systemd-resolved" "Enabling systemd-resolved"
}

# Configure a static IP network using systemd-networkd
configure_static_network() {
  log "INFO" "Setting up static network configuration"
  
  if [[ -z "$static_iface" || -z "$static_ip" || -z "$static_netmask" || -z "$static_gateway" ]]; then
    log "ERROR" "Missing static network parameters - this should not happen after validation"
    return 1
  fi
  
  # Convert netmask to CIDR if needed
  local cidr_mask
  case "$static_netmask" in
    255.255.255.0) cidr_mask="24" ;;
    255.255.0.0) cidr_mask="16" ;;
    255.0.0.0) cidr_mask="8" ;;
    255.255.255.128) cidr_mask="25" ;;
    255.255.255.192) cidr_mask="26" ;;
    255.255.255.224) cidr_mask="27" ;;
    255.255.255.240) cidr_mask="28" ;;
    255.255.255.248) cidr_mask="29" ;;
    255.255.255.252) cidr_mask="30" ;;
    *) cidr_mask="24" ;; # Default to /24
  esac
  
  local network_config_dir="$install_root/etc/systemd/network"
  execute_cmd "mkdir -p $network_config_dir" "Creating systemd-networkd config directory"
  
  # Create static IP configuration
  if [[ $dry_run == "true" ]]; then
    echo "[DRY-RUN] Would create static network configuration:"
    echo "  Interface: $static_iface"
    echo "  IP: $static_ip/$cidr_mask"
    echo "  Gateway: $static_gateway"
    echo "  DNS: ${static_dns:-8.8.8.8,8.8.4.4}"
    [[ -n "$static_domain_search" ]] && echo "  Domain Search: $static_domain_search"
    [[ -n "$static_dns_suffix" ]] && echo "  DNS Suffix: $static_dns_suffix"
  else
    # Start building the network config
    cat > "$network_config_dir/20-static-$static_iface.network" << EOF
[Match]
Name=$static_iface

[Network]
Address=$static_ip/$cidr_mask
Gateway=$static_gateway
DNS=${static_dns:-8.8.8.8}
DNS=${static_dns##*,}
IPForward=no
EOF

    # Add domain search entries if provided
    local domain
    if [[ -n "$static_domain_search" ]]; then
      for domain in $static_domain_search; do
        echo "Domains=$domain" >> "$network_config_dir/20-static-$static_iface.network"
      done
    fi
    
    # Add DNS suffix entries if provided (using Domains= in systemd-networkd)
    local suffix
    if [[ -n "$static_dns_suffix" ]]; then
      for suffix in $static_dns_suffix; do
        echo "Domains=$suffix" >> "$network_config_dir/20-static-$static_iface.network"
      done
    fi
    
    log "INFO" "Created static network configuration for $static_iface: $static_ip/$cidr_mask"
    [[ -n "$static_domain_search" ]] && log "INFO" "Added domain search: $static_domain_search"
    [[ -n "$static_dns_suffix" ]] && log "INFO" "Added DNS suffix: $static_dns_suffix"
  fi
  
  # Enable systemd-networkd
  execute_cmd "chroot $install_root systemctl enable systemd-networkd" "Enabling systemd-networkd"
  execute_cmd "chroot $install_root systemctl enable systemd-resolved" "Enabling systemd-resolved"
}

# Configure manual network (leave for user to configure post-installation)
configure_manual_network() {
  log "INFO" "Manual network configuration selected - skipping automatic setup"
  
  # Create a placeholder file to indicate a manual configuration was chosen
  if [[ $dry_run == "true" ]]; then
    echo "[DRY-RUN] Would create manual network indicator file"
  else
    cat > "$install_root/etc/kde-neon-manual-network" << 'EOF'
# Manual network configuration was selected during installation
# Please configure your network settings manually after the first boot
# Common options:
#   - Use NetworkManager GUI (System Settings > Network)
#   - Configure systemd-networkd (/etc/systemd/network/)
#   - Use traditional networking (/etc/network/interfaces)
EOF
    log "INFO" "Created manual network configuration indicator"
  fi
}

# Interactive drive selection with Windows detection and safety checks
select_target_drive() {
  log "INFO" "Enumerating NVMe drives..."
  local drives
  mapfile -t drives < <(enumerate_nvme_drives)

  if [[ ${#drives[@]} -eq 0 ]]; then
    error_exit "No suitable NVMe drives found"
  fi

  # Check for global Windows EFI entries first
  local windows_efi_detected=false
  if detect_windows_efi; then
    windows_efi_detected=true
  fi

  # Windows detection on all drives for safety
  local windows_detected=false
  local windows_drives=()
  local safe_drives=()
  local drive
  for drive in "${drives[@]}"; do
    if detect_windows "$drive"; then
      windows_detected=true
      windows_drives+=("$drive")
    else
      safe_drives+=("$drive")
    fi
  done

  # Handle Windows drives based on flags
  if [[ $windows_detected == "true"   ]]; then
    if [[ $show_win == "true"   ]]; then
      echo -e "\n${YELLOW}Windows Detection Results:${NC}"
      echo "Windows installations found on: ${windows_drives[*]}"
      echo "All drives shown below (--show-win enabled)"
      echo
      log "WARN" "Windows installation detected on drives: ${windows_drives[*]} - included in selection (--show-win enabled)"
      # Keep all drives including Windows ones
      drives=("${drives[@]}")
    else
      # Exclude Windows drives and inform user
      if [[ ${#safe_drives[@]} -eq 0 ]]; then
        if [[ $force_mode == "true"   ]]; then
          echo -e "\n${YELLOW}Windows Detection Results:${NC}"
          echo "All drives contain Windows installations: ${windows_drives[*]}"
          echo "Force mode enabled - showing all drives"
          echo
          log "WARN" "Force mode enabled - using all drives despite Windows detection"
          drives=("${drives[@]}")
        else
          error_exit "No safe drives available. All drives contain Windows installations. Use --show-win or --force to override."
        fi
      else
        echo -e "\n${YELLOW}Windows Detection Results:${NC}"
        echo "Windows installations found on: ${windows_drives[*]}"
        echo "Safe drives available: ${safe_drives[*]}"
        echo "Only safe drives shown below (use --show-win to include Windows drives)"
        echo
        # Update a drive array to only safe drives
        drives=("${safe_drives[@]}")
      fi
    fi
  fi

  # EFI warning only if showing Windows drives or force mode
  if [[ $windows_efi_detected == "true" && $show_win == "true" && $force_mode == "false"     ]]; then
    echo -e "\n${YELLOW}Windows Boot Manager detected in system EFI${NC}"
    echo "Your computer has Windows installed somewhere."
    echo "Windows drives are included in the selection below because you used --show-win."
    echo "Selecting a Windows drive will permanently destroy Windows and all its data."
    echo "Please verify your drive selection carefully."
    echo
    if [[ $dry_run == "false"   ]]; then
      read -r -p "Continue with installation? (y/N): " confirm
      if [[ ! $confirm =~ ^[Yy]$   ]]; then
        error_exit "Installation cancelled by user"
      fi
    else
      echo "[DRY-RUN] Would prompt: Continue with installation? (y/N)"
    fi
  fi

  # Drive selection
  if [[ ${#drives[@]} -eq 1 ]]; then
    target_drive="${drives[0]}"
    echo -e "\n${GREEN}Single drive available for installation: $target_drive${NC}"
    echo -e "${RED}This drive will be completely erased and all data will be permanently lost.${NC}"
    echo "All other drives in your computer will be left untouched."
    log "INFO" "Single drive detected: $target_drive"
  else
    echo -e "\n${GREEN}Multiple drives available for KDE Neon installation:${NC}"
    echo "Select the drive to install KDE Neon on."
    echo -e "${RED}WARNING: The selected drive will be completely erased and all data will be lost.${NC}"
    echo "Drives not selected will be left completely untouched."
    echo
    log "INFO" "Multiple drives detected:"
    local i
    for i in "${!drives[@]}"; do
      local drive="${drives[$i]}"
      local size
      local size_gb
      local model
      local windows_flag=""
      size=$(lsblk -b -d -o SIZE "$drive" 2> /dev/null | tail -n1)
      size_gb=$((size / 1024 / 1024 / 1024))
      model=$(lsblk -d -o MODEL "$drive" 2> /dev/null | tail -n1)

      # Add Windows indicator for any Windows drives in the list
      local windows_drive
      for windows_drive in "${windows_drives[@]}"; do
        if [[ $drive == "$windows_drive"   ]]; then
          windows_flag=" ${RED}(Contains Windows)${NC}"
          break
        fi
      done

      echo "  $((i + 1)). $drive - ${size_gb}GB - $model$windows_flag"
    done

    echo
    if [[ $dry_run == "true"   ]]; then
      target_drive="${drives[0]}"
      echo "[DRY-RUN] Auto-selecting first drive for installation: $target_drive"
    else
      local selection
      read -r -p "Select drive for installation (1-${#drives[@]}): " selection
      if [[ $selection =~ ^[0-9]+$   ]] && [[ $selection -ge 1   ]] && [[ $selection -le ${#drives[@]}   ]]; then
        target_drive="${drives[$((selection - 1))]}"
      else
        error_exit "Invalid selection"
      fi
    fi
  fi

  log "INFO" "Target drive selected: $target_drive"
}

# Load configuration from a file if it exists
load_configuration() {
  local config_file="${custom_config:-$default_config_file}"
  local error

  if [[ -f $config_file   ]]; then
    echo "Loading saved settings from: $(basename "$config_file")"
    log "INFO" "Loading configuration from: $config_file"
    
    # Validate configuration file syntax before sourcing
    if ! bash -n "$config_file" 2>/dev/null; then
      echo -e "${RED}✗ Configuration file is corrupted (syntax error)${NC}"
      log "ERROR" "Configuration file has syntax errors: $config_file"
      
      if [[ $dry_run == "false" ]]; then
        local choice
        read -r -p "Delete corrupted configuration and start fresh? (y/N): " choice
        if [[ "${choice,,}" =~ ^[Yy]$ ]]; then
          rm -f "$config_file"
          echo "Corrupted configuration deleted."
          log "INFO" "Deleted corrupted configuration file: $config_file"
          return 1
        else
          echo "Keeping corrupted file. Installation cannot continue with invalid configuration."
          log "ERROR" "User chose to keep corrupted configuration file"
          return 1
        fi
      else
        echo "[DRY-RUN] Would offer to delete corrupted configuration file"
        return 1
      fi
    fi
    
    # shellcheck source=/dev/null
    source "$config_file"
    
    # Comprehensive validation of configuration content
    local validation_errors=()
    
    # Check file integrity and basic structure
    if [[ $(wc -l < "$config_file") -lt 5 ]]; then
      validation_errors+=("File too small - appears truncated or empty")
    fi
    
    # Validate required variables are present and not empty
    [[ -z "$network_config" ]] && validation_errors+=("Missing required variable: network_config")
    [[ -z "$locale" ]] && validation_errors+=("Missing required variable: locale")
    [[ -z "$timezone" ]] && validation_errors+=("Missing required variable: timezone")
    [[ -z "$username" ]] && validation_errors+=("Missing required variable: username")
    [[ -z "$hostname" ]] && validation_errors+=("Missing required variable: hostname")
    
    
    # Validate network configuration
    if [[ -n "$network_config" && ! "$network_config" =~ ^(dhcp|static|manual)$ ]]; then
      validation_errors+=("Invalid network_config: $network_config (must be dhcp, static, or manual)")
    fi
    
    # Validate static network settings if network_config is static
    if [[ "$network_config" == "static" ]]; then
      [[ -z "$static_iface" ]] && validation_errors+=("Static network missing: static_iface")
      [[ -z "$static_ip" ]] && validation_errors+=("Static network missing: static_ip")
      [[ -z "$static_netmask" ]] && validation_errors+=("Static network missing: static_netmask")
      [[ -z "$static_gateway" ]] && validation_errors+=("Static network missing: static_gateway")
      
      # Validate IP address format
      if [[ -n "$static_ip" && ! "$static_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        validation_errors+=("Invalid static_ip format: $static_ip")
      fi
      
      # Validate netmask format
      if [[ -n "$static_netmask" && ! "$static_netmask" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        validation_errors+=("Invalid static_netmask format: $static_netmask")
      fi
      
      # Validate gateway format
      if [[ -n "$static_gateway" && ! "$static_gateway" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        validation_errors+=("Invalid static_gateway format: $static_gateway")
      fi
    fi
    
    # Validate locale format
    if [[ -n "$locale" && ! "$locale" =~ ^[a-z]{2}_[A-Z]{2}\.(UTF-8|utf8)$ ]]; then
      validation_errors+=("Invalid locale format: $locale (expected format: en_US.UTF-8)")
    fi
    
    # Validate timezone format
    if [[ -n "$timezone" && ! "$timezone" =~ ^[A-Za-z_]+/[A-Za-z_]+$ ]]; then
      validation_errors+=("Invalid timezone format: $timezone (expected format: America/New_York)")
    fi
    
    # Validate keyboard layout
    if [[ -n "$keyboard_layout" && ! "$keyboard_layout" =~ ^[a-z]{2,3}$ ]]; then
      validation_errors+=("Invalid keyboard_layout: $keyboard_layout (expected 2-3 letter code)")
    fi
    
    # Validate username format
    if [[ -n "$username" && ! "$username" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]; then
      validation_errors+=("Invalid username: $username (must start with letter, lowercase, max 32 chars)")
    fi
    
    # Validate sudo_nopasswd format
    if [[ -n "$sudo_nopasswd" && ! "$sudo_nopasswd" =~ ^[YyNn]$ ]]; then
      validation_errors+=("Invalid sudo_nopasswd: $sudo_nopasswd (must be y, Y, n, or N)")
    fi
    
    # Validate hostname format
    if [[ -n "$hostname" && ! "$hostname" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}[a-zA-Z0-9]?$ ]]; then
      validation_errors+=("Invalid hostname: $hostname (invalid format)")
    fi
    
    # Validate swap size format
    if [[ -n "$swap_size" && ! "$swap_size" =~ ^[0-9]+[GMK]?$ ]]; then
      validation_errors+=("Invalid swap_size: $swap_size (expected format: 4G, 512M, etc.)")
    fi
    
    # Validate root filesystem
    if [[ -n "$root_fs" && ! "$root_fs" =~ ^(ext4|ext3|xfs|btrfs)$ ]]; then
      validation_errors+=("Invalid root_fs: $root_fs (must be ext4, ext3, xfs, or btrfs)")
    fi
    
    # Check for conflicting settings
    if [[ "$network_config" == "manual" && (-n "$static_ip" || -n "$static_gateway") ]]; then
      validation_errors+=("Conflicting settings: manual network with static IP configuration")
    fi
    
    # If validation errors found, handle them
    if [[ ${#validation_errors[@]} -gt 0 ]]; then
      echo -e "${RED}✗ Configuration file has validation errors${NC}"
      for error in "${validation_errors[@]}"; do
        log "ERROR" "Config validation: $error"
      done
      
      if [[ $dry_run == "false" ]]; then
        local choice
        read -r -p "Delete corrupted configuration and start fresh? (y/N): " choice
        if [[ "${choice,,}" =~ ^[Yy]$ ]]; then
          rm -f "$config_file"
          echo "Corrupted configuration deleted."
          log "INFO" "Deleted invalid configuration file: $config_file"
          return 1
        else
          echo "Keeping invalid file. Will prompt for all settings to correct issues."
          log "WARN" "User chose to keep invalid configuration file"
          return 1
        fi
      else
        echo "[DRY-RUN] Would offer to delete invalid configuration file"
        return 1
      fi
    fi
    
    echo -e "${GREEN}✓ Configuration loaded${NC}"
    
    # Show current settings to the user
    echo
    echo -e "${YELLOW}Current Settings:${NC}"
    echo "  Locale: ${locale:-en_US.UTF-8}"
    echo "  Timezone: ${timezone:-$(detect_timezone)}"
    echo "  Keyboard Layout: ${keyboard_layout:-us}"
    echo "  User Full Name: ${user_fullname:-KDE User}"
    echo "  Username: ${username:-user}"
    echo "  Passwordless Sudo: ${sudo_nopasswd:-n}"
    echo "  Hostname: ${hostname:-kde-neon}"
    echo "  Swap Size: ${swap_size:-4G}"
    echo "  Root Filesystem: ${root_fs:-ext4}"
    echo "  Network Config: ${network_config:-dhcp}"
    [[ -n "$static_domain_search" ]] && echo "  Domain Search: $static_domain_search"
    [[ -n "$static_dns_suffix" ]] && echo "  DNS Suffix: $static_dns_suffix"
    echo
    
    if [[ $dry_run == "false" ]]; then
      local choice
      read -r -p "Use these settings? (y/N/edit): " choice
      case "${choice,,}" in
        y|yes)
          echo "Using saved settings"
          return 0
          ;;
        e|edit)
          echo "Interactive configuration editing:"
          prompt_for_settings
          return 0
          ;;
        *)
          echo "Starting fresh configuration"
          clear_configuration
          prompt_for_settings
          return 0
          ;;
      esac
    else
      echo "[DRY-RUN] Would prompt: Use these settings? (y/N/edit)"
      return 0
    fi
  else
    echo "No saved configuration found - will prompt for settings"
    log "INFO" "No existing configuration found, will prompt for settings"
    if [[ $dry_run == "false" ]]; then
      prompt_for_settings
    fi
    return 1
  fi
}

# Clear all configuration variables
clear_configuration() {
  unset locale timezone keyboard_layout user_fullname username hostname swap_size root_fs network_config
  unset user_password sudo_nopasswd
}

# Auto-detect timezone using GeoIP (like original Calamares)
detect_timezone_geoip() {
  local detected_tz=""

  # Try ipinfo.io first (HTTPS, secure)
  if command -v curl >/dev/null 2>&1; then
    detected_tz=$(curl -s --connect-timeout 5 --max-time 10 "https://ipinfo.io/json" 2>/dev/null | \
      grep -o '"timezone":"[^"]*"' | cut -d'"' -f4)
  fi

  # Fallback to ip-api.com if the first attempt failed (HTTP only - free tier doesn't support HTTPS)
  if [[ -z "$detected_tz" ]] && command -v curl >/dev/null 2>&1; then
    detected_tz=$(curl -s --connect-timeout 5 --max-time 10 "http://ip-api.com/json" 2>/dev/null | \
      grep -o '"timezone":"[^"]*"' | cut -d'"' -f4)
  fi

  # If GeoIP failed, fall back to system detection
  if [[ -z "$detected_tz" ]]; then
    detected_tz=$(detect_timezone_system)
  fi

  echo "$detected_tz"
}

# Auto-detect system timezone from local files
detect_timezone_system() {
  local detected_tz
  if [[ -f /etc/timezone ]]; then
    detected_tz=$(cat /etc/timezone)
  elif [[ -L /etc/localtime ]]; then
    detected_tz=$(readlink /etc/localtime | sed 's|/usr/share/zoneinfo/||')
  else
    detected_tz="UTC"
  fi
  echo "$detected_tz"
}

# Main timezone detection (uses GeoIP like Calamares)
detect_timezone() {
  detect_timezone_geoip
}

# Map country codes to common locales
get_locale_for_country() {
  local country_code="$1"
  case "$country_code" in
    BR) echo "pt_BR.UTF-8" ;;
    RO) echo "ro_RO.UTF-8" ;;
    HU) echo "hu_HU.UTF-8" ;;
    DE) echo "de_DE.UTF-8" ;;
    FR) echo "fr_FR.UTF-8" ;;
    ES) echo "es_ES.UTF-8" ;;
    IT) echo "it_IT.UTF-8" ;;
    JP) echo "ja_JP.UTF-8" ;;
    CN) echo "zh_CN.UTF-8" ;;
    RU) echo "ru_RU.UTF-8" ;;
    KR) echo "ko_KR.UTF-8" ;;
    *) echo "en_US.UTF-8" ;;  # Default to US English
  esac
}

# Auto-detect locale using GeoIP + system detection
detect_locale() {
  local detected_locale=""

  # First, try system locale (the highest priority if set)
  if [[ -n "$LANG" && "$LANG" != "C" && "$LANG" != "POSIX" ]]; then
    detected_locale="$LANG"
  elif [[ -f /etc/default/locale ]]; then
    local system_locale
    system_locale=$(grep "^LANG=" /etc/default/locale | cut -d= -f2 | tr -d '"')
    if [[ -n "$system_locale" && "$system_locale" != "C" && "$system_locale" != "POSIX" ]]; then
      detected_locale="$system_locale"
    fi
  fi

  # If no useful system locale, try GeoIP-based suggestion
  if [[ -z "$detected_locale" || "$detected_locale" == "C.UTF-8" ]]; then
    if command -v curl >/dev/null 2>&1; then
      local country_code

      # Try ipinfo.io first (HTTPS, secure)
      country_code=$(curl -s --connect-timeout 5 --max-time 10 "https://ipinfo.io/json" 2>/dev/null | \
        grep -o '"country":"[^"]*"' | cut -d'"' -f4)

      # Fallback to ip-api.com if the first attempt failed (HTTP only - free tier doesn't support HTTPS)
      if [[ -z "$country_code" ]]; then
        country_code=$(curl -s --connect-timeout 5 --max-time 10 "http://ip-api.com/json" 2>/dev/null | \
          grep -o '"countryCode":"[^"]*"' | cut -d'"' -f4)
      fi

      if [[ -n "$country_code" ]]; then
        detected_locale=$(get_locale_for_country "$country_code")
      fi
    fi
  fi

  # Final fallback
  if [[ -z "$detected_locale" ]]; then
    detected_locale="en_US.UTF-8"
  fi

  echo "$detected_locale"
}

# Calculate optimal swap size based on available RAM
calculate_optimal_swap() {
  local ram_gb
  ram_gb=$(free -g | awk '/^Mem:/ {print $2}')

  # Handle case where RAM is less than 1GB (shows as 0 in -g)
  if [[ $ram_gb -eq 0 ]]; then
    ram_gb=1
  fi

  # Modern best practices for swap sizing
  if [[ $ram_gb -le 2 ]]; then
    # Low RAM systems: 2x RAM for stability
    echo "$((ram_gb * 2))G"
  elif [[ $ram_gb -le 8 ]]; then
    # Medium RAM systems: equal to RAM
    echo "${ram_gb}G"
  elif [[ $ram_gb -le 32 ]]; then
    # High RAM systems: 4-8GB is enough
    echo "8G"
  else
    # Very high RAM systems: minimal swap needed
    echo "4G"
  fi
}

# Interactive prompts for configuration settings
prompt_for_settings() {
  ui_section "Configuration Setup"

  # Auto-detect system settings for defaults
  local detected_locale detected_timezone
  detected_locale=$(detect_locale)
  detected_timezone=$(detect_timezone)

  # Show current detected values
  ui_field "Detected Locale" "$detected_locale"
  ui_field "Detected Timezone" "$detected_timezone"
  echo

  # Prompt for all settings with loaded config or auto-detected defaults
  local default_locale="${locale:-$detected_locale}"
  local default_timezone="${timezone:-$detected_timezone}"
  local default_keyboard="${keyboard_layout:-us}"
  local default_fullname="${user_fullname:-KDE User}"
  local default_username="${username:-user}"

  # System Settings
  ui_section "System Settings"
  locale=$(ui_input "Locale" "$default_locale")
  timezone=$(ui_input "Timezone" "$default_timezone")
  keyboard_layout=$(ui_input "Keyboard layout" "$default_keyboard")

  # User Account
  ui_section "User Account"
  user_fullname=$(ui_input "Full name" "$default_fullname")
  username=$(ui_input "Username" "$default_username")
  sudo_nopasswd=$(ui_input "Add to passwordless sudo?" "n" "confirm")

  # System Configuration
  ui_section "System Configuration"
  local default_hostname="${hostname:-kde-neon}"
  hostname=$(ui_input "Hostname" "$default_hostname")
  
  local optimal_swap
  optimal_swap=$(calculate_optimal_swap)
  local default_swap="${swap_size:-$optimal_swap}"
  swap_size=$(ui_input "Swap file size" "$default_swap")
  
  local default_fs="${root_fs:-ext4}"
  root_fs=$(ui_input "Root filesystem" "$default_fs")

  # Network Configuration
  ui_section "Network Configuration"
  ui_status "info" "dhcp - Automatic IP configuration (recommended)"
  ui_status "info" "static - Manual IP configuration"
  ui_status "info" "manual - Manual network setup after installation"
  echo
  
  local default_network="${network_config:-dhcp}"
  network_config=$(ui_input "Network configuration" "$default_network" "choice" "dhcp,static,manual")

  # Collect additional settings for static configuration
  if [[ "$network_config" == "static" ]]; then
    # Detect the currently active interface
    local current_iface
    current_iface=$(ip route | grep default | head -n1 | awk '{print $5}' 2>/dev/null || echo "")

    ui_section "Static IP Configuration"
    
    while true; do
      local default_iface="${static_iface:-$current_iface}"
      local default_ip="${static_ip:-192.168.1.100}"
      local default_netmask="${static_netmask:-255.255.255.0}"
      local default_gateway="${static_gateway:-192.168.1.1}"
      local default_dns="${static_dns:-8.8.8.8,8.8.4.4}"

      if [[ -n "$default_iface" ]]; then
        static_iface=$(ui_input "Network interface" "$default_iface")
      else
        static_iface=$(ui_input "Network interface (e.g., enp0s3, eth0)" "")
      fi
      static_ip=$(ui_input "IP address" "$default_ip")
      static_netmask=$(ui_input "Subnet mask" "$default_netmask")
      static_gateway=$(ui_input "Gateway" "$default_gateway")
      static_dns=$(ui_input "DNS servers" "$default_dns")

      # Basic validation
      if [[ -z "$static_iface" || -z "$static_ip" || -z "$static_netmask" || -z "$static_gateway" ]]; then
        ui_status "error" "Interface, IP address, netmask, and gateway are required"
        ui_status "info" "Please provide all required fields"
        echo
      else
        break
      fi
    done
  fi

  # Collect DNS settings for both DHCP and static (but not manual)
  if [[ "$network_config" != "manual" ]]; then
    ui_section "DNS Configuration"
    local default_dns_suffix="${static_dns_suffix:-}"

    if [[ -n "$default_dns_suffix" ]]; then
      static_dns_suffix=$(ui_input "DNS suffix" "$default_dns_suffix")
    else
      static_dns_suffix=$(ui_input "DNS suffix (optional, space-separated)" "")
    fi

    # Use suffix as fallback default for search if no saved search domain
    local default_domain_search="${static_domain_search:-$static_dns_suffix}"

    if [[ -n "$default_domain_search" ]]; then
      static_domain_search=$(ui_input "Domain search" "$default_domain_search")
    else
      static_domain_search=$(ui_input "Domain search (optional, space-separated)" "")
    fi
  fi

  echo
  ui_status "success" "Configuration complete"

  # Save configuration for future runs
  save_configuration
}

# Save the current installation configuration to file
save_configuration() {
  local config_file="${custom_config:-$default_config_file}"

  log "INFO" "Saving configuration to: $config_file"

  cat > "$config_file" << EOF
# KDE Neon Installation Configuration
# Generated: $(date)

# System settings
locale="${locale:-en_US.UTF-8}"
timezone="${timezone:-$(detect_timezone)}"
keyboard_layout="${keyboard_layout:-us}"

# User settings
user_fullname="${user_fullname:-KDE User}"
username="${username:-user}"
# Password is not stored in config for security - always prompt fresh
hostname="${hostname:-kde-neon}"
sudo_nopasswd="${sudo_nopasswd:-n}"

# Storage settings with dynamic swap sizing
swap_size="${swap_size:-$(calculate_optimal_swap)}"
root_fs="${root_fs:-ext4}"

# Network settings
network_config="${network_config:-dhcp}"
static_iface="${static_iface:-}"
static_ip="${static_ip:-}"
static_netmask="${static_netmask:-}"
static_gateway="${static_gateway:-}"
static_dns="${static_dns:-}"
static_domain_search="${static_domain_search:-}"
static_dns_suffix="${static_dns_suffix:-}"
EOF

  if [[ $dry_run == "false"   ]]; then
    chmod 600 "$config_file"
  fi
}

# Execute addon scripts from the./addons directory
execute_addon_scripts() {
  local addon_dir="./addons"
  local script_count=0
  local addon_scripts=()
  
  # Check if the addons directory exists
  if [[ ! -d "$addon_dir" ]]; then
    return 0  # No addons directory, nothing to do
  fi
  
  # Find all .sh files in the addons directory
  local script
  while IFS= read -r -d '' script; do
    addon_scripts+=("$script")
    ((script_count++))
  done < <(find "$addon_dir" -name "*.sh" -type f -print0 2>/dev/null)
  
  # If no .sh files found, return
  if [[ $script_count -eq 0 ]]; then
    log "INFO" "No addon scripts found in $addon_dir"
    return 0
  fi
  
  # Sort scripts numerically by filename
  mapfile -t addon_scripts < <(printf '%s\n' "${addon_scripts[@]}" | sort -V)

  echo
  dry_echo "=== Executing Addon Scripts ($script_count found) ==="
  
  # Execute each script in order
  for script in "${addon_scripts[@]}"; do
    local script_name
    script_name=$(basename "$script")
    
    # Make script executable
    execute_cmd "chmod +x '$script'" "Making addon script executable: $script_name"
    
    # Execute the script with the installation root as the first argument
    log "INFO" "Executing addon script: $script_name"
    if [[ $dry_run == "true" ]]; then
      echo "[DRY-RUN] Would execute addon script: $script with install_root=$install_root"
    else
      echo "  Executing addon script: $script_name..."
      if ! bash "$script" "$install_root" >> "$log_file" 2>&1; then
        log "ERROR" "Addon script failed: $script_name"
        log "WARN" "Continuing with installation despite addon script failure"
      else
        log "INFO" "Addon script completed successfully: $script_name"
      fi
    fi
  done
  
  log "INFO" "Addon script execution completed"
}

# Phase 1: System preparation, validation, and package installation
phase1_system_preparation() {
  echo
  dry_echo "=== Phase 1: Preparing system and installing required tools ==="

  check_uefi
  check_network

  # Update package database
  execute_cmd "apt-get -qq update" "Updating package database"

  # Install required packages
  execute_cmd "apt-get -qq install -y parted gdisk dosfstools e2fsprogs" "Installing partitioning tools"

  log "INFO" "Phase 1 completed successfully"
}

# Phase 2: Create GPT partitions and format filesystems
phase2_partitioning() {
  echo
  dry_echo "=== Phase 2: Creating partitions on $target_drive ==="

  local drive="$target_drive"

  # Unmount any existing partitions
  execute_cmd "umount ${drive}p* 2>/dev/null || true"

  # Create a new GPT partition table
  execute_cmd "parted -s $drive mklabel gpt" "Creating GPT partition table"

  # Create an EFI system partition (512MB)
  execute_cmd "parted -s $drive mkpart primary fat32 1MiB 513MiB" "Creating EFI system partition"
  execute_cmd "parted -s $drive set 1 esp on" "Setting EFI system partition flag"

  # Create a root partition (remaining space)
  execute_cmd "parted -s $drive mkpart primary ext4 513MiB 100%" "Creating root partition"

  # Wait for the kernel to recognize partitions
  execute_cmd "partprobe $drive" "Refreshing partition table"
  execute_cmd "sleep 2" "Waiting for partition recognition"

  # Format EFI partition
  execute_cmd "mkfs.fat -F32 -n EFI ${drive}p1" "Formatting EFI partition"

  # Format root partition
  execute_cmd "mkfs.ext4 -F -L KDE-Neon ${drive}p2" "Formatting root partition"

  log "INFO" "Phase 2 completed successfully"
}

# Phase 3: Mount filesystems, copy system files, and create a swap
phase3_system_installation() {
  local device
  echo
  dry_echo "=== Phase 3: Installing KDE Neon system files ==="

  local drive="$target_drive"
  local root_part="${drive}p2"
  local efi_part="${drive}p1"

  # Create mount points
  execute_cmd "mkdir -p $install_root" "Creating installation root"

  # Mount root partition first
  execute_cmd "mount $root_part $install_root" "Mounting root partition"

  # Create EFI mount point after root is mounted
  execute_cmd "mkdir -p $install_root/boot/efi" "Creating EFI mount point"
  execute_cmd "mount $efi_part $install_root/boot/efi" "Mounting EFI partition"

  # Find and mount an installation source (live filesystem)
  execute_cmd "mkdir -p /mnt/squashfs" "Creating squashfs mount point"

  # Try to find the squashfs filesystem directly from a live system
  local squashfs_path=""
  if [[ -f "/run/live/medium/casper/filesystem.squashfs" ]]; then
    squashfs_path="/run/live/medium/casper/filesystem.squashfs"
  elif [[ -f "/lib/live/mount/medium/casper/filesystem.squashfs" ]]; then
    squashfs_path="/lib/live/mount/medium/casper/filesystem.squashfs"
  elif [[ -f "/cdrom/casper/filesystem.squashfs" ]]; then
    squashfs_path="/cdrom/casper/filesystem.squashfs"
  else
    # Try to find USB drive with casper directory
    for device in /dev/sd* /dev/nvme*; do
      if [[ -b "$device" ]]; then
        execute_cmd "mkdir -p /mnt/source" "Creating source mount point"
        if execute_cmd "mount -o ro $device /mnt/source 2>/dev/null || true" "Trying to mount $device"; then
          if [[ -f "/mnt/source/casper/filesystem.squashfs" ]]; then
            squashfs_path="/mnt/source/casper/filesystem.squashfs"
            break
          fi
          execute_cmd "umount /mnt/source 2>/dev/null || true"
        fi
      fi
    done
  fi

  if [[ -z "$squashfs_path" ]]; then
    error_exit "Could not find KDE Neon installation filesystem. Please ensure you're running from the KDE Neon live USB."
  fi

  execute_cmd "mount -o loop $squashfs_path /mnt/squashfs" "Mounting squashfs filesystem from $squashfs_path"

  # Copy system files from squashfs (this will take several minutes)
  log "INFO" "Extracting system files from squashfs (this will take several minutes)..."
  if [[ $dry_run == "true" ]]; then
    echo "[DRY-RUN] Would extract squashfs system files with rsync"
else
    # Run rsync quietly and log the summary
    local rsync_start_time
    local rsync_end_time
    local rsync_duration

    rsync_start_time=$(date +%s)
    rsync -a --quiet \
      --exclude='/proc' --exclude='/sys' \
      --exclude='/dev' --exclude='/run' --exclude='/tmp' --exclude='/mnt' \
      --exclude='/lost+found' --exclude='/media' --exclude='/cdrom' \
      /mnt/squashfs/ "$install_root/" && {
      rsync_end_time=$(date +%s)
      rsync_duration=$((rsync_end_time - rsync_start_time))
      log "INFO" "System file extraction completed in ${rsync_duration}s"
  }
fi
  # Create essential directories
  local dir
  for dir in proc sys dev run tmp; do
    execute_cmd "mkdir -p $install_root/$dir" "Creating /$dir directory"
  done

  # Create a swap file
  local swap_file_size="${swap_size:-4G}"
  execute_cmd "fallocate -l $swap_file_size $install_root/swapfile" "Creating swap file"
  execute_cmd "chmod 600 $install_root/swapfile" "Setting swap file permissions"
  execute_cmd "mkswap $install_root/swapfile" "Formatting swap file"

  # Copy kernel files from the casper directory (not included in squashfs)
  local kernel_source=""
  if [[ -f "/run/live/medium/casper/vmlinuz" ]]; then
    kernel_source="/run/live/medium/casper"
  elif [[ -f "/lib/live/mount/medium/casper/vmlinuz" ]]; then
    kernel_source="/lib/live/mount/medium/casper"
  elif [[ -f "/cdrom/casper/vmlinuz" ]]; then
    kernel_source="/cdrom/casper"
  elif [[ -f "/mnt/source/casper/vmlinuz" ]]; then
    kernel_source="/mnt/source/casper"
  fi

  if [[ -n "$kernel_source" ]]; then
    # Find the actual kernel version from the installed system
    local kernel_version
    if [[ $dry_run == "true" ]]; then
      kernel_version="6.5.0-generic"  # Mock kernel version for dry-run
      echo "[DRY-RUN] Would determine kernel version from $install_root/lib/modules/"
    else
      kernel_version=$(find "$install_root/lib/modules/" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | head -n1)
    fi
    if [[ -n "$kernel_version" ]]; then
      execute_cmd "cp '$kernel_source/vmlinuz' '$install_root/boot/vmlinuz-$kernel_version'" "Copying kernel image"
      execute_cmd "cp '$kernel_source/initrd' '$install_root/boot/initrd.img-$kernel_version'" "Copying initial ramdisk"
      log "INFO" "Kernel files copied for version: $kernel_version"
    else
      log "WARN" "Could not determine kernel version, copying with generic names"
      execute_cmd "cp '$kernel_source/vmlinuz' '$install_root/boot/vmlinuz'" "Copying kernel image"
      execute_cmd "cp '$kernel_source/initrd' '$install_root/boot/initrd.img'" "Copying initial ramdisk"
    fi
  else
    log "WARN" "Could not find kernel files in casper directory"
  fi

  # Unmount installation source
  execute_cmd "umount /mnt/squashfs 2>/dev/null || true"
  execute_cmd "umount /mnt/source 2>/dev/null || true"

  log "INFO" "Phase 3 completed successfully"
}

# Phase 4: Install GRUB bootloader and configure fstab
phase4_bootloader_configuration() {
  echo
  dry_echo "=== Phase 4: Installing and configuring GRUB bootloader ==="

  local drive="$target_drive"

  # Mount essential filesystems in chroot
  execute_cmd "mount --bind /proc $install_root/proc" "Binding /proc"
  execute_cmd "mount --bind /sys $install_root/sys" "Binding /sys"
  execute_cmd "mount --bind /dev $install_root/dev" "Binding /dev"
  execute_cmd "mount --bind /dev/pts $install_root/dev/pts" "Binding /dev/pts"
  execute_cmd "mount --bind /run $install_root/run" "Binding /run"
  execute_cmd "mount -t tmpfs tmpfs $install_root/tmp" "Mounting tmpfs for /tmp"
  execute_cmd "chmod 1777 $install_root/tmp" "Setting proper permissions on /tmp"
  execute_cmd "mount --bind /sys/firmware/efi/efivars $install_root/sys/firmware/efi/efivars" "Binding EFI variables"

  # Capture existing boot entries before GRUB installation
  # This allows us to exclude our newly created entry from a cleanup menu
  # Note: Boot entries captured for potential future cleanup functionality
  # pre_grub_entries=$(efibootmgr -v 2>/dev/null || true)

  # Install GRUB
  execute_cmd "chroot $install_root grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id='KDE Neon' $drive" "Installing GRUB bootloader"

  # Generate GRUB configuration
  execute_cmd "chroot $install_root update-grub" "Generating GRUB configuration"

  # Update initramfs after GRUB configuration
  execute_cmd "chroot $install_root update-initramfs -u -k all" "Updating initramfs for all kernels"

  # Clean up conflicting EFI boot entries to avoid boot menu confusion
  log "INFO" "Cleaning up EFI boot entries to avoid conflicts with GRUB"

  # Remove systemd-boot entries (Linux Boot Manager)
  if efibootmgr | grep -q "Linux Boot Manager"; then
    local systemd_boot_id
    systemd_boot_id=$(efibootmgr | grep "Linux Boot Manager" | sed 's/Boot\([0-9A-F]\{4\}\).*/\1/')
    if [[ -n "$systemd_boot_id" ]]; then
      execute_cmd "efibootmgr -b $systemd_boot_id -B" "Removing systemd-boot entry (Boot$systemd_boot_id)"
    fi
  fi

  # Check for existing KDE entries that don't reference our target drive
  check_existing_kde_entries "$target_drive"

  # Update fstab
  if [[ $dry_run == "true"   ]]; then
    echo "[DRY-RUN] Creating /etc/fstab with root and EFI partitions"
    echo "[DRY-RUN] Would write fstab entries for ${drive}p1 and ${drive}p2"
  else
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
  fi

  log "INFO" "Phase 4 completed successfully"
}

# Phase 5: Configure locale, hostname, and cleanup live packages
phase5_system_configuration() {
  echo
  dry_echo "=== Phase 5: Configuring system settings and cleanup ==="

  # Configure timezone
  local system_timezone="${timezone:-UTC}"
  execute_cmd "chroot $install_root ln -sf /usr/share/zoneinfo/$system_timezone /etc/localtime" "Setting timezone to $system_timezone"
  execute_cmd "echo '$system_timezone' > $install_root/etc/timezone" "Writing timezone configuration"
  
  # Set timezone to local time
  execute_cmd "chroot $install_root timedatectl set-local-rtc 1" "Setting system clock to local time"

  # Configure locale
  local system_locale="${locale:-en_US.UTF-8}"
  execute_cmd "chroot $install_root locale-gen $system_locale" "Generating locale"
  execute_cmd "chroot $install_root update-locale LANG=$system_locale" "Setting system locale"

  # Disable automatic language pack installation
  execute_cmd "echo 'APT::Install-Recommends \"false\";' > $install_root/etc/apt/apt.conf.d/90-no-recommends" "Disabling automatic language pack installation"

  # Set hostname
  local system_hostname="${hostname:-kde-neon}"
  execute_cmd "echo $system_hostname > $install_root/etc/hostname" "Setting hostname"

  # Configure network settings
  configure_network_settings

  # Create a user account
  local system_username="${username:-user}"
  local system_fullname="${user_fullname:-KDE User}"
  execute_cmd "chroot $install_root useradd -m -s /bin/bash -c '$system_fullname' $system_username" "Creating user account"

  if [[ -n "${user_password:-}" ]]; then
    execute_cmd "printf '%s:%s\n' '$system_username' '$user_password' | chroot $install_root chpasswd" "Setting user password"
  else
    # In dry-run mode, skip password prompting
    if [[ $dry_run == "true" ]]; then
      echo "[DRY-RUN] Would prompt for user password during installation"
      user_password="dummy_password_for_dry_run"
    else
      # Prompt for password if not set
      log "INFO" "Prompting for user password during installation"
      while true; do
        local user_password_confirm
        read -r -s -p "  Password for $system_username: " user_password
        echo
        read -r -s -p "  Confirm password: " user_password_confirm
        echo
        if [[ "$user_password" == "$user_password_confirm" ]]; then
          if [[ ${#user_password} -ge 6 ]]; then
            break
          else
            echo "Password must be at least 6 characters long."
          fi
        else
          echo "Passwords do not match. Please try again."
        fi
      done
    fi
    execute_cmd "printf '%s:%s\n' '$system_username' '$user_password' | chroot $install_root chpasswd" "Setting user password"
  fi

  execute_cmd "chroot $install_root usermod -aG sudo $system_username" "Adding user to sudo group"

  # Create a no-password sudoers file if requested
  if [[ "${sudo_nopasswd:-n}" =~ ^[Yy]$ ]]; then
    execute_cmd "echo '$system_username ALL=(ALL) NOPASSWD:ALL' | tee $install_root/etc/sudoers.d/$system_username >/dev/null" "Configuring passwordless sudo"
    execute_cmd "chmod 440 $install_root/etc/sudoers.d/$system_username" "Setting sudoers file permissions"
  fi

  # Remove live system packages
  execute_cmd "chroot $install_root apt-get -qq -y purge calamares neon-live casper '^live-*' >/dev/null 2>&1" "Purging live system packages"
  execute_cmd "chroot $install_root apt-get -qq -y autoremove --purge >/dev/null 2>&1" "Cleaning up orphaned packages"
  execute_cmd "chroot $install_root apt-get -qq -y autoclean >/dev/null 2>&1" "Cleaning package cache"

  # Execute addon scripts if available
  execute_addon_scripts

  # Initramfs was already updated in Phase 4 after GRUB configuration

  # Unmount chroot filesystems (reverse order of mounting)
  umount "$install_root/sys/firmware/efi/efivars" 2>/dev/null || true
  umount "$install_root/tmp" 2>/dev/null || true
  umount "$install_root/dev/pts" 2>/dev/null || true
  umount "$install_root/run" 2>/dev/null || true
  umount "$install_root/dev" 2>/dev/null || true
  umount "$install_root/sys" 2>/dev/null || true
  umount "$install_root/proc" 2>/dev/null || true
  umount "$install_root/boot/efi" 2>/dev/null || true
  umount "$install_root" 2>/dev/null || true

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

  # Display a completion message to the user
  echo
  echo -e "${GREEN}🎉 KDE Neon Installation Complete! 🎉${NC}"
  echo
  echo -e "${YELLOW}Installation Summary:${NC}"
  echo "  ✅ KDE Neon installed successfully on $target_drive"
  echo "  ✅ GRUB bootloader configured"
  echo "  ✅ System ready for first boot"
  echo
  echo -e "${YELLOW}Next Steps:${NC}"
  echo "  1. Remove the installation USB drive"
  echo "  2. Restart your computer"
  echo "  3. Your computer should boot into KDE Neon"
  echo "  4. Complete the initial user setup"
  echo
  echo -e "${YELLOW}Important Notes:${NC}"
  echo "  • The installation log is saved at: $log_file"
  echo "  • If the system doesn't boot, check UEFI boot order in BIOS"
  echo "  • Your original data on $target_drive has been permanently removed"
  echo
  echo -e "${GREEN}Ready to reboot!${NC}"
}

# Script entry point with argument parsing and installation flow
main() {
  # Load modules first - must be done before any function calls
  load_modules
  
  # Initialize constants
  local script_dir
  # default_install_root removed - not used
  local mountpoint
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  readonly script_dir
  readonly default_config_file="${script_dir}/install.conf"
  # readonly default_install_root="/target"

  # Initialize remaining variables
  log_file=""
  custom_config=""
  force_mode=false
  show_win=false
  target_drive=""
  install_root="/target"
  dry_run=false
  debug=false
  user_password=""
  sudo_nopasswd="n"

  if [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
    exit 0
  fi

    # Script directory already determined at module load time
  # Parse command line arguments first
  parse_arguments "$@"

  # Set default log file if not specified
  if [[ -z $log_file   ]]; then
    log_file="${script_dir}/logs/kde-install-$(date +%Y%m%d-%H%M%S).log"
  fi

  # Check root privileges immediately (except for help/dry-run)
  if [[ $dry_run == "false"   ]]; then
    check_root "$@"
  fi

  # Initialize logging and cleanup old logs
  mkdir -p "$(dirname "$log_file")"

  # Delete logs older than 7 days
  if [[ -d "$(dirname "$log_file")" ]]; then
    find "$(dirname "$log_file")" -name "kde-install-*.log" -type f -mtime +7 -delete 2>/dev/null || true
  fi

  # Display a professional welcome banner
  ui_header "KDE Neon Installer v$VERSION" "Automated Installation System"
  
  ui_section "Features"
  ui_status "info" "UEFI-only systems with NVMe drives"
  ui_status "info" "Automatic Windows detection for dual-boot safety"
  ui_status "info" "GeoIP-based timezone and locale detection"
  ui_status "info" "Interactive configuration management"
  
  echo
  ui_status "warn" "Target drive will be completely erased"

  log "INFO" "KDE Neon Automated Installer started"
  log "INFO" "Log file: $log_file"

  # Load existing configuration if available
  load_configuration || true

  # Select the target drive
  select_target_drive

  # Check if the installation directory exists and has data
  if [[ -d $install_root   ]] && [[ -n "$(ls -A "$install_root" 2> /dev/null)" ]]; then
    echo -e "\n${YELLOW}Installation Target Directory Check${NC}"
    echo "The system installation target directory $install_root already exists and contains data."
    echo "This appears to be from a previous installation attempt."
    echo ""

    # Check if anything is mounted in the installation root
    if mount | grep -q "$install_root"; then
      echo "Previous active mounts needed by script are being unmounted..."
      if [[ $dry_run == "false" ]]; then
        # Unmount all filesystems in install_root (reverse order for nested mounts)
        mount | grep "$install_root" | awk '{print $3}' | sort -r | while read -r mountpoint; do
          execute_cmd "umount $mountpoint"
        done
      else
        echo "[DRY-RUN] Would unmount filesystems mounted in $install_root"
      fi
    fi

    echo "Contents that will be removed:"
    if [[ $dry_run == "false" ]]; then
      find "$install_root" -maxdepth 1 -type f -o -type d | head -10
      local file_count
      file_count=$(find "$install_root" -type f 2>/dev/null | wc -l)
      echo "... and $file_count total files"
    else
      echo "[DRY-RUN] Would show directory contents here"
    fi
    echo ""
    echo "This data will be removed to prepare for the new installation."
    echo
    if [[ $dry_run == "false"   ]]; then
      echo "Existing data is being automatically cleaned..."
      execute_cmd "rm -rf $install_root/*" "Cleaning installation directory"
    else
      echo "[DRY-RUN] Would prompt: Continue and remove existing data? (y/N)"
      echo "[DRY-RUN] Would remove existing data in $install_root"
    fi
  fi

  # Save configuration for future runs
  save_configuration

  # Show installation summary and confirm
  echo -e "\n${YELLOW}Installation Summary:${NC}"
  echo -e "Target Drive: ${GREEN}$target_drive${NC} (will be completely erased)"
  echo -e "Installation Root: ${GREEN}$install_root${NC}"
  echo -e "Log File: ${GREEN}$log_file${NC}"
  echo
  echo "This installation will:"
  echo "  • Completely erase $target_drive (all existing data will be lost)"
  echo "  • Create new partitions: 512MB EFI + remaining space for KDE Neon"
  echo "  • Install KDE Neon operating system from this live USB"
  echo "  • Install GRUB bootloader so your computer can start KDE Neon"
  echo "  • Take approximately 15-30 minutes (computer will be unusable during this time)"
  echo ""
  echo -e "${YELLOW}After installation:${NC}"
  echo "  • Your computer will restart into KDE Neon"
  echo "  • Your user account will be ready to use"
  echo "  • Any data on $target_drive will be permanently gone"
  echo

  if [[ $dry_run == "false"   ]]; then
    echo -e "${YELLOW}⚠️  WARNING: This will destroy all data on $target_drive${NC}"
    echo
    read -r -p "Proceed with KDE Neon installation? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$   ]]; then
      log "INFO" "Installation cancelled by user"
      exit 0
    fi
  else
    echo "[DRY-RUN] Would show warning and prompt: Proceed with KDE Neon installation? (y/N)"
  fi

  main_installation

  log "INFO" "KDE Neon Automated Installer completed"
}

main "$@"