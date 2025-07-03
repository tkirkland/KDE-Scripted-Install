# CLAUDE.md

This file provides guidance when working with the KDE Neon automated installer project. This documentation is language-agnostic and applies regardless of implementation technology.

## Project Overview

The KDE Neon automated installer is a comprehensive system installation solution featuring advanced safety mechanisms, configuration management, and dual-boot protection. The project provides a professional-grade installation experience with extensive validation and error recovery.

## Target Environment

- **Target System**: KDE Neon live environment
- **Hardware Requirements**: UEFI systems with NVMe storage
- **System Dependencies**: Standard Linux utilities, GRUB bootloader, systemd-networkd
- **Network Requirements**: Internet connectivity for package downloads

## Project Architecture

The installer implements a robust, safety-first approach to system installation with comprehensive validation at every step.

### Core Design Principles

1. **Safety First**: Multiple layers of protection against data loss
2. **Professional UX**: Clean, informative interface with clear progress indication
3. **Comprehensive Validation**: Extensive input validation and error checking
4. **Configuration Persistence**: Save and restore installation preferences
5. **Dual-Boot Protection**: Automatic Windows detection with user confirmation
6. **Extensibility**: Modular design supporting additional features and GUI implementation

### System Architecture

The installer follows a structured 5-phase approach:

1. **Configuration Management**: Load/validate saved settings or prompt for new configuration
2. **System Preparation**: Hardware validation, drive enumeration, Windows detection
3. **Partitioning**: EFI and root partition creation with proper alignment
4. **System Installation**: Filesystem creation, mounting, and system extraction
5. **Boot Configuration**: GRUB installation, EFI setup, boot entry management
6. **System Configuration**: Network setup, user creation, package cleanup

### Key Components

- **Configuration System**: Comprehensive settings management with validation
- **Hardware Detection**: NVMe drive enumeration with Windows detection
- **Safety Mechanisms**: Multi-layer protection against accidental data loss
- **Installation Engine**: 5-phase structured installation process
- **Logging System**: Detailed operation logging for debugging and audit
- **Addon System**: Extensible script execution for customization

## Implementation Status

### ✅ Core Features Complete

**Configuration Management:**
- Interactive configuration with auto-detected defaults
- Persistent configuration storage with validation
- Comprehensive error detection and recovery
- Edit mode with current values as defaults
- Network configuration (DHCP, static, manual)
- DNS settings for both search domains and routing domains

**Safety Features:**
- Multi-method Windows installation detection
- NVMe drive enumeration and validation
- UEFI boot mode verification
- Boot entry management with conflict resolution
- Comprehensive error handling and logging
- Dry-run mode for testing without system changes

**Installation Process:**
- 5-phase structured installation with progress tracking
- Clean user interface with professional presentation
- User account creation with password validation
- Network configuration using systemd-networkd
- Dynamic swap file sizing based on system RAM
- Automatic package cleanup and system optimization

**System Integration:**
- KDE Neon-specific optimizations
- EFI boot entry management with differential comparison
- System clock and locale configuration
- Addon script execution system for customization

### Configuration Validation Framework

The installer includes a comprehensive validation system:

**Syntax and Integrity Validation:**
- Configuration file syntax checking
- File corruption detection (truncation, binary data)
- Required variable presence verification

**Format Validation:**
- Drive path format validation (`/dev/nvmeXnY` pattern)
- Network settings validation (IP addresses, interfaces)
- Locale format compliance (`xx_XX.UTF-8`)
- Timezone format validation (`Area/City`)
- Username compliance with Linux standards
- Hostname format validation

**Consistency Validation:**
- Static network configuration completeness
- Cross-field dependency checking
- Conflicting settings detection

**Recovery Mechanisms:**
- Automatic corruption detection on startup
- Comprehensive error reporting with specific descriptions
- User choice for configuration deletion or manual correction
- Detailed validation failure logging

## Development Guidelines

### Code Quality Standards

- **Input Validation**: Validate all user inputs before processing
- **Error Handling**: Implement comprehensive error handling with recovery options
- **Logging**: Maintain detailed logs for debugging and audit purposes
- **Security**: Follow security best practices, avoid exposing sensitive information
- **Modularity**: Maintain clean separation between components
- **Documentation**: Document all functions with clear parameter and return specifications

### Testing Requirements

- **Dry-Run Testing**: Always test with simulation mode before live execution
- **Configuration Validation**: Test with corrupted and incomplete configuration files
- **Network Configuration**: Test all network configuration types (DHCP, static, manual)
- **Drive Selection**: Test drive selection with multiple drives and Windows detection
- **Error Scenarios**: Test error handling and recovery mechanisms

### Architecture Patterns

The project follows these architectural patterns:

**Model-View-Controller (MVC)**:
- **Model**: Configuration data, system state, installation progress
- **View**: User interface (CLI currently, GUI-ready architecture)
- **Controller**: Business logic, installation orchestration, user interaction handling

