#!/bin/bash
#
# Module: Hardware Detection and Drive Management
# Purpose: NVMe drive detection, drive selection, and hardware validation
# Dependencies: core.sh, ui.sh, validation.sh

#######################################
# Load dependencies
#######################################
if [[ -z "${SCRIPT_DIR:-}" ]]; then
  # Determine script directory safely
  if ! SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; then
    echo "Error: Cannot determine script directory" >&2
    return 1
  fi
  readonly SCRIPT_DIR
fi
# Source modules only if not already loaded
if [[ -z "${CORE_VERSION:-}" ]]; then
  source "${SCRIPT_DIR}/lib/core.sh"
fi
if [[ -z "${UI_VERSION:-}" ]]; then
  source "${SCRIPT_DIR}/lib/ui.sh"
fi
if [[ -z "${VALIDATION_VERSION:-}" ]]; then
  source "${SCRIPT_DIR}/lib/validation.sh"
fi

#######################################
# Hardware module constants
#######################################
# Module version for dependency tracking
# shellcheck disable=SC2034  # Used for version checking
readonly HARDWARE_VERSION="1.0"

#######################################
# Find and list available internal NVMe drives.
# Filters out external/USB drives for safety and provides only
# suitable installation targets with proper validation.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   List of NVMe drive paths, one per line
# Returns:
#   Always returns 0 (empty list if no drives found)
#######################################
enumerate_nvme_drives() {
  local drives=()
  local drive

  for drive in /dev/nvme*n*; do
    if [[ -b "$drive" && "$drive" =~ /dev/nvme[0-9]+n[0-9]+$ ]]; then
      # Check if it's an internal drive (not USB)
      local drive_name
      drive_name=$(basename "$drive")
      local sys_path="/sys/block/$drive_name"

      if [[ -e "$sys_path" ]]; then
        local removable
        removable=$(cat "$sys_path/removable" 2> /dev/null || echo "0")
        if [[ "$removable" == "0" ]]; then
          drives+=("$drive")
        fi
      fi
    fi
  done

  printf '%s\n' "${drives[@]}"
}

#######################################
# Get detailed information about a specific drive.
# Provides comprehensive drive details including size, model, and health.
# Used for drive selection interface and validation.
# Globals:
#   None
# Arguments:
#   $1: Drive path (e.g., /dev/nvme0n1)
# Outputs:
#   Formatted drive information string
# Returns:
#   0 if drive information retrieved, 1 if drive not accessible
#######################################
get_drive_info() {
  local drive="$1"
  local drive_name
  drive_name=$(basename "$drive")
  
  # Get drive size
  local size_bytes
  size_bytes=$(cat "/sys/block/$drive_name/size" 2>/dev/null || echo "0")
  local size_gb=$((size_bytes * 512 / 1000000000))
  
  # Get drive model if available
  local model=""
  if [[ -f "/sys/block/$drive_name/device/model" ]]; then
    model=$(tr -d '\0' < "/sys/block/$drive_name/device/model" 2>/dev/null | xargs)
  fi
  
  # Format the output
  if [[ -n "$model" ]]; then
    echo "${drive} (${size_gb}GB - ${model})"
  else
    echo "${drive} (${size_gb}GB)"
  fi
}

