#!/usr/bin/env python3
"""
Fix TLS segment alignment in ELF binaries for Android ARM64.
Android Bionic requires TLS alignment to be at least 64 bytes.
"""
import sys
import struct

def fix_tls_alignment(filename, new_align=64):
    with open(filename, 'r+b') as f:
        # Read ELF header
        elf_header = f.read(64)
        if elf_header[:4] != b'\x7fELF':
            print(f"Error: {filename} is not an ELF file")
            return False
        
        # Check if 64-bit
        if elf_header[4] != 2:
            print(f"Skipping {filename}: not a 64-bit ELF")
            return False
        
        # Get program header offset and count
        e_phoff = struct.unpack('<Q', elf_header[32:40])[0]
        e_phnum = struct.unpack('<H', elf_header[56:58])[0]
        
        # Each program header is 56 bytes in 64-bit ELF
        ph_size = 56
        
        # Find and fix TLS segment
        for i in range(e_phnum):
            ph_offset = e_phoff + (i * ph_size)
            f.seek(ph_offset)
            ph = f.read(ph_size)
            
            p_type = struct.unpack('<I', ph[0:4])[0]
            
            # PT_TLS = 7
            if p_type == 7:
                p_align = struct.unpack('<Q', ph[48:56])[0]
                if p_align < new_align:
                    print(f"Fixing TLS alignment in {filename}: {p_align} -> {new_align}")
                    # Write new alignment
                    f.seek(ph_offset + 48)
                    f.write(struct.pack('<Q', new_align))
                    return True
                else:
                    print(f"TLS alignment in {filename} is already {p_align}")
                    return True
        
        print(f"No TLS segment found in {filename}")
        return False

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: fix-tls-alignment.py <elf-file>")
        sys.exit(1)
    
    success = fix_tls_alignment(sys.argv[1])
    sys.exit(0 if success else 1)
