#!/usr/bin/env python3
"""
Python Configuration Validation (Standard Library Only)
Demonstrates validation without external dependencies
"""

import re
import ipaddress
from dataclasses import dataclass
from typing import List, Optional, Dict, Any

@dataclass
class ValidationError:
    field: str
    message: str

class ConfigValidator:
    """Configuration validation using standard library only"""
    
    @staticmethod
    def validate_drive_path(drive: str) -> Optional[ValidationError]:
        """Validate NVMe drive path"""
        if not re.match(r'/dev/nvme\d+n\d+$', drive):
            return ValidationError('target_drive', 'Invalid NVMe drive path format')
        return None
    
    @staticmethod
    def validate_ip_address(ip: str) -> Optional[ValidationError]:
        """Validate IP address format"""
        try:
            ipaddress.IPv4Address(ip)
            return None
        except ipaddress.AddressValueError:
            return ValidationError('ip_address', 'Invalid IP address format')
    
    @staticmethod
    def validate_username(username: str) -> Optional[ValidationError]:
        """Validate Linux username"""
        if not re.match(r'^[a-z][a-z0-9_-]*$', username):
            return ValidationError('username', 
                'Username must start with letter, contain only lowercase letters, numbers, underscore, dash')
        if len(username) > 32:
            return ValidationError('username', 'Username too long (max 32 characters)')
        return None
    
    @staticmethod
    def validate_locale(locale: str) -> Optional[ValidationError]:
        """Validate locale format"""
        if not re.match(r'[a-z]{2}_[A-Z]{2}\.UTF-8$', locale):
            return ValidationError('locale', 'Locale must be in format: en_US.UTF-8')
        return None
    
    @staticmethod
    def validate_network_config(config: Dict[str, str]) -> List[ValidationError]:
        """Validate network configuration"""
        errors = []
        network_type = config.get('network_config', '')
        
        if network_type not in ['dhcp', 'static', 'manual']:
            errors.append(ValidationError('network_config', 'Must be dhcp, static, or manual'))
        
        if network_type == 'static':
            required_fields = ['static_ip', 'static_gateway', 'static_iface']
            for field in required_fields:
                if not config.get(field):
                    errors.append(ValidationError(field, f'{field} required for static configuration'))
            
            # Validate IP addresses
            if config.get('static_ip'):
                ip_error = ConfigValidator.validate_ip_address(config['static_ip'])
                if ip_error:
                    errors.append(ip_error)
            
            if config.get('static_gateway'):
                gw_error = ConfigValidator.validate_ip_address(config['static_gateway'])
                if gw_error:
                    gw_error.field = 'static_gateway'
                    errors.append(gw_error)
        
        return errors

def validate_config_file(config_data: Dict[str, str]) -> List[ValidationError]:
    """Validate entire configuration"""
    errors = []
    
    # Required fields
    required = ['target_drive', 'username', 'hostname']
    for field in required:
        if not config_data.get(field):
            errors.append(ValidationError(field, f'{field} is required'))
    
    # Validate individual fields
    if config_data.get('target_drive'):
        drive_error = ConfigValidator.validate_drive_path(config_data['target_drive'])
        if drive_error:
            errors.append(drive_error)
    
    if config_data.get('username'):
        user_error = ConfigValidator.validate_username(config_data['username'])
        if user_error:
            errors.append(user_error)
    
    if config_data.get('locale'):
        locale_error = ConfigValidator.validate_locale(config_data['locale'])
        if locale_error:
            errors.append(locale_error)
    
    # Validate network configuration
    network_errors = ConfigValidator.validate_network_config(config_data)
    errors.extend(network_errors)
    
    return errors

def demo_bash_vs_python():
    """Compare Bash vs Python validation approaches"""
    print("Bash vs Python Configuration Validation")
    print("=" * 50)
    
    # Test data
    test_configs = [
        {
            'name': 'Valid DHCP Config',
            'data': {
                'target_drive': '/dev/nvme0n1',
                'username': 'testuser',
                'hostname': 'kde-test',
                'locale': 'en_US.UTF-8',
                'network_config': 'dhcp'
            }
        },
        {
            'name': 'Valid Static Config',
            'data': {
                'target_drive': '/dev/nvme1n1',
                'username': 'admin',
                'hostname': 'workstation',
                'locale': 'en_US.UTF-8',
                'network_config': 'static',
                'static_ip': '192.168.1.100',
                'static_gateway': '192.168.1.1',
                'static_iface': 'enp0s3'
            }
        },
        {
            'name': 'Invalid Config (Multiple Errors)',
            'data': {
                'target_drive': '/dev/invalid',      # Bad drive path
                'username': '123user',              # Invalid username
                'hostname': '',                     # Empty hostname
                'locale': 'invalid_locale',         # Bad locale
                'network_config': 'static',         # Static but missing fields
                'static_ip': '999.999.999.999'      # Invalid IP
            }
        }
    ]
    
    for test_case in test_configs:
        print(f"\n{test_case['name']}:")
        print("-" * len(test_case['name']))
        
        errors = validate_config_file(test_case['data'])
        
        if errors:
            print("❌ Validation errors found:")
            for error in errors:
                print(f"  {error.field}: {error.message}")
        else:
            print("✅ Configuration is valid")
    
    print(f"\n{'='*50}")
    print("COMPARISON: What this replaces in Bash:")
    print("• 50+ lines of manual validation logic")
    print("• Complex string parsing and regex matching")
    print("• Manual error accumulation and reporting")
    print("• Inconsistent error message formatting")
    print("• No type safety or IDE support")
    print(f"{'='*50}")

if __name__ == "__main__":
    demo_bash_vs_python()