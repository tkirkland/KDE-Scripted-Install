#!/bin/bash
#
# Module: Network Configuration Management
# Purpose: Network setup, validation, and systemd-networkd configuration
# Dependencies: core.sh, ui.sh

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

#######################################
# Network module constants and globals
#######################################
# Module version for dependency tracking
# shellcheck disable=SC2034  # Used for version checking
readonly NETWORK_VERSION="1.0"

# Global variables used by network functions
# These are set by the main installer before calling network functions
# shellcheck disable=SC2034  # Variables set externally
install_root=""
static_iface=""
static_ip=""
static_netmask=""
static_gateway=""
static_dns=""
static_domain_search=""
static_dns_suffix=""
network_config=""

#######################################
# Configure DHCP network with systemd-networkd.
# Sets up automatic IP configuration with optional DNS customization.
# Provides professional interface with clear status feedback.
# Globals:
#   None
# Arguments:
#   $1: install_root - Target installation directory
#   $2: static_dns_suffix - Optional DNS suffix (can be empty)
#   $3: static_domain_search - Optional domain search list (can be empty)
# Outputs:
#   Professional status messages during configuration
# Returns:
#   Always returns 0
#######################################
configure_dhcp_network() {
  ui_status "info" "Configuring DHCP network"
  
  local network_config_dir="$install_root/etc/systemd/network"
  
  execute_cmd "mkdir -p '$network_config_dir'" \
             "Creating network configuration directory"

  # Create DHCP configuration with professional formatting
  execute_cmd "cat > '$network_config_dir/20-wired.network' << 'EOF'
[Match]
Name=en*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCP]
UseDNS=yes
UseNTP=yes
EOF" "Creating DHCP network configuration"

  # Configure DNS domains properly (search domains and routing domains are different)
  local domains_list=""
  
  # Add search domains (without ~ prefix) - used for hostname completion
  if [[ -n "${static_domain_search:-}" ]]; then
    ui_status "info" "Adding search domains: $static_domain_search"
    domains_list="$static_domain_search"
  fi
  
  # Add DNS routing domains (with ~ prefix) - used for DNS query routing
  if [[ -n "${static_dns_suffix:-}" ]]; then
    ui_status "info" "Adding DNS routing domains: $static_dns_suffix"
    local routing_domains
    routing_domains=$(echo "$static_dns_suffix" | sed 's/[[:space:]]\+/ ~/g; s/^/~/')
    if [[ -n "$domains_list" ]]; then
      domains_list="$domains_list $routing_domains"
    else
      domains_list="$routing_domains"
    fi
  fi
  
  # Add the combined domains configuration
  if [[ -n "$domains_list" ]]; then
    execute_cmd "echo 'Domains=$domains_list' >> '$network_config_dir/20-wired.network'" \
               "Adding domains configuration"
  fi

  ui_status "success" "DHCP network configuration completed"
  log "INFO" "Created DHCP network configuration"
}

#######################################
# Configure static IP network with systemd-networkd.
# Sets up manual IP configuration with comprehensive validation.
# Provides professional interface with detailed status reporting.
# Globals:
#   None
# Arguments:
#   $1: install_root - Target installation directory
#   $2: static_iface - Network interface name
#   $3: static_ip - Static IP address
#   $4: static_netmask - Subnet mask
#   $5: static_gateway - Gateway IP address
#   $6: static_dns - DNS servers
#   $7: static_domain_search - Domain search list (can be empty)
#   $8: static_dns_suffix - DNS suffix (can be empty)
# Outputs:
#   Professional status messages and configuration summary
# Returns:
#   Always returns 0
#######################################
configure_static_network() {
  ui_section "Static Network Configuration"
  
  # Display configuration summary
  ui_field "Interface" "${static_iface}"
  ui_field "IP Address" "${static_ip}"
  ui_field "Subnet Mask" "${static_netmask}"
  ui_field "Gateway" "${static_gateway}"
  ui_field "DNS Servers" "${static_dns}"
  
  if [[ -n "${static_domain_search:-}" ]]; then
    ui_field "Domain Search" "${static_domain_search}"
  fi
  if [[ -n "${static_dns_suffix:-}" ]]; then
    ui_field "DNS Suffix" "${static_dns_suffix}"
  fi
  echo

  local network_config_dir="$install_root/etc/systemd/network"
  
  execute_cmd "mkdir -p '$network_config_dir'" \
             "Creating network configuration directory"

  # Convert netmask to CIDR notation for systemd-networkd
  local cidr
  case "$static_netmask" in
    "255.255.255.0") cidr="24" ;;
    "255.255.0.0") cidr="16" ;;
    "255.0.0.0") cidr="8" ;;
    "255.255.255.128") cidr="25" ;;
    "255.255.255.192") cidr="26" ;;
    "255.255.255.224") cidr="27" ;;
    "255.255.255.240") cidr="28" ;;
    "255.255.255.248") cidr="29" ;;
    "255.255.255.252") cidr="30" ;;
    *) 
      ui_status "warn" "Unknown netmask format, using /24"
      cidr="24" 
      ;;
  esac

  ui_status "info" "Converting netmask to CIDR: /$cidr"

  # Create static network configuration
  execute_cmd "cat > '$network_config_dir/20-wired.network' << EOF
