#!/usr/bin/env python3
"""
Fix TLS segment alignment in 32-bit ARM ELF binaries for Android.
Android Bionic requires TLS alignment to be at least 32 bytes for ARM32.
"""
import sys
import struct

def fix_tls_alignment(filename, new_align=32):
    with open(filename, 'r+b') as f:
        # Read ELF header
        elf_header = f.read(52)  # 32-bit ELF header is 52 bytes
        if elf_header[:4] != b'\x7fELF':
            print(f"Error: {filename} is not an ELF file")
            return False
        
        # Check if 32-bit
        if elf_header[4] != 1:
            print(f"Skipping {filename}: not a 32-bit ELF")
            return False
        
        # Get program header offset and count (32-bit offsets)
        e_phoff = struct.unpack('<I', elf_header[28:32])[0]
        e_phnum = struct.unpack('<H', elf_header[44:46])[0]
        
        # Each program header is 32 bytes in 32-bit ELF
        ph_size = 32
        
        # Find and fix TLS segment
        for i in range(e_phnum):
            ph_offset = e_phoff + (i * ph_size)
            f.seek(ph_offset)
            ph = f.read(ph_size)
            
            p_type = struct.unpack('<I', ph[0:4])[0]
            
            # PT_TLS = 7
            if p_type == 7:
                p_align = struct.unpack('<I', ph[28:32])[0]
                if p_align < new_align:
                    print(f"Fixing TLS alignment in {filename}: {p_align} -> {new_align}")
                    # Write new alignment
                    f.seek(ph_offset + 28)
                    f.write(struct.pack('<I', new_align))
                    return True
                else:
                    print(f"TLS alignment in {filename} is already {p_align}")
                    return True
        
        print(f"No TLS segment found in {filename}")
        return False

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: fix-tls-alignment-arm32.py <elf-file> [alignment]")
        sys.exit(1)
    
    alignment = 32  # Default for ARM32
    if len(sys.argv) >= 3:
        alignment = int(sys.argv[2])
    
    success = fix_tls_alignment(sys.argv[1], alignment)
    sys.exit(0 if success else 1)
