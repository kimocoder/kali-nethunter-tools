//go:build linux && go1.16
// +build linux,go1.16

package psx

import (
	"syscall"
	"testing"
)

// Test to confirm no regression against [Go bug 42494].
//
// [Go bug 42494]: https://github.com/golang/go/issues/42494
func TestThreadChurn(t *testing.T) {
	const prSetKeepCaps = 8

	for j := 0; j < 4; j++ {
		kill := (j & 1) != 0
		sysc := (j & 2) != 0
		t.Logf("[%d] testing kill=%v, sysc=%v", j, kill, sysc)
		for i := 50; i > 0; i-- {
			if kill {
				c := make(chan struct{})
				go killAThread(c)
				close(c)
			}
			if sysc {
				if _, _, e := Syscall3(syscall.SYS_PRCTL, prSetKeepCaps, uintptr(i&1), 0); e != 0 {
					t.Fatalf("[%d] psx:prctl(SET_KEEPCAPS, %d) failed: %v", i, i&1, syscall.Errno(e))
				}
			}
		}
		t.Logf("[%d] PASSED kill=%v, sysc=%v", j, kill, sysc)
	}
}
