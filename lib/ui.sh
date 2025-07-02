#!/bin/bash
#
# Module: Professional CLI User Interface
# Purpose: Polished display and input functions for professional presentation
# Dependencies: core.sh

#######################################
# Load dependencies
#######################################
if [[ -z "${SCRIPT_DIR:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  readonly SCRIPT_DIR
fi
# Source core.sh only if not already loaded
if [[ -z "${CORE_VERSION:-}" ]]; then
  source "${SCRIPT_DIR}/lib/core.sh"
fi

#######################################
# UI module constants
#######################################
# Module version for dependency tracking
# shellcheck disable=SC2034  # Used for version checking
readonly UI_VERSION="1.0"
readonly UI_WIDTH=65

# Box drawing characters (compatible with most terminals)
readonly BOX_H="─"
readonly BOX_V="│"
readonly BOX_TL="┌"
readonly BOX_TR="┐"
readonly BOX_BL="└"
readonly BOX_BR="┘"

# Status symbols
readonly SYMBOL_SUCCESS="✓"
readonly SYMBOL_ERROR="✗"
readonly SYMBOL_WARN="!"
readonly SYMBOL_ARROW="→"
readonly SYMBOL_BULLET="•"

#######################################
# Display a professional header with title and optional subtitle.
# Creates consistent branded headers throughout the application.
# Globals:
#   UI_WIDTH
#   BOX_* constants
#   GREEN, NC color codes
# Arguments:
#   $1: Main title text
#   $2: Optional subtitle text
# Outputs:
#   Writes formatted header to stdout
# Returns:
#   Always returns 0
#######################################
ui_header() {
  local title="$1"
  local subtitle="${2:-}"
  local title_len=${#title}
  local subtitle_len=${#subtitle}
  
  # Calculate padding for centering
  local title_padding=$(( (UI_WIDTH - title_len - 2) / 2 ))
  local subtitle_padding=$(( (UI_WIDTH - subtitle_len - 2) / 2 ))
  
  echo
  echo -e "${GREEN}${BOX_TL}$(printf "%*s" $((UI_WIDTH-2)) "" | tr ' ' "${BOX_H}")${BOX_TR}${NC}"
  echo -e "${GREEN}${BOX_V}$(printf "%*s" ${title_padding} "")${title}$(printf "%*s" $((UI_WIDTH - title_len - title_padding - 2)) "")${BOX_V}${NC}"
  
  if [[ -n "$subtitle" ]]; then
    echo -e "${GREEN}${BOX_V}$(printf "%*s" ${subtitle_padding} "")${subtitle}$(printf "%*s" $((UI_WIDTH - subtitle_len - subtitle_padding - 2)) "")${BOX_V}${NC}"
  fi
  
  echo -e "${GREEN}${BOX_BL}$(printf "%*s" $((UI_WIDTH-2)) "" | tr ' ' "${BOX_H}")${BOX_BR}${NC}"
  echo
}

#######################################
# Display a section separator with title.
# Creates visual separation between configuration sections.
# Globals:
#   BLUE, NC color codes
# Arguments:
#   $1: Section title
# Outputs:
#   Writes formatted section header to stdout
# Returns:
#   Always returns 0
#######################################
ui_section() {
  local title="$1"
  echo
  echo -e "${BLUE}${title}:${NC}"
  echo -e "${BLUE}$(printf "%*s" ${#title} "" | tr ' ' '─')${NC}"
}

#######################################
# Display a status message with symbol and formatting.
# Provides consistent status feedback throughout the application.
# Globals:
#   Color codes (RED, GREEN, YELLOW, BLUE, NC)
#   Symbol constants
# Arguments:
#   $1: Status type (success, error, warn, info, arrow)
#   $2: Message text
# Outputs:
#   Writes formatted status message to stdout
# Returns:
#   Always returns 0
#######################################
ui_status() {
  local status_type="$1"
  local message="$2"
  local symbol=""
  local color=""
  
  case "$status_type" in
    "success")
      symbol="$SYMBOL_SUCCESS"
      color="$GREEN"
      ;;
    "error")
      symbol="$SYMBOL_ERROR"  
      color="$RED"
      ;;
    "warn")
      symbol="$SYMBOL_WARN"
      color="$YELLOW"
      ;;
    "info")
      symbol="$SYMBOL_BULLET"
      color="$BLUE"
      ;;
    "arrow")
      symbol="$SYMBOL_ARROW"
      color="$BLUE"
      ;;
    *)
      symbol="$SYMBOL_BULLET"
      color="$NC"
      ;;
  esac
  
  echo -e "${color}${symbol} ${message}${NC}"
}

#######################################
# Display a formatted key-value pair with proper alignment.
# Creates consistent form layouts and configuration displays.
# Globals:
#   BLUE, NC color codes
# Arguments:
#   $1: Key/label text
#   $2: Value text
#   $3: Optional label width (default: 15)
# Outputs:
#   Writes aligned key-value pair to stdout
# Returns:
#   Always returns 0
#######################################
ui_field() {
  local key="$1"
  local value="$2"
  local width="${3:-15}"
  
  printf "  ${BLUE}%-*s${NC}: %s\n" "$width" "$key" "$value"
}

