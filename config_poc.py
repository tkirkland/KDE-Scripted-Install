#!/usr/bin/env python3
"""
Python Proof-of-Concept: Configuration Management
Demonstrates how the current Bash config validation would look in Python
"""

import re
import ipaddress
from pathlib import Path
from dataclasses import dataclass, field
from typing import List, Optional, Dict, Any
from pydantic import BaseModel, validator, ValidationError

class NetworkConfig(BaseModel):
    """Network configuration with built-in validation"""
    network_type: str
    interface: Optional[str] = None
    ip_address: Optional[str] = None
    netmask: Optional[str] = None
    gateway: Optional[str] = None
    dns_servers: Optional[str] = None
    domain_search: Optional[str] = None
    dns_suffix: Optional[str] = None
    
    @validator('network_type')
    def validate_network_type(cls, v):
        if v not in ['dhcp', 'static', 'manual']:
            raise ValueError('network_type must be dhcp, static, or manual')
        return v
    
    @validator('ip_address')
    def validate_ip(cls, v, values):
        if values.get('network_type') == 'static' and not v:
            raise ValueError('IP address required for static configuration')
        if v:
            try:
                ipaddress.IPv4Address(v)
            except ipaddress.AddressValueError:
                raise ValueError('Invalid IP address format')
        return v
    
    @validator('gateway')
    def validate_gateway(cls, v, values):
        if values.get('network_type') == 'static' and not v:
            raise ValueError('Gateway required for static configuration')
        if v:
            try:
                ipaddress.IPv4Address(v)
            except ipaddress.AddressValueError:
                raise ValueError('Invalid gateway IP address')
        return v
    
    @validator('interface')
    def validate_interface(cls, v, values):
        if values.get('network_type') == 'static' and not v:
            raise ValueError('Interface required for static configuration')
        return v

class SystemConfig(BaseModel):
    """Complete system configuration with validation"""
    target_drive: str
    locale: str = "en_US.UTF-8"
    timezone: str = "America/New_York"
    username: str
    hostname: str
    swap_size: str = "auto"
    filesystem: str = "ext4"
    network: NetworkConfig
    
    @validator('target_drive')
    def validate_drive(cls, v):
        if not re.match(r'/dev/nvme\d+n\d+$', v):
            raise ValueError('Invalid NVMe drive path format')
        if not Path(v).exists():
            raise ValueError(f'Drive {v} does not exist')
        return v
    
    @validator('locale')
    def validate_locale(cls, v):
        if not re.match(r'[a-z]{2}_[A-Z]{2}\.UTF-8$', v):
            raise ValueError('Locale must be in format: en_US.UTF-8')
        return v
    
    @validator('timezone')
    def validate_timezone(cls, v):
        if not re.match(r'[A-Z][a-z_]+/[A-Z][a-z_]+$', v):
            raise ValueError('Timezone must be in format: America/New_York')
        return v
    
    @validator('username')
    def validate_username(cls, v):
        if not re.match(r'^[a-z][a-z0-9_-]*$', v):
            raise ValueError('Username must start with letter, contain only lowercase letters, numbers, underscore, dash')
        if len(v) > 32:
            raise ValueError('Username too long (max 32 characters)')
        return v
    
    @validator('hostname')
    def validate_hostname(cls, v):
        if not re.match(r'^[a-zA-Z0-9-]+$', v):
            raise ValueError('Hostname can only contain letters, numbers, and hyphens')
        if len(v) > 63:
            raise ValueError('Hostname too long (max 63 characters)')
        return v

