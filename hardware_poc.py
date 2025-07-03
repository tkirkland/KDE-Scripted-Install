#!/usr/bin/env python3
"""
Python Proof-of-Concept: Hardware Detection Module
Demonstrates how the current Bash hardware detection would look in Python
"""

import re
import subprocess
from pathlib import Path
from dataclasses import dataclass
from typing import List, Optional, Tuple
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

@dataclass
class Drive:
    """Represents a storage drive with all relevant information"""
    path: str
    size_gb: int
    model: str
    is_removable: bool
    has_windows: bool = False
    
    def __str__(self) -> str:
        if self.model:
            return f"{self.path} ({self.size_gb}GB - {self.model})"
        return f"{self.path} ({self.size_gb}GB)"

@dataclass
class EfiEntry:
    """Represents an EFI boot entry"""
    boot_id: str
    name: str
    device_path: str
    drive: Optional[str] = None
    
    @classmethod
    def parse_from_efibootmgr(cls, line: str) -> Optional['EfiEntry']:
        """Parse EFI entry from efibootmgr output"""
        # Example: Boot0006* KDE neon      HD(1,GPT,88a04cd7-4fb4-4a9f-898b-36e3fb5534e3,0x800,0x100000)/File(\EFI\KDE Neon\shimx64.efi)
        match = re.match(r'Boot([0-9A-F]+)\*?\s+(.+?)\s+(HD\(.+)', line)
        if not match:
            return None
        
        boot_id, name, device_path = match.groups()
        return cls(boot_id=boot_id, name=name.strip(), device_path=device_path)

class HardwareDetector:
    """Hardware detection and management"""
    
    def __init__(self, dry_run: bool = False):
        self.dry_run = dry_run
        self.drives: List[Drive] = []
        self.efi_entries: List[EfiEntry] = []
    
    def enumerate_nvme_drives(self) -> List[Drive]:
        """Find and validate NVMe drives - much cleaner than Bash version"""
        drives = []
        
        for device_path in Path('/dev').glob('nvme*n*'):
            if not device_path.is_block_device():
                continue
                
            # Check if it matches NVMe pattern
            if not re.match(r'/dev/nvme\d+n\d+$', str(device_path)):
                continue
            
            drive_name = device_path.name
            sys_path = Path(f'/sys/block/{drive_name}')
            
            if not sys_path.exists():
                continue
            
            # Check if removable (exclude USB drives)
            removable_file = sys_path / 'removable'
            try:
                is_removable = removable_file.read_text().strip() == '1'
                if is_removable:
                    continue
            except (FileNotFoundError, PermissionError):
                # If we can't read, assume it's not removable
                pass
            
            # Get drive size
            try:
                size_sectors = int((sys_path / 'size').read_text().strip())
                size_gb = (size_sectors * 512) // (1000 * 1000 * 1000)
            except (FileNotFoundError, ValueError):
                size_gb = 0
            
            # Get drive model
            model_file = sys_path / 'device' / 'model'
            try:
                model = model_file.read_text().strip().replace('\x00', '')
            except (FileNotFoundError, PermissionError):
                model = "Unknown"
            
            # Check for Windows installation
            has_windows = self.detect_windows(str(device_path))
            
            drive = Drive(
                path=str(device_path),
                size_gb=size_gb,
                model=model,
                is_removable=is_removable,
                has_windows=has_windows
            )
            drives.append(drive)
            
        logger.info(f"Found {len(drives)} NVMe drives")
        self.drives = drives
        return drives
    
    def detect_windows(self, drive_path: str) -> bool:
        """Detect Windows installation on drive"""
        try:
            if self.dry_run:
                logger.info(f"[DRY-RUN] Would check Windows on {drive_path}")
                return False
            
            # Check for Windows Boot Manager
            result = subprocess.run(['blkid', '-o', 'value', '-s', 'LABEL', drive_path + 'p1'], 
                                  capture_output=True, text=True)
            return 'EFI' in result.stdout or 'SYSTEM' in result.stdout
            
        except (subprocess.SubprocessError, FileNotFoundError):
            return False
    
    def get_efi_entries(self) -> List[EfiEntry]:
        """Get EFI boot entries - much simpler than Bash parsing"""
        try:
            if self.dry_run:
                logger.info("[DRY-RUN] Would get EFI entries")
                return []
            
            result = subprocess.run(['efibootmgr'], capture_output=True, text=True, check=True)
            entries = []
            
            for line in result.stdout.splitlines():
                if 'KDE' in line.upper():
                    entry = EfiEntry.parse_from_efibootmgr(line)
                    if entry:
                        entries.append(entry)
            
            self.efi_entries = entries
            return entries
            
        except (subprocess.SubprocessError, FileNotFoundError):
            logger.warning("efibootmgr not available")
            return []
    
    def categorize_drives(self, target_drive: str) -> Tuple[List[Drive], List[Drive]]:
        """Separate safe drives from Windows drives"""
        safe_drives = []
        windows_drives = []
        
        for drive in self.drives:
            if drive.has_windows:
                windows_drives.append(drive)
            else:
                safe_drives.append(drive)
        
        return safe_drives, windows_drives
    
    def display_drive_selection(self, available_drives: List[Drive], 
                              windows_drives: List[Drive], 
                              safe_drives: List[Drive]) -> None:
        """Display drive selection interface"""
        print("\nDrive Selection")
        print("═" * 50)
        
        if windows_drives:
            print(f"⚠ Windows installations detected on {len(windows_drives)} drives")
            print(f"Windows drives: {[str(d) for d in windows_drives]}")
            print(f"Safe drives: {[str(d) for d in safe_drives]}")
        else:
            print("✓ No Windows installations detected")
            print(f"Available drives: {[str(d) for d in available_drives]}")

def main():
    """Demo the Python hardware detection"""
    print("Python Hardware Detection Proof-of-Concept")
    print("=" * 50)
    
    detector = HardwareDetector(dry_run=True)
    
    # Enumerate drives
    drives = detector.enumerate_nvme_drives()
    
    if not drives:
        print("❌ No suitable NVMe drives found")
        return
    
    # Get EFI entries
    efi_entries = detector.get_efi_entries()
    
    # Categorize drives
    safe_drives, windows_drives = detector.categorize_drives("/dev/nvme0n1")
    
    # Display selection
    detector.display_drive_selection(drives, windows_drives, safe_drives)
    
    print(f"\nFound {len(efi_entries)} KDE EFI entries")
    for entry in efi_entries:
        print(f"  {entry.boot_id}: {entry.name}")

if __name__ == "__main__":
    main()