#######################################
# Robust input function with validation, defaults, and formatting.
# Provides consistent, professional input handling throughout application.
# Globals:
#   BLUE, YELLOW, RED, NC color codes
#   SYMBOL_ARROW
# Arguments:
#   $1: Prompt text
#   $2: Default value (optional)
#   $3: Input type: text(default), confirm, password, choice
#   $4: Additional options (validation pattern, choices, etc.)
# Outputs:
#   Writes formatted prompt to stdout
#   Writes user input to stdout (or validation errors to stderr)
# Returns:
#   0 on valid input, 1 on validation failure
#######################################
ui_input() {
  local prompt="$1"
  local default_value="${2:-}"
  local input_type="${3:-text}"
  local options="${4:-}"
  local user_input=""
  
  while true; do
    case "$input_type" in
      "confirm")
        if [[ -n "$default_value" ]]; then
          echo -n -e "${SYMBOL_ARROW} ${prompt} [${BLUE}${default_value}${NC}]: "
        else
          echo -n -e "${SYMBOL_ARROW} ${prompt} (y/n): "
        fi
        read -r -n 1 user_input
        echo  # Move to next line after single character input
        
        # Handle default for confirm type
        if [[ -z "$user_input" && -n "$default_value" ]]; then
          user_input="$default_value"
        fi
        
        case "${user_input,,}" in
          y|yes) echo "y"; return 0 ;;
          n|no) echo "n"; return 0 ;;
          *) ui_status "error" "Please enter 'y' for yes or 'n' for no" ;;
        esac
        ;;
        
      "choice")
        local choices="$options"
        echo -e "  Available options: ${BLUE}${choices}${NC}"
        if [[ -n "$default_value" ]]; then
          echo -n -e "${SYMBOL_ARROW} ${prompt} [${BLUE}${default_value}${NC}]: "
        else
          echo -n -e "${SYMBOL_ARROW} ${prompt}: "
        fi
        read -r user_input
        
        # Use default if empty
        if [[ -z "$user_input" && -n "$default_value" ]]; then
          user_input="$default_value"
        fi
        
        # Validate against choices
        if [[ "$choices" =~ (^|,)${user_input}(,|$) ]]; then
          echo "$user_input"
          return 0
        else
          ui_status "error" "Invalid choice. Please select from: $choices"
        fi
        ;;
        
      "password")
        echo -n -e "${SYMBOL_ARROW} ${prompt}: "
        read -r -s user_input
        echo  # Move to next line after password input
        
        if [[ -n "$user_input" ]]; then
          echo "$user_input"
          return 0
        else
          ui_status "error" "Password cannot be empty"
        fi
        ;;
        
      "text"|*)
        if [[ -n "$default_value" ]]; then
          echo -n -e "${SYMBOL_ARROW} ${prompt} [${BLUE}${default_value}${NC}]: "
        else
          echo -n -e "${SYMBOL_ARROW} ${prompt}: "
        fi
        read -r user_input
        
        # Use default if empty
        if [[ -z "$user_input" && -n "$default_value" ]]; then
          user_input="$default_value"
        fi
        
        # Basic validation for text input
        if [[ -n "$options" ]]; then
          if [[ "$user_input" =~ $options ]]; then
            echo "$user_input"
            return 0
          else
            ui_status "error" "Invalid format. Please try again."
          fi
        else
          echo "$user_input"
          return 0
        fi
        ;;
    esac
  done
}

#######################################
# Display a progress indicator for long-running operations.
# Provides visual feedback during installation phases.
# Globals:
#   GREEN, BLUE, NC color codes
# Arguments:
#   $1: Current step number
#   $2: Total steps
#   $3: Current operation description
# Outputs:
#   Writes progress indicator to stdout
# Returns:
#   Always returns 0
#######################################
ui_progress() {
  local current="$1"
  local total="$2"
  local description="$3"
  local percentage=$((current * 100 / total))
  local progress_width=30
  local filled=$((current * progress_width / total))
  local remaining=$((progress_width - filled))
  
  echo
  echo -e "${BLUE}Progress: ${percentage}% (${current}/${total})${NC}"
  echo -n -e "${GREEN}["
  printf "%*s" "$filled" "" | tr ' ' '█'
  printf "%*s" "$remaining" "" | tr ' ' '░'
  echo -e "]${NC}"
  echo -e "${description}"
  echo
}

#######################################
# Display a summary table of configuration values.
# Shows final configuration before proceeding with installation.
# Globals:
#   BOX_* constants for table borders
#   BLUE, NC color codes
# Arguments:
#   Takes key-value pairs as arguments: key1 value1 key2 value2 ...
# Outputs:
#   Writes formatted configuration table to stdout
# Returns:
#   Always returns 0
#######################################
ui_summary() {
  local title="Configuration Summary"
  echo
  echo -e "${BLUE}${BOX_TL}$(printf "%*s" $((UI_WIDTH-2)) "" | tr ' ' "${BOX_H}")${BOX_TR}${NC}"
  echo -e "${BLUE}${BOX_V} $(printf "%-*s" $((UI_WIDTH-4)) "$title") ${BOX_V}${NC}"
  echo -e "${BLUE}${BOX_V}$(printf "%*s" $((UI_WIDTH-2)) "" | tr ' ' "${BOX_H}")${BOX_V}${NC}"
  
  while [[ $# -gt 1 ]]; do
    local key="$1"
    local value="$2"
    shift 2
    
    printf "${BLUE}${BOX_V}${NC} %-18s: %-*s ${BLUE}${BOX_V}${NC}\n" \
           "$key" $((UI_WIDTH-24)) "$value"
  done
  
  echo -e "${BLUE}${BOX_BL}$(printf "%*s" $((UI_WIDTH-2)) "" | tr ' ' "${BOX_H}")${BOX_BR}${NC}"
  echo
}