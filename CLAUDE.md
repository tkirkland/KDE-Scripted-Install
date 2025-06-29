# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a logparser project set up for IntelliJ IDEA development. The project is in its initial stages with only IDE configuration files present.

## Development Environment

- **IDE**: IntelliJ IDEA (configuration files in `.idea/`)
- **Module**: General module type (see `logparser.iml`)

## Project Architecture

This logparser project includes tools for analyzing installation logs and extracting executed commands.

### Core Components

- **parse_kde_install.sh**: Main parser script that extracts commands from KDE Calamares installation logs
- **session.log**: Sample KDE installation log file containing detailed installation process
- **Generated scripts**: Output scripts containing extracted and reproduced commands

### Command Patterns Parsed

The parser identifies and extracts:
1. **QList Commands**: Commands executed via Qt's QList structure (primary pattern)
2. **Shell Commands**: Direct shell command executions
3. **Filesystem Operations**: Mount, unmount, partition, and filesystem commands
4. **Package Management**: APT operations for package installation/removal

## Common Development Tasks

### Running the Parser
```bash
# Parse session.log and generate extracted_commands.sh
./parse_kde_install.sh

# Parse custom log file with custom output
./parse_kde_install.sh /path/to/logfile.log output_script.sh
```

### Analyzing Command Patterns
The parser extracts commands from log patterns like:
- `.. Running QList("command", "arg1", "arg2")`
- Shell execution contexts
- Filesystem operation references

## Log Format

The session.log follows Calamares installer format:
- Timestamped entries: `YYYY-MM-DD - HH:MM:SS [thread]:`
- Command execution logged as QList structures
- Hierarchical job execution with progress tracking

## Implementation Tasks

### Current Priority Tasks
1. **Core Installer Script Structure**
   - Create main installer script with modular function architecture
   - Implement command-line argument parsing (--dry-run, --log-path, --config)
   - Add logging system with timestamped entries to script directory

2. **Drive Management System**
   - Build NVMe drive enumeration and filtering
   - Implement Windows installation detection for dual-boot safety
   - Create drive selection interface with validation

3. **Installation Phases**
   - **Phase 1**: System preparation and validation
   - **Phase 2**: Partitioning and filesystem creation
   - **Phase 3**: System installation and file copying
   - **Phase 4**: Bootloader and EFI configuration
   - **Phase 5**: System configuration and cleanup

4. **Configuration Management**
   - Create settings persistence system
   - Implement initial setup prompts with validation
   - Add configuration file management (save/load/validate)

5. **KDE Neon Integration**
   - Integrate KDE Neon-specific helpers (/usr/bin/calamares-*)
   - Implement filesystem cleanup and package management
   - Configure systemd-networkd and locale settings

6. **System Configuration**
   - Set system clock to local time (not UTC)
   - Configure EFI boot entry as "KDE Neon"
   - Implement swap file creation based on RAM sizing

## Future Development Items

### Enhanced Hardware Support
- Support for non-NVMe drives (SATA SSDs, mechanical drives)
- Multi-drive installation scenarios
- Advanced partitioning schemes beyond simple 2-partition setup

### Configuration Management
- Multiple configuration profiles for different deployment scenarios
- Configuration import/export functionality
- Template-based configurations for bulk deployments

### Advanced Boot Configuration
- Triple-boot and complex multi-boot scenarios
- Custom boot entry management beyond simple "KDE Neon" naming
- Boot recovery and repair tools integration

### Network and Connectivity
- WiFi configuration during installation
- Enterprise network integration (domain joining, certificates)
- Proxy and firewall configuration automation

### Post-Installation Automation
- Automated software installation from predefined lists
- User account and permission setup automation
- System monitoring and health check integration

### Security Enhancements
- Full disk encryption support
- Advanced Secure Boot management
- Security policy enforcement and compliance checking

### User Experience Improvements
- GUI wrapper for the command-line installer
- Progress visualization and better user feedback
- Installation resume capability after interruption

### Enterprise Features
- Integration with deployment systems (Ansible, Puppet, etc.)
- Centralized logging and reporting
- Remote installation monitoring and management

## Technical Requirements

### Hardware & Environment
- **Boot System**: UEFI-only systems (no legacy BIOS support)
- **Storage**: NVMe drives only (/dev/nvmeXXX)
- **Dual-Boot**: Windows detection for safety (prevent accidental overwrites)
- **Secure Boot**: Enabled with MOK signing for graphics drivers
- **Drive Selection**: Internal drives only, exclude USB/external

### Installation Source
- **Source**: Live ISO filesystem extraction
- **Network**: Required for package updates and drivers
- **Package Selection**: Minimal KDE Neon installation
- **Drivers**: Automatic detection and MOK signing

### Partitioning & Storage
- **Partition Scheme**: Simple 2-partition (EFI + root)
- **Filesystem**: ext4 for root partition
- **Swap**: Swap file (not partition) with RAM-based sizing
- **Drive Policy**: Single drive installations only

### User Experience
- **Error Handling**: Comprehensive validation and recovery
- **Progress**: Clear progress indication throughout installation
- **Validation**: Pre-flight checks for all requirements
- **Logging**: Detailed logging for troubleshooting

### Configuration Persistence
- **Scope**: Installation settings and preferences
- **Storage**: Local configuration files in script directory
- **Profiles**: Single configuration profile support
- **Management**: Save/load/validate configuration settings

### System Integration
- **Existing Systems**: Windows detection and dual-boot safety
- **Hardware Detection**: Automatic graphics driver detection
- **Post-Install**: systemd-networkd configuration, locale setup
- **Clock**: System clock set to local time (not UTC)
- **Boot Entry**: EFI entry renamed to "KDE Neon"

## KDE Neon Specific Components

### Calamares Helper Scripts
- `/usr/bin/calamares-l10n-helper`: Localization and translation setup
- `/usr/bin/calamares-logs-helper`: Installation log management
- Custom filesystem cleanup modules

### Configuration Files
- `/calamares/desktop/settings.conf`: Installation sequence configuration
- `/calamares/desktop/modules/grubcfg.conf`: GRUB configuration with cryptodisk support
- Shell process configurations for boot reconfiguration

### Package Management
- **Remove**: calamares, neon-live, casper, '^live-*'
- **Filesystem Tools**: Intelligent cleanup of unused filesystem packages
- **Graphics Drivers**: Automatic detection and MOK signing

### System Configuration
- **Network**: systemd-networkd (replacing netplan)
- **Boot**: EFI bootloader ID changed from "neon" to "KDE Neon"
- **Locale**: Translation and localization helper integration
- **Cleanup**: Automated live system package removal