#######################################
# Display professional drive selection interface.
# Shows available drives with detailed information and safety warnings.
# Handles Windows detection and provides clear user guidance.
# Globals:
#   show_win - Flag to show Windows drives
#   force_mode - Flag to override safety checks
# Arguments:
#   $1: Array of available drives
#   $2: Array of Windows-detected drives
#   $3: Array of safe drives
# Outputs:
#   Professional drive selection interface
# Returns:
#   Selected drive path via stdout
#######################################
display_drive_selection() {
  local -n available_drives=$1
  local -n windows_drives=$2
  local -n safe_drives=$3
  
  ui_section "Drive Selection"
  
  # Show Windows detection results if any found
  if [[ ${#windows_drives[@]} -gt 0 ]]; then
    ui_status "warn" "Windows installations detected on some drives"
    
    if [[ "${show_win:-false}" == "true" ]]; then
      ui_status "info" "All drives shown (--show-win enabled)"
      echo
      ui_field "Windows drives" "${windows_drives[*]}"
      ui_field "Available drives" "${available_drives[*]}"
    elif [[ "${force_mode:-false}" == "true" ]]; then
      ui_status "warn" "Force mode enabled - showing all drives"
      echo
      ui_field "Windows drives" "${windows_drives[*]}"
      ui_field "All drives" "${available_drives[*]}"
    else
      ui_status "info" "Windows drives hidden for safety"
      echo
      ui_field "Windows drives" "${windows_drives[*]} (hidden)"
      ui_field "Safe drives" "${safe_drives[*]}"
    fi
  else
    ui_status "success" "No Windows installations detected"
    ui_field "Available drives" "${available_drives[*]}"
  fi
  
  echo
}

#######################################
# Comprehensive drive selection with safety checks and professional UI.
# Handles Windows detection, drive filtering, and user selection.
# Provides multiple safety layers and clear error messaging.
# Globals:
#   show_win - Show Windows drives flag
#   force_mode - Override safety checks flag
#   target_drive - Selected drive (set by this function)
# Arguments:
#   None
# Outputs:
#   Professional drive selection interface and confirmations
# Returns:
#   0 on successful selection, exits on error or no drives
#######################################
select_target_drive() {
  ui_status "info" "Scanning for NVMe drives..."
  
  local drives
  mapfile -t drives < <(enumerate_nvme_drives)

  if [[ ${#drives[@]} -eq 0 ]]; then
    ui_status "error" "No suitable NVMe drives found"
    echo
    ui_section "Requirements"
    ui_status "info" "UEFI-compatible system required"
    ui_status "info" "Internal NVMe drive required"
    ui_status "info" "USB drives are excluded for safety"
    error_exit "No suitable drives available for installation"
  fi

  ui_status "success" "Found ${#drives[@]} NVMe drive(s)"

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

  # Determine which drives to show based on flags and safety
  local selectable_drives=()
  
  if [[ "$windows_detected" == "true" ]]; then
    if [[ "${show_win:-false}" == "true" ]]; then
      # Show all drives including Windows ones
      selectable_drives=("${drives[@]}")
    elif [[ "${force_mode:-false}" == "true" ]]; then
      # Force mode: show all drives
      selectable_drives=("${drives[@]}")
    else
      # Safety mode: only show safe drives
      if [[ ${#safe_drives[@]} -eq 0 ]]; then
        ui_status "error" "All drives contain Windows installations"
        echo
        ui_section "Safety Options"
        ui_status "info" "Use --show-win to display Windows drives"
        ui_status "info" "Use --force to override safety checks"
        ui_status "warn" "WARNING: These options may destroy Windows"
        error_exit "No safe drives available for installation"
      fi
      selectable_drives=("${safe_drives[@]}")
    fi
  else
    # No Windows detected, use all drives
    selectable_drives=("${drives[@]}")
  fi

  # Display drive selection interface
  display_drive_selection drives windows_drives safe_drives

  # Handle drive selection based on count
  if [[ ${#selectable_drives[@]} -eq 1 ]]; then
    target_drive="${selectable_drives[0]}"
    local drive_info
    drive_info=$(get_drive_info "$target_drive")
    ui_status "arrow" "Using only available drive: $drive_info"
  else
    # Multiple drives available - show selection interface
    ui_section "Available Drives"
    
    local i
    for i in "${!selectable_drives[@]}"; do
      local drive_info
      drive_info=$(get_drive_info "${selectable_drives[$i]}")
      ui_field "$((i + 1))" "$drive_info"
    done
    
    echo
    while true; do
      local selection
      selection=$(ui_input "Select drive number (1-${#selectable_drives[@]})" "1")
      
      if [[ "$selection" =~ ^[0-9]+$ ]] && 
         [[ "$selection" -ge 1 ]] && 
         [[ "$selection" -le ${#selectable_drives[@]} ]]; then
        target_drive="${selectable_drives[$((selection - 1))]}"
        break
      else
        ui_status "error" "Invalid selection. Please enter 1-${#selectable_drives[@]}"
      fi
    done
    
    local drive_info
    drive_info=$(get_drive_info "$target_drive")
    ui_status "success" "Selected: $drive_info"
  fi

  # Final confirmation for Windows drives
  # Check if target drive is in Windows drives array
  local drive_found=false
  for drive in "${windows_drives[@]}"; do
    if [[ "$drive" == "$target_drive" ]]; then
      drive_found=true
      break
    fi
  done
  
  if [[ "$drive_found" == "true" ]]; then
    echo
    ui_status "warn" "WARNING: Selected drive contains Windows installation"
    ui_status "warn" "This will PERMANENTLY destroy the Windows installation"
    
    local confirm
    confirm=$(ui_input "Continue and destroy Windows?" "n" "confirm")
    
    if [[ "$confirm" != "y" ]]; then
      ui_status "info" "Installation cancelled by user"
      exit 0
    fi
    
    ui_status "warn" "Proceeding with Windows drive destruction"
  fi

  log "INFO" "Target drive selected: $target_drive"
}