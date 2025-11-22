#!/usr/bin/env python3
"""
Fix TLS segment alignment in ELF binaries for Android.
Android Bionic requires TLS alignment of at least 32 for ARM and 64 for ARM64.
"""

import sys
import struct

def fix_tls_alignment(filename, required_alignment):
    """Fix TLS segment alignment in an ELF file."""
    with open(filename, 'r+b') as f:
        # Read ELF header
        elf_header = f.read(64)
        
        # Check if it's an ELF file
        if elf_header[:4] != b'\x7fELF':
            print(f"Error: {filename} is not an ELF file")
            return False
        
        # Get ELF class (32-bit or 64-bit)
        elf_class = elf_header[4]
        is_64bit = (elf_class == 2)
        
        # Get endianness
        endian = elf_header[5]
        is_little_endian = (endian == 1)
        endian_char = '<' if is_little_endian else '>'
        
        # Get program header offset and count
        if is_64bit:
            ph_offset = struct.unpack(endian_char + 'Q', elf_header[32:40])[0]
            ph_entsize = struct.unpack(endian_char + 'H', elf_header[54:56])[0]
            ph_num = struct.unpack(endian_char + 'H', elf_header[56:58])[0]
        else:
            ph_offset = struct.unpack(endian_char + 'I', elf_header[28:32])[0]
            ph_entsize = struct.unpack(endian_char + 'H', elf_header[42:44])[0]
            ph_num = struct.unpack(endian_char + 'H', elf_header[44:46])[0]
        
        # Find and fix TLS segment
        fixed = False
        for i in range(ph_num):
            f.seek(ph_offset + i * ph_entsize)
            ph = f.read(ph_entsize)
            
            # Check if this is a TLS segment (PT_TLS = 7)
            p_type = struct.unpack(endian_char + 'I', ph[0:4])[0]
            if p_type == 7:  # PT_TLS
                # Get current alignment
                if is_64bit:
                    current_align = struct.unpack(endian_char + 'Q', ph[48:56])[0]
                    align_offset = 48
                    align_format = endian_char + 'Q'
                else:
                    current_align = struct.unpack(endian_char + 'I', ph[28:32])[0]
                    align_offset = 28
                    align_format = endian_char + 'I'
                
                print(f"Found TLS segment with alignment: {current_align}")
                
                if current_align < required_alignment:
                    # Update alignment
                    f.seek(ph_offset + i * ph_entsize + align_offset)
                    f.write(struct.pack(align_format, required_alignment))
                    print(f"Fixed TLS alignment: {current_align} -> {required_alignment}")
                    fixed = True
                else:
                    print(f"TLS alignment already sufficient: {current_align} >= {required_alignment}")
                    fixed = True
                
                break
        
        if not fixed:
            print("Warning: No TLS segment found")
            return False
        
        return True

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: fix-tls-alignment.py <elf-file> [alignment]")
        print("Default alignment: 64 for 64-bit, 32 for 32-bit")
        sys.exit(1)
    
    filename = sys.argv[1]
    
    # Determine required alignment
    with open(filename, 'rb') as f:
        elf_header = f.read(5)
        is_64bit = (elf_header[4] == 2)
    
    if len(sys.argv) >= 3:
        required_alignment = int(sys.argv[2])
    else:
        required_alignment = 64 if is_64bit else 32
    
    print(f"Fixing TLS alignment in {filename} to {required_alignment}")
    if fix_tls_alignment(filename, required_alignment):
        print("Success!")
        sys.exit(0)
    else:
        print("Failed!")
        sys.exit(1)
