#!/usr/bin/env python3
#
# rfkill control code
#
# Copyright (c) 2015	Intel Corporation
#
# Author: Johannes Berg <johannes.berg@intel.com>
#
# This software may be distributed under the terms of the MIT license.
# See COPYING for more details.

import struct
import fcntl
import os

(TYPE_ALL,
 TYPE_WLAN,
 TYPE_BLUETOOTH,
 TYPE_UWB,
 TYPE_WIMAX,
 TYPE_WWAN,
 TYPE_GPS,
 TYPE_FM,
 TYPE_NFC) = range(9)

(_OP_ADD,
 _OP_DEL,
 _OP_CHANGE,
 _OP_CHANGE_ALL) = range(4)

HARD_BLOCK_SIGNAL = 1 << 0
HARD_BLOCK_NOT_OWNER = 1 << 1

_type_names = {
    TYPE_ALL: "all",
    TYPE_WLAN: "Wireless LAN",
    TYPE_BLUETOOTH: "Bluetooth",
    TYPE_UWB: "Ultra-Wideband",
    TYPE_WIMAX: "WiMAX",
    TYPE_WWAN: "Wireless WAN",
    TYPE_GPS: "GPS",
    TYPE_FM: "FM",
    TYPE_NFC: "NFC",
}

# idx, type, op, soft, hard, hard_block_reasons
_event_struct = '@IBBBBB'
_event_sz = struct.calcsize(_event_struct)

# idx, type, op, soft, hard
_event_struct_old = '@IBBBB'
_event_old_sz = struct.calcsize(_event_struct_old)

class RFKillException(Exception):
    pass

class RFKill(object):
    def __init__(self, idx):
        self._idx = idx
        self._type = None

    @property
    def idx(self):
        return self._idx

    @property
    def name(self):
        return open('/sys/class/rfkill/rfkill%d/name' % self._idx, 'r').read().rstrip()

    @property
    def type(self):
        if not self._type:
            for r, s, h, hbr in RFKill.list():
                if r.idx == self.idx:
                    self._type = r._type
                    break
        return self._type

    @property
    def type_name(self):
        return _type_names.get(self._type, "unknown")

    @property
    def blocked(self):
        l = RFKill.list()
        for r, s, h, hbr in l:
            if r.idx == self.idx:
                return (s, h)
        raise RFKillException("RFKill instance no longer exists")

    @property
    def soft_blocked(self):
        return self.blocked[0]

    @soft_blocked.setter
    def soft_blocked(self, block):
        if block:
            self.block()
        else:
            self.unblock()

    @property
    def hard_blocked(self):
        return self.blocked[1]

    def block(self):
        rfk = open('/dev/rfkill', 'wb', buffering=0)
        s = struct.pack(_event_struct_old, self.idx, TYPE_ALL, _OP_CHANGE, 1, 0)
        rfk.write(s)
        rfk.close()

    def unblock(self):
        rfk = open('/dev/rfkill', 'wb', buffering=0)
        s = struct.pack(_event_struct_old, self.idx, TYPE_ALL, _OP_CHANGE, 0, 0)
        rfk.write(s)
        rfk.close()

    @classmethod
    def block_all(cls, t=TYPE_ALL):
        rfk = open('/dev/rfkill', 'wb', buffering=0)
        s = struct.pack(_event_struct_old, 0, t, _OP_CHANGE_ALL, 1, 0)
        rfk.write(s)
        rfk.close()

    @classmethod
    def unblock_all(cls, t=TYPE_ALL):
        rfk = open('/dev/rfkill', 'wb', buffering=0)
        s = struct.pack(_event_struct_old, 0, t, _OP_CHANGE_ALL, 0, 0)
        rfk.write(s)
        rfk.close()

    @classmethod
    def list(cls):
        res = []
        rfk = open('/dev/rfkill', 'rb', buffering=0)
        fd = rfk.fileno()
        flgs = fcntl.fcntl(fd, fcntl.F_GETFL)
        fcntl.fcntl(fd, fcntl.F_SETFL, flgs | os.O_NONBLOCK)
        while True:
            try:
                d = rfk.read(_event_sz)
                if d is None:
                    break
                read_len = len(d)
                assert read_len >= _event_old_sz

                # init additional fields of newer formats to 'None' here
                _hbr = None

                # hard block reason included ?
                if read_len >= _event_sz:
                    _idx, _t, _op, _s, _h, _hbr = struct.unpack(_event_struct,
                                                                d[:_event_sz])
                else:
                    _idx, _t, _op, _s, _h = struct.unpack(_event_struct_old, d)

                if _op != _OP_ADD:
                    continue
                r = RFKill(_idx)
                r._type = _t
                res.append((r, _s, _h, _hbr))
            except IOError:
                break
        return res

if __name__ == "__main__":
    for r, s, h, hbr in RFKill.list():
        print("%d: %s: %s" % (r.idx, r.name, r.type_name))
        print("\tSoft blocked: %s" % ("yes" if s else "no"))
        print("\tHard blocked: %s" % ("yes" if h else "no"))
        if hbr != None:
            print("\tHard block reasons: ", end="")
            if hbr == 0:
                print("[NONE]", end="")
            if hbr & HARD_BLOCK_NOT_OWNER:
                print("[NOT_OWNER]", end="")
            if hbr & HARD_BLOCK_SIGNAL:
                print("[SIGNAL]", end="")
            print()