**Observer Pattern**:
- Configuration changes trigger dependent updates
- Installation progress updates notify multiple observers
- Error conditions broadcast to error handlers

**Command Pattern**:
- All system operations wrapped in command objects
- Dry-run mode implementation through command abstraction
- Undo/recovery operations for failed commands

**Strategy Pattern**:
- Network configuration strategies (DHCP, static, manual)
- Drive detection strategies for different hardware types
- Validation strategies for different configuration types

## Future Development Priorities

### GUI Implementation

The current architecture is designed to support GUI implementation with minimal refactoring:

**Frontend Requirements:**
- Modern UI framework (Qt, GTK, Electron, etc.)
- Responsive design for different screen sizes
- Professional styling consistent with KDE design guidelines
- Accessibility support for screen readers and keyboard navigation

**Interface Components:**
- Installation wizard with step-by-step progression
- Drive selection interface with visual drive representation
- Configuration forms with real-time validation
- Progress display with phase visualization and log viewing
- Error dialogs with recovery options

**User Experience Enhancements:**
- Visual drive health and capacity indicators
- Network configuration wizard with connectivity testing
- Real-time installation progress with estimated time remaining
- Configuration import/export functionality
- Advanced options for power users

### Enhanced Features

**Advanced Hardware Support:**
- SATA drive support with performance warnings
- RAID configuration detection and handling
- Multiple drive installation scenarios
- Advanced partitioning schemes (LVM, encryption)

**Enterprise Features:**
- Automated deployment configurations
- Network installation capabilities
- Domain integration and centralized management
- Custom package selection and pre-configuration
- Unattended installation modes

**Security Enhancements:**
- Full disk encryption support with key management
- Secure boot configuration and validation
- TPM integration for hardware-based security
- Network security policy enforcement

## Implementation Considerations

### Language-Agnostic Design

The installer architecture is designed to be implementable in any modern programming language:

**Core Requirements:**
- Object-oriented or functional programming support
- File system and process management capabilities
- Network communication support
- Regular expression and string processing
- Configuration file parsing (JSON, YAML, or similar)

**Recommended Language Features:**
- Strong type system for configuration validation
- Exception handling for error management
- Async/await support for non-blocking operations
- Rich standard library for system operations
- GUI framework availability for future development

**External Dependencies:**
- Minimal external dependencies preferred
- Standard system utilities (parted, mount, etc.)
- Network utilities for connectivity testing
- Package management integration

### Performance Considerations

**Optimization Targets:**
- Fast startup time (< 2 seconds)
- Responsive user interface during long operations
- Efficient drive scanning and Windows detection
- Minimal memory footprint
- Graceful handling of slow storage devices

**Scalability Considerations:**
- Support for systems with many drives
- Efficient handling of large file transfers
- Robust network timeout and retry logic
- Scalable logging without performance impact

## Testing Strategy

### Automated Testing

**Unit Testing:**
- Configuration validation functions
- Input parsing and sanitization
- Network configuration generation
- Drive detection algorithms
- Error handling scenarios

**Integration Testing:**
- Complete installation workflow (dry-run)
- Configuration persistence and loading
- Error recovery mechanisms
- Addon script execution
- Network configuration application

**System Testing:**
- Full installation on test hardware
- Multi-drive scenarios with Windows detection
- Network configuration testing on various setups
- Performance testing with different hardware configurations

### Manual Testing Scenarios

**Configuration Management:**
- Test with valid, invalid, and corrupted configuration files
- Verify edit mode shows current values as defaults
- Test configuration migration between versions

**Drive Selection:**
- Test with single and multiple drives
- Verify Windows detection accuracy
- Test safety mechanisms and user confirmations
- Verify dual-boot scenarios

**Installation Process:**
- Complete installation testing on clean hardware
- Installation over existing systems
- Network connectivity variation testing
- Addon script testing with various scenarios

**Error Handling:**
- Network failure during installation
- Drive disconnection during installation
- Invalid user inputs at various stages
- System interruption and recovery testing

## Deployment Considerations

### Distribution Integration

**KDE Neon Integration:**
- Integration with live system boot process
- Desktop shortcut and application menu integration
- System requirements checking and user guidance
- Documentation and help system integration

**Quality Assurance:**
- Comprehensive testing on reference hardware
- User acceptance testing with diverse configurations
- Performance benchmarking and optimization
- Security audit and vulnerability assessment

### Documentation Requirements

**User Documentation:**
- Installation guide with screenshots/video
- Troubleshooting guide for common issues
- Advanced configuration options documentation
- FAQ covering typical user questions

**Developer Documentation:**
- API documentation for all modules
- Architecture overview and design decisions
- Contribution guidelines and code standards
- Testing procedures and environment setup

**System Documentation:**
- Hardware compatibility list
- Software dependency requirements
- Network configuration examples
- Integration with existing systems

---

This installer provides a robust, professional-grade installation experience for KDE Neon systems. The architecture supports both current command-line usage and future GUI implementation while maintaining the highest standards for safety, reliability, and user experience.