[Match]
Name=$static_iface

[Network]
Address=$static_ip/$cidr
Gateway=$static_gateway
DNS=$static_dns
IPv6AcceptRA=no

[DHCP]
UseDNS=no
UseNTP=no
EOF" "Creating static network configuration"

  # Configure DNS domains properly (search domains and routing domains are different)
  local domains_list=""
  
  # Add search domains (without ~ prefix) - used for hostname completion
  if [[ -n "${static_domain_search:-}" ]]; then
    ui_status "info" "Adding search domains: $static_domain_search"
    domains_list="$static_domain_search"
  fi
  
  # Add DNS routing domains (with ~ prefix) - used for DNS query routing
  if [[ -n "${static_dns_suffix:-}" ]]; then
    ui_status "info" "Adding DNS routing domains: $static_dns_suffix"
    local routing_domains
    routing_domains=$(echo "$static_dns_suffix" | sed 's/[[:space:]]\+/ ~/g; s/^/~/')
    if [[ -n "$domains_list" ]]; then
      domains_list="$domains_list $routing_domains"
    else
      domains_list="$routing_domains"
    fi
  fi
  
  # Add the combined domains configuration
  if [[ -n "$domains_list" ]]; then
    execute_cmd "echo 'Domains=$domains_list' >> '$network_config_dir/20-wired.network'" \
               "Adding domains configuration"
  fi

  ui_status "success" "Static network configuration completed"
  log "INFO" "Created static network configuration for $static_iface"
}

#######################################
# Configure manual network setup instructions.
# Provides user with guidance for post-installation network setup.
# Creates placeholder configuration with helpful documentation.
# Globals:
#   None
# Arguments:
#   $1: install_root - Target installation directory
# Outputs:
#   Professional status messages and setup instructions
# Returns:
#   Always returns 0
#######################################
configure_manual_network() {
  ui_section "Manual Network Configuration"
  ui_status "info" "Creating manual setup template"
  
  local network_config_dir="$install_root/etc/systemd/network"
  
  execute_cmd "mkdir -p '$network_config_dir'" \
             "Creating network configuration directory"

  # Create template configuration file with instructions
  execute_cmd "cat > '$network_config_dir/README-network.txt' << 'EOF'
KDE Neon Network Configuration
==============================

Manual network configuration was selected during installation.
Please configure your network after first boot.

Configuration Location: /etc/systemd/network/

Example DHCP Configuration:
--------------------------
File: /etc/systemd/network/20-wired.network

[Match]
Name=en*

[Network]
DHCP=yes

Example Static Configuration:
----------------------------
File: /etc/systemd/network/20-wired.network

[Match]
Name=enp0s3  # Replace with your interface name

[Network]
Address=192.168.1.100/24
Gateway=192.168.1.1
DNS=8.8.8.8 8.8.4.4

Commands to configure:
----------------------
1. Find your interface: ip link show
2. Edit configuration: sudo nano /etc/systemd/network/20-wired.network
3. Restart networking: sudo systemctl restart systemd-networkd
4. Check status: sudo networkctl status

For more information:
https://www.freedesktop.org/software/systemd/man/systemd.network.html
EOF" "Creating network setup instructions"

  ui_status "success" "Manual network setup template created"
  ui_status "info" "Instructions saved to /etc/systemd/network/README-network.txt"
  log "INFO" "Created manual network configuration template"
}

#######################################
# Main network configuration dispatcher.
# Routes to appropriate configuration method based on user choice.
# Provides consistent interface and error handling across all methods.
# Globals:
#   None
# Arguments:
#   $1: network_config - User's network configuration choice
#   $2: install_root - Target installation directory
#   $3-N: Additional configuration parameters based on network type
# Outputs:
#   Professional status messages and configuration results
# Returns:
#   Always returns 0
#######################################
configure_network_settings() {
  log "INFO" "Configuring network settings: ${network_config}"
  
  case "${network_config}" in
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
      ui_status "error" "Unknown network configuration: ${network_config}"
      log "ERROR" "Invalid network configuration option: ${network_config}"
      error_exit "Invalid network configuration"
      ;;
  esac
  
  # Enable systemd-networkd for all configurations
  execute_cmd "chroot '$install_root' systemctl enable systemd-networkd" \
             "Enabling systemd-networkd service"
  execute_cmd "chroot '$install_root' systemctl enable systemd-resolved" \
             "Enabling systemd-resolved service"
  
  ui_status "success" "Network configuration completed"
  log "INFO" "Network configuration completed successfully"
}