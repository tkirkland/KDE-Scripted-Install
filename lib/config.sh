#!/bin/bash
#
# Module: Configuration Management and Auto-Detection
# Purpose: System configuration, locale/timezone detection, and settings persistence
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
# Configuration module constants
#######################################
readonly CONFIG_VERSION="1.0"

#######################################
# Detect timezone using GeoIP services with fallbacks.
# Provides automatic timezone detection for better user experience.
# Uses multiple GeoIP services for reliability and falls back gracefully.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Timezone string in Area/City format (e.g., America/New_York)
# Returns:
#   Always returns 0 (defaults to UTC on complete failure)
#######################################
detect_timezone_geoip() {
  local detected_tz=""
  
  if command -v curl >/dev/null 2>&1; then
    # Try ipinfo.io first (HTTPS, secure, reliable)
    detected_tz=$(curl -s --connect-timeout 5 --max-time 10 \
                  "https://ipinfo.io/json" 2>/dev/null | \
                  grep -o '"timezone":"[^"]*"' | cut -d'"' -f4)

    # Fallback to ip-api.com if first attempt failed
    if [[ -z "$detected_tz" ]]; then
      detected_tz=$(curl -s --connect-timeout 5 --max-time 10 \
                    "http://ip-api.com/json" 2>/dev/null | \
                    grep -o '"timezone":"[^"]*"' | cut -d'"' -f4)
    fi
  fi

  # If GeoIP failed, fall back to system detection
  if [[ -z "$detected_tz" ]]; then
    detected_tz=$(detect_timezone_system)
  fi

  # Final fallback to UTC if everything fails
  if [[ -z "$detected_tz" ]]; then
    detected_tz="UTC"
  fi
  
  echo "$detected_tz"
}

#######################################
# Detect timezone from system configuration files.
# Fallback method when GeoIP services are unavailable.
# Checks multiple system sources for timezone information.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Timezone string in Area/City format
# Returns:
#   Always returns 0 (defaults to UTC if no system timezone found)
#######################################
detect_timezone_system() {
  local detected_tz=""
  
  # Try reading from /etc/timezone (Debian/Ubuntu)
  if [[ -f /etc/timezone ]]; then
    detected_tz=$(head -n1 /etc/timezone 2>/dev/null | xargs)
  fi
  
  # Try reading from timedatectl if available
  if [[ -z "$detected_tz" ]] && command -v timedatectl >/dev/null 2>&1; then
    detected_tz=$(timedatectl show --property=Timezone --value 2>/dev/null)
  fi
  
  # Default to UTC if nothing found
  if [[ -z "$detected_tz" ]]; then
    detected_tz="UTC"
  fi
  
  echo "$detected_tz"
}

#######################################
# Main timezone detection with GeoIP priority.
# Public interface for timezone detection, tries GeoIP first for accuracy.
# Provides the most accurate timezone detection available.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Best available timezone detection result
# Returns:
#   Always returns 0
#######################################
detect_timezone() {
  detect_timezone_geoip
}

#######################################
# Map country codes to appropriate locales.
# Provides locale suggestions based on detected country from GeoIP.
# Covers major countries and falls back to en_US for others.
# Globals:
#   None
# Arguments:
#   $1: Two-letter country code (e.g., "US", "DE", "FR")
# Outputs:
#   Locale string (e.g., "en_US.UTF-8", "de_DE.UTF-8")
# Returns:
#   Always returns 0
#######################################
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

#######################################
# Auto-detect locale using GeoIP and system detection.
# Provides intelligent locale detection for better user experience.
# Prioritizes system locale over GeoIP suggestions when available.
# Globals:
#   LANG - System language environment variable
# Arguments:
#   None
# Outputs:
#   Locale string in format like "en_US.UTF-8"
# Returns:
#   Always returns 0
#######################################
detect_locale() {
  local detected_locale=""

  # First, try system locale (highest priority if properly set)
  if [[ -n "${LANG:-}" && "$LANG" != "C" && "$LANG" != "POSIX" ]]; then
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
      country_code=$(curl -s --connect-timeout 5 --max-time 10 \
                     "https://ipinfo.io/json" 2>/dev/null | \
                     grep -o '"country":"[^"]*"' | cut -d'"' -f4)

      # Fallback to ip-api.com if first attempt failed
      if [[ -z "$country_code" ]]; then
        country_code=$(curl -s --connect-timeout 5 --max-time 10 \
                       "http://ip-api.com/json" 2>/dev/null | \
                       grep -o '"countryCode":"[^"]*"' | cut -d'"' -f4)
      fi

      if [[ -n "$country_code" ]]; then
        detected_locale=$(get_locale_for_country "$country_code")
      fi
    fi
  fi

  # Final fallback to en_US.UTF-8
  if [[ -z "$detected_locale" ]]; then
    detected_locale="en_US.UTF-8"
  fi

  echo "$detected_locale"
}

#######################################
# Calculate optimal swap size based on available RAM.
# Implements modern best practices for swap sizing on SSDs.
# Provides reasonable defaults that work well for most use cases.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Swap size string with unit (e.g., "8G", "4G")
# Returns:
#   Always returns 0
#######################################
calculate_optimal_swap() {
  local ram_gb
  ram_gb=$(free -g | awk '/^Mem:/ {print $2}')

  # Handle case where RAM is less than 1GB (shows as 0 in -g)
  if [[ $ram_gb -eq 0 ]]; then
    ram_gb=1
  fi

  # Modern best practices for swap sizing on SSDs
  if [[ $ram_gb -le 2 ]]; then
    # Low RAM systems: 2x RAM for stability and hibernation
    echo "$((ram_gb * 2))G"
  elif [[ $ram_gb -le 8 ]]; then
    # Medium RAM systems: equal to RAM
    echo "${ram_gb}G"
  elif [[ $ram_gb -le 32 ]]; then
    # High RAM systems: 8GB is sufficient
    echo "8G"
  else
    # Very high RAM systems: minimal swap needed
    echo "4G"
  fi
}