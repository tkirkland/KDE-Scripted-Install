#!/bin/bash

# KDE Install Session Log Parser
# Extracts and reproduces all commands executed during installation

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

LOG_FILE="${1:-session.log}"
OUTPUT_SCRIPT="${2:-extracted_commands.sh}"

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if log file exists
if [[ ! -f "$LOG_FILE" ]]; then
    print_error "Log file '$LOG_FILE' not found!"
    echo "Usage: $0 [session.log] [output_script.sh]"
    exit 1
fi

print_info "Parsing KDE install log: $LOG_FILE"
print_info "Output script: $OUTPUT_SCRIPT"

# Create output script with header
cat > "$OUTPUT_SCRIPT" << 'EOF'
#!/bin/bash

# Generated KDE Installation Command Reproduction Script
# This script contains all commands executed during the KDE installation process
# Generated from session.log analysis

set -euo pipefail

echo "=== KDE Installation Command Reproduction ==="
echo "WARNING: This script contains system-level commands!"
echo "Review carefully before execution."
echo ""

EOF

# Function to parse and format QList commands
parse_qlist_commands() {
    local temp_file=$(mktemp)
    
    # Extract all QList command patterns
    grep '\.\. Running QList([^)]*)'  "$LOG_FILE" | \
    sed 's/.*\.\. Running QList(\([^)]*\)).*/\1/' | \
    sed 's/"//g' | \
    sed 's/, / /g' | \
    while IFS= read -r line; do
        # Skip empty arguments or malformed lines
        if [[ "$line" != *" "* ]] && [[ -z "${line// }" ]]; then
            continue
        fi
        
        # Clean up the command line and validate
        cleaned_line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\000-\037')
        
        # Skip if empty after cleaning or contains invalid characters
        if [[ -z "$cleaned_line" ]] || [[ "$cleaned_line" =~ [{}()] ]]; then
            continue
        fi
        
        # Basic validation - should start with a command
        if [[ "$cleaned_line" =~ ^[a-zA-Z0-9/_-] ]]; then
            echo "$cleaned_line"
        fi
    done | sort -u > "$temp_file"
    
    echo "$temp_file"
}

# Function to extract other command patterns
parse_other_commands() {
    local temp_file=$(mktemp)
    
    # Look for other command execution patterns
    grep -E "(executed|executing|running|launched|starting).*command|Command:|cmd:" "$LOG_FILE" | \
    grep -v "QList" | \
    sed 's/^[^:]*://' | \
    sed 's/^[[:space:]]*//' | \
    grep -v "^$" > "$temp_file" 2>/dev/null || true
    
    echo "$temp_file"
}

# Function to extract filesystem operations
parse_fs_operations() {
    local temp_file=$(mktemp)
    
    # Extract mount, umount, mkfs, etc. operations from context
    grep -E "(mount|umount|mkfs|fsck|parted|fdisk|gdisk|sgdisk)" "$LOG_FILE" | \
    grep -v "QList" | \
    sed 's/^[^:]*://' | \
    sed 's/^[[:space:]]*//' | \
    grep -v "^$" > "$temp_file" 2>/dev/null || true
    
    echo "$temp_file"
}

print_info "Extracting QList commands..."
qlist_temp=$(parse_qlist_commands)
qlist_count=$(wc -l < "$qlist_temp")
print_success "Found $qlist_count unique QList commands."

print_info "Extracting other command patterns..."
other_temp=$(parse_other_commands)
other_count=$(wc -l < "$other_temp")
print_success "Found $other_count other command references."

print_info "Extracting filesystem operations..."
fs_temp=$(parse_fs_operations)
fs_count=$(wc -l < "$fs_temp")
print_success "Found $fs_count filesystem operation references."

# Add QList commands to output script
if [[ $qlist_count -gt 0 ]]; then
    cat >> "$OUTPUT_SCRIPT" << 'EOF'

echo "=== System Information and Disk Operations ==="
echo "The following commands were executed for system discovery and disk operations:"
echo ""

EOF

    while IFS= read -r cmd; do
        if [[ -n "$cmd" ]]; then
            echo "echo \"Executing: $cmd\"" >> "$OUTPUT_SCRIPT"
            echo "# $cmd" >> "$OUTPUT_SCRIPT"
            echo "" >> "$OUTPUT_SCRIPT"
        fi
    done < "$qlist_temp"
fi

# Add other commands if found
if [[ $other_count -gt 0 ]]; then
    cat >> "$OUTPUT_SCRIPT" << 'EOF'

echo "=== Other Installation Commands ==="
echo "Additional commands identified during installation:"
echo ""

EOF

    while IFS= read -r cmd; do
        if [[ -n "$cmd" ]]; then
            echo "echo \"Referenced: $cmd\"" >> "$OUTPUT_SCRIPT"
            echo "# $cmd" >> "$OUTPUT_SCRIPT"
            echo "" >> "$OUTPUT_SCRIPT"
        fi
    done < "$other_temp"
fi

# Add filesystem operations if found
if [[ $fs_count -gt 0 ]]; then
    cat >> "$OUTPUT_SCRIPT" << 'EOF'

echo "=== Filesystem Operations ==="
echo "Filesystem-related operations during installation:"
echo ""

EOF

    while IFS= read -r cmd; do
        if [[ -n "$cmd" ]]; then
            echo "echo \"FS Operation: $cmd\"" >> "$OUTPUT_SCRIPT"
            echo "# $cmd" >> "$OUTPUT_SCRIPT"
            echo "" >> "$OUTPUT_SCRIPT"
        fi
    done < "$fs_temp"
fi

# Add summary section to output script
cat >> "$OUTPUT_SCRIPT" << 'EOF'

echo ""
echo "=== Installation Summary ==="
echo "KDE installation process completed."
echo "This script shows the commands that were executed during installation."
echo ""
echo "IMPORTANT NOTES:"
echo "- Many commands above are system-level operations"
echo "- Some commands may require root privileges"  
echo "- Device paths (/dev/nvme*, /dev/sd*) are specific to the original system"
echo "- Review and modify device paths before executing on different systems"
echo ""

EOF

# Make output script executable
chmod +x "$OUTPUT_SCRIPT"

# Clean up temp files
rm -f "$qlist_temp" "$other_temp" "$fs_temp"

# Print summary
echo ""
print_success "Command extraction completed!"
echo ""
echo "Summary:"
echo "  - QList commands: $qlist_count"
echo "  - Other commands: $other_count" 
echo "  - FS operations: $fs_count"
echo "  - Output script: $OUTPUT_SCRIPT"
echo ""
print_warning "Review the generated script before execution!"
print_info "The script is now executable: ./$OUTPUT_SCRIPT"