class ConfigManager:
    """Configuration management with validation"""
    
    def __init__(self, config_file: str = "install.conf"):
        self.config_file = Path(config_file)
        self.config: Optional[SystemConfig] = None
    
    def load_config(self) -> Optional[SystemConfig]:
        """Load and validate configuration"""
        if not self.config_file.exists():
            print(f"❌ Configuration file {self.config_file} not found")
            return None
        
        try:
            # Parse the shell-style config (simplified for demo)
            config_data = self._parse_shell_config()
            
            # Validate with Pydantic
            self.config = SystemConfig(**config_data)
            print("✅ Configuration loaded and validated successfully")
            return self.config
            
        except ValidationError as e:
            print("❌ Configuration validation failed:")
            for error in e.errors():
                field = " → ".join(str(x) for x in error['loc'])
                print(f"  {field}: {error['msg']}")
            return None
        
        except Exception as e:
            print(f"❌ Error loading configuration: {e}")
            return None
    
    def _parse_shell_config(self) -> Dict[str, Any]:
        """Parse shell-style configuration file"""
        config_data = {}
        
        # This is a simplified parser - in reality you'd use something more robust
        content = self.config_file.read_text()
        
        # Extract basic variables
        for line in content.splitlines():
            line = line.strip()
            if '=' in line and not line.startswith('#'):
                key, value = line.split('=', 1)
                # Remove quotes
                value = value.strip('"\'')
                config_data[key] = value
        
        # Structure the data for Pydantic
        network_data = {
            'network_type': config_data.get('network_config', 'dhcp'),
            'interface': config_data.get('static_iface'),
            'ip_address': config_data.get('static_ip'),
            'netmask': config_data.get('static_netmask'),
            'gateway': config_data.get('static_gateway'),
            'dns_servers': config_data.get('static_dns'),
            'domain_search': config_data.get('static_domain_search'),
            'dns_suffix': config_data.get('static_dns_suffix'),
        }
        
        structured_config = {
            'target_drive': config_data.get('target_drive', ''),
            'locale': config_data.get('locale', 'en_US.UTF-8'),
            'timezone': config_data.get('timezone', 'America/New_York'),
            'username': config_data.get('username', ''),
            'hostname': config_data.get('hostname', ''),
            'swap_size': config_data.get('swap_size', 'auto'),
            'filesystem': config_data.get('filesystem', 'ext4'),
            'network': network_data
        }
        
        return structured_config
    
    def save_config(self, config: SystemConfig) -> None:
        """Save configuration to file"""
        content = f'''# KDE Neon Installation Configuration
target_drive="{config.target_drive}"
locale="{config.locale}"
timezone="{config.timezone}"
username="{config.username}"
hostname="{config.hostname}"
swap_size="{config.swap_size}"
filesystem="{config.filesystem}"

# Network Configuration
network_config="{config.network.network_type}"
'''
        
        if config.network.network_type == 'static':
            content += f'''static_iface="{config.network.interface}"
static_ip="{config.network.ip_address}"
static_netmask="{config.network.netmask}"
static_gateway="{config.network.gateway}"
static_dns="{config.network.dns_servers}"
'''
        
        if config.network.domain_search:
            content += f'static_domain_search="{config.network.domain_search}"\n'
        
        if config.network.dns_suffix:
            content += f'static_dns_suffix="{config.network.dns_suffix}"\n'
        
        self.config_file.write_text(content)
        print(f"✅ Configuration saved to {self.config_file}")

def demo_validation():
    """Demonstrate configuration validation"""
    print("Python Configuration Validation Demo")
    print("=" * 40)
    
    # Test 1: Valid configuration
    print("\n1. Testing valid configuration:")
    try:
        valid_config = SystemConfig(
            target_drive="/dev/nvme0n1",
            username="testuser",
            hostname="kde-test",
            network=NetworkConfig(
                network_type="static",
                interface="enp0s3",
                ip_address="192.168.1.100",
                netmask="255.255.255.0",
                gateway="192.168.1.1",
                dns_servers="8.8.8.8",
                domain_search="home.local",
                dns_suffix="corp.example.com"
            )
        )
        print("✅ Valid configuration created successfully")
    except ValidationError as e:
        print("❌ Validation failed:")
        for error in e.errors():
            print(f"  {error['loc']}: {error['msg']}")
    
    # Test 2: Invalid configuration
    print("\n2. Testing invalid configuration:")
    try:
        invalid_config = SystemConfig(
            target_drive="/dev/invalid",  # Invalid drive
            username="123invalid",       # Invalid username
            hostname="",                # Empty hostname  
            network=NetworkConfig(
                network_type="static",
                # Missing required fields for static
                ip_address="invalid.ip",  # Invalid IP
            )
        )
    except ValidationError as e:
        print("❌ Expected validation errors found:")
        for error in e.errors():
            field = " → ".join(str(x) for x in error['loc'])
            print(f"  {field}: {error['msg']}")

if __name__ == "__main__":
    demo_validation()