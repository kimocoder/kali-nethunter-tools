package psx

import (
	"fmt"
	"runtime"
	"sync"
	"syscall"
	"testing"
)

func TestSyscall3(t *testing.T) {
	want := syscall.Getpid()
	if got, _, err := Syscall3(syscall.SYS_GETPID, 0, 0, 0); err != 0 {
		t.Errorf("failed to get PID via libpsx: %v", err)
	} else if int(got) != want {
		t.Errorf("pid mismatch: got=%d want=%d", got, want)
	}
	if got, _, err := Syscall3(syscall.SYS_CAPGET, 0, 0, 0); err != 14 {
		t.Errorf("malformed capget returned %d: %v (want 14: %v)", err, err, syscall.Errno(14))
	} else if ^got != 0 {
		t.Errorf("malformed capget did not return -1, got=%d", got)
	}
}

func TestSyscall6(t *testing.T) {
	want := syscall.Getpid()
	if got, _, err := Syscall6(syscall.SYS_GETPID, 0, 0, 0, 0, 0, 0); err != 0 {
		t.Errorf("failed to get PID via libpsx: %v", err)
	} else if int(got) != want {
		t.Errorf("pid mismatch: got=%d want=%d", got, want)
	}
	if got, _, err := Syscall6(syscall.SYS_CAPGET, 0, 0, 0, 0, 0, 0); err != 14 {
		t.Errorf("malformed capget errno %d: %v (want 14: %v)", err, err, syscall.Errno(14))
	} else if ^got != 0 {
		t.Errorf("malformed capget did not return -1, got=%d", got)
	}
}

// killAThread locks the goroutine to a thread and exits. This has the
// effect of making the go runtime terminate the thread.
func killAThread(c <-chan struct{}) {
	runtime.LockOSThread()
	<-c
}

// Test state is mirrored as expected.
func TestShared(t *testing.T) {
	const prGetKeepCaps = 7
	const prSetKeepCaps = 8

	var wg sync.WaitGroup

	newTracker := func() (chan<- uintptr, <-chan string) {
		ch := make(chan uintptr)
		ex := make(chan string)
		go func() {
			runtime.LockOSThread()
			defer wg.Done()
			defer close(ex)
			tid := syscall.Gettid()
			for {
				if _, ok := <-ch; !ok {
					break
				}
				val, ok := <-ch
				if !ok {
					break
				}
				got, _, e := Syscall3(syscall.SYS_PRCTL, prGetKeepCaps, 0, 0)
				if e != 0 {
					ex <- fmt.Sprintf("[%d] psx:prctl(GET_KEEPCAPS) ?= %d failed: %v", tid, val, syscall.Errno(e))
					break
				}
				if got != val {
					t.Errorf("[%d] bad keepcaps value: got=%d, want=%d", tid, got, val)
				}
				if _, ok := <-ch; !ok {
					break
				}
			}
		}()
		return ch, ex
	}

	var tracked []chan<- uintptr
	var exes []<-chan string
	for i := 0; i <= 10; i++ {
		val := uintptr(i & 1)
		if _, _, e := Syscall3(syscall.SYS_PRCTL, prSetKeepCaps, val, 0); e != 0 {
			t.Fatalf("[%d] psx:prctl(SET_KEEPCAPS, %d) failed: %v", i, i&1, syscall.Errno(e))
		}
		wg.Add(1)
		tr, ex := newTracker()
		tracked, exes = append(tracked, tr), append(exes, ex)
		for i, ch := range tracked {
			ch <- 2 // start serialization.
			select {
			case ferr := <-exes[i]:
				t.Fatalf("%s", ferr)
			case ch <- val: // definitely written after change.
			}
			ch <- 3 // end serialization.
		}
	}
	for _, ch := range tracked {
		close(ch)
	}
	wg.Wait()
}
