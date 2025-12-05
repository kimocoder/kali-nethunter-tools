#!/usr/bin/env python3
"""
Fix TLS segment skew in ELF binaries for Android.
Android Bionic requires TLS segment address % alignment == 0.
"""
import sys
import struct
import os

def fix_tls_skew(filename):
    # Read the entire file
    with open(filename, 'rb') as f:
        data = bytearray(f.read())
    
    # Check ELF header
    if data[:4] != b'\x7fELF':
        print(f"Error: {filename} is not an ELF file")
        return False
    
    # Check if 32-bit or 64-bit
    ei_class = data[4]
    is_64bit = (ei_class == 2)
    is_32bit = (ei_class == 1)
    
    if not (is_32bit or is_64bit):
        print(f"Error: {filename} has unknown ELF class {ei_class}")
        return False
    
    if is_64bit:
        # 64-bit ELF
        e_phoff = struct.unpack('<Q', data[32:40])[0]
        e_phnum = struct.unpack('<H', data[56:58])[0]
        ph_size = 56
        fmt_offset = '<Q'
        fmt_vaddr = '<Q'
        fmt_paddr = '<Q'
        fmt_filesz = '<Q'
        fmt_memsz = '<Q'
        fmt_align = '<Q'
        size = 8
    else:
        # 32-bit ELF
        e_phoff = struct.unpack('<I', data[28:32])[0]
        e_phnum = struct.unpack('<H', data[44:46])[0]
        ph_size = 32
        fmt_offset = '<I'
        fmt_vaddr = '<I'
        fmt_paddr = '<I'
        fmt_filesz = '<I'
        fmt_memsz = '<I'
        fmt_align = '<I'
        size = 4
    
    # Find TLS segment
    tls_ph_offset = None
    for i in range(e_phnum):
        ph_offset = e_phoff + (i * ph_size)
        p_type = struct.unpack('<I', data[ph_offset:ph_offset+4])[0]
        
        # PT_TLS = 7
        if p_type == 7:
            tls_ph_offset = ph_offset
            break
    
    if tls_ph_offset is None:
        print(f"No TLS segment found in {filename}")
        return False
    
    # Read TLS segment header
    if is_64bit:
        p_offset = struct.unpack(fmt_offset, data[tls_ph_offset+8:tls_ph_offset+16])[0]
        p_vaddr = struct.unpack(fmt_vaddr, data[tls_ph_offset+16:tls_ph_offset+24])[0]
        p_paddr = struct.unpack(fmt_paddr, data[tls_ph_offset+24:tls_ph_offset+32])[0]
        p_filesz = struct.unpack(fmt_filesz, data[tls_ph_offset+32:tls_ph_offset+40])[0]
        p_memsz = struct.unpack(fmt_memsz, data[tls_ph_offset+40:tls_ph_offset+48])[0]
        p_align = struct.unpack(fmt_align, data[tls_ph_offset+48:tls_ph_offset+56])[0]
    else:
        p_offset = struct.unpack(fmt_offset, data[tls_ph_offset+4:tls_ph_offset+8])[0]
        p_vaddr = struct.unpack(fmt_vaddr, data[tls_ph_offset+8:tls_ph_offset+12])[0]
        p_paddr = struct.unpack(fmt_paddr, data[tls_ph_offset+12:tls_ph_offset+16])[0]
        p_filesz = struct.unpack(fmt_filesz, data[tls_ph_offset+16:tls_ph_offset+20])[0]
        p_memsz = struct.unpack(fmt_memsz, data[tls_ph_offset+20:tls_ph_offset+24])[0]
        p_align = struct.unpack(fmt_align, data[tls_ph_offset+28:tls_ph_offset+32])[0]
    
    # Calculate skew
    skew = p_offset % p_align
    vaddr_skew = p_vaddr % p_align
    
    print(f"TLS segment: offset=0x{p_offset:x}, vaddr=0x{p_vaddr:x}, align=0x{p_align:x}")
    print(f"File offset skew: {skew}, vaddr skew: {vaddr_skew}")
    
    if skew == 0 and vaddr_skew == 0:
        print(f"TLS segment is already properly aligned")
        return True
    
    if skew != vaddr_skew:
        print(f"Error: File offset and vaddr have different skews")
        return False
    
    # Calculate padding needed
    padding_needed = (p_align - skew) % p_align
    if padding_needed == 0:
        print(f"TLS segment is already aligned")
        return True
    
    print(f"Need to add {padding_needed} bytes of padding before TLS segment")
    
    # Insert padding before the TLS segment
    padding = b'\x00' * padding_needed
    data = data[:p_offset] + padding + data[p_offset:]
    
    # Update TLS segment offset
    new_p_offset = p_offset + padding_needed
    if is_64bit:
        data[tls_ph_offset+8:tls_ph_offset+16] = struct.pack(fmt_offset, new_p_offset)
    else:
        data[tls_ph_offset+4:tls_ph_offset+8] = struct.pack(fmt_offset, new_p_offset)
    
    # Update all program headers that come after the TLS segment
    for i in range(e_phnum):
        ph_offset = e_phoff + (i * ph_size)
        p_type = struct.unpack('<I', data[ph_offset:ph_offset+4])[0]
        
        if is_64bit:
            ph_p_offset = struct.unpack(fmt_offset, data[ph_offset+8:ph_offset+16])[0]
            if ph_p_offset > p_offset and p_type != 7:  # Not TLS
                new_ph_p_offset = ph_p_offset + padding_needed
                data[ph_offset+8:ph_offset+16] = struct.pack(fmt_offset, new_ph_p_offset)
        else:
            ph_p_offset = struct.unpack(fmt_offset, data[ph_offset+4:ph_offset+8])[0]
            if ph_p_offset > p_offset and p_type != 7:  # Not TLS
                new_ph_p_offset = ph_p_offset + padding_needed
                data[ph_offset+4:ph_offset+8] = struct.pack(fmt_offset, new_ph_p_offset)
    
    # Write the modified file
    with open(filename, 'wb') as f:
        f.write(data)
    
    print(f"Fixed TLS skew in {filename}")
    return True

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: fix-tls-skew.py <elf-file>")
        sys.exit(1)
    
    success = fix_tls_skew(sys.argv[1])
    sys.exit(0 if success else 1)
