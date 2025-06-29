# KDE Neon Log Parser & Installer

A comprehensive toolkit for analyzing KDE Calamares installation logs and creating automated command-line installers for KDE Neon systems.

## Overview

This project extracts and analyzes commands from KDE Calamares installation logs to create reproducible, automated installation scripts. It transforms logged installation processes into standalone command-line installers with enhanced features like drive enumeration, dual-boot safety, and configuration persistence.

## Features

### Log Analysis
- **Pattern Recognition**: Extracts QList commands and shell executions from Calamares logs
- **Command Validation**: Validates and filters extracted commands for reproducibility  
- **Execution Reproduction**: Generates executable scripts that mirror original installations

### Automated Installation
- **Drive Enumeration**: Dynamic NVMe drive detection and selection
- **Dual-Boot Safety**: Windows installation detection to prevent accidental overwrites
- **Configuration Persistence**: Save and load installation preferences
- **Dry-Run Mode**: Test installations without making system changes
- **Comprehensive Logging**: Detailed logging for debugging and validation

### KDE Neon Integration
- **Helper Scripts**: Integration with KDE Neon-specific Calamares helpers
- **Package Management**: Intelligent cleanup of live system packages
- **System Configuration**: Proper locale, network, and boot configuration

## Quick Start

### Prerequisites
- UEFI-capable system
- NVMe storage device
- KDE Neon live environment
- Root privileges for installation

### Basic Usage

```bash
# Parse installation log and generate command script
./parse_kde_install.sh session.log extracted_commands.sh

# Run with dry-run mode (recommended first run)
sudo ./kde_neon_installer.sh --dry-run

# Run actual installation with custom log path
sudo ./kde_neon_installer.sh --log-path /var/log/kde-install.log

# Use custom configuration file
sudo ./kde_neon_installer.sh --config /path/to/install.conf
```

## Project Structure

```
logparser/
├── README.md                 # This file
├── CLAUDE.md                 # Project documentation and requirements
├── parse_kde_install.sh      # Log parser script
├── extracted_commands.sh     # Generated command extraction
├── kde_commands.sh          # Processed commands for installer
├── session.log             # Sample KDE installation log (gitignored)
└── .gitignore              # Git ignore rules
```

## Components

### Core Scripts

#### `parse_kde_install.sh`
Main parser that extracts commands from Calamares installation logs.

**Usage:**
```bash
./parse_kde_install.sh [input_log] [output_script]
```

**Features:**
- Extracts QList command patterns
- Validates command structure
- Generates executable reproduction scripts
- Handles filesystem operations and package management

#### `extracted_commands.sh` (Generated)
Raw extracted commands from the installation log, organized by execution context.

#### `kde_commands.sh` (Generated)  
Processed and validated commands ready for installer integration.

### Installation Phases

The comprehensive installer follows a structured 5-phase approach:

1. **System Preparation**: Hardware validation, drive enumeration, Windows detection
2. **Partitioning**: EFI and root partition creation with proper alignment
3. **System Installation**: Filesystem creation, mounting, and file system extraction
4. **Bootloader Configuration**: GRUB installation, EFI setup, boot entry creation
5. **System Configuration**: Network setup, locale configuration, package cleanup

## Technical Requirements

### Hardware Support
- **Boot System**: UEFI-only (no legacy BIOS)
- **Storage**: NVMe drives only (`/dev/nvmeXXX`)
- **Security**: Secure Boot with MOK signing capability
- **Memory**: Minimum 4GB RAM (affects swap file sizing)

### Software Dependencies
- KDE Neon live environment
- Calamares helper scripts (`/usr/bin/calamares-*`)
- Standard Linux utilities (blkid, mount, rsync, etc.)
- GRUB bootloader packages

### Supported Configurations
- **Partitioning**: Simple 2-partition scheme (EFI + root)
- **Filesystem**: ext4 for root, FAT32 for EFI
- **Swap**: File-based swap (not partition)
- **Network**: systemd-networkd configuration
- **Boot**: Single-boot or dual-boot with Windows detection

## Configuration

### Initial Setup
On first run, the installer prompts for:
- Target drive selection
- User account information
- Locale and timezone settings
- Network configuration preferences
- Swap file sizing options

### Configuration Persistence
Settings are saved to `install.conf` in the script directory:
```ini
[system]
target_drive=/dev/nvme0n1
locale=en_US.UTF-8
timezone=America/New_York

[user]
username=user
hostname=kde-neon

[storage]
swap_size=8G
filesystem=ext4
```

### Command Line Options
```bash
Usage: kde_neon_installer.sh [options]

Options:
  --dry-run              Test mode - show what would be done
  --log-path PATH        Custom log file location
  --config PATH          Use custom configuration file
  --force                Skip safety checks (use with caution)
  --help                 Show this help message
```

## Safety Features

### Pre-Installation Validation
- **Hardware Compatibility**: UEFI and NVMe drive verification
- **Windows Detection**: Prevents accidental dual-boot overwrites
- **Drive Selection**: Internal drives only, excludes USB/external
- **Space Requirements**: Validates available storage space

### Dual-Boot Protection
- Automatically detects existing Windows installations
- Prompts for confirmation before modifying Windows drives
- Preserves EFI system partitions when possible
- Creates separate boot entries for each OS

### Error Handling
- Comprehensive validation at each installation phase
- Rollback capability for failed operations
- Detailed error logging and reporting
- Safe exit on critical failures

## Development

### Contributing
1. Fork the repository
2. Create a feature branch
3. Test changes in a virtual environment
4. Submit pull request with detailed description

### Testing
```bash
# Test log parsing
./parse_kde_install.sh test_session.log test_output.sh

# Validate generated commands
bash -n extracted_commands.sh

# Test installer in dry-run mode
sudo ./kde_neon_installer.sh --dry-run
```

### Architecture
- **Modular Design**: Separate functions for each installation phase
- **Error Recovery**: Graceful handling of installation failures
- **Logging**: Comprehensive logging for debugging and validation
- **Configuration**: Persistent settings and user preferences

## Future Development

### Planned Features
- **Enhanced Hardware**: Support for SATA drives and advanced partitioning
- **GUI Interface**: Graphical frontend for the command-line installer
- **Network Installation**: Remote installation and configuration management
- **Security**: Full disk encryption and advanced security features
- **Enterprise**: Integration with deployment systems and centralized management

### Roadmap
See [CLAUDE.md](CLAUDE.md) for detailed implementation tasks and future development items.

## Troubleshooting

### Common Issues

**Parser fails with "command not found"**
- Ensure log file exists and is readable
- Check log format matches Calamares output
- Verify bash version compatibility

**Installer fails drive detection**
- Confirm NVMe drives are present
- Check UEFI boot mode is enabled
- Verify drive permissions and accessibility

**Installation hangs or fails**
- Review installation logs for specific errors
- Check available disk space and memory
- Verify network connectivity for package downloads

### Debug Mode
Enable verbose logging:
```bash
export DEBUG=1
sudo ./kde_neon_installer.sh --dry-run
```

### Log Analysis
Installation logs are saved to:
- Default: `./kde-install-YYYYMMDD-HHMMSS.log`
- Custom: Specified via `--log-path` option

## License

This project is released under the GPL-3.0 license, consistent with KDE and Calamares licensing.

## Acknowledgments

- **KDE Neon Team**: For the excellent distribution and Calamares configuration
- **Calamares Project**: For the modular installation framework
- **Community Contributors**: For testing, feedback, and improvements

---

For detailed technical documentation, see [CLAUDE.md](CLAUDE.md).