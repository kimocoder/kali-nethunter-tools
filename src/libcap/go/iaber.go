// Program iaber attempts to set an iab value and then exec itself
// with its remaining arguments. This is used to validate some
// behavior of IAB setting.
package main

import (
	"log"
	"os"
	"syscall"

	"kernel.org/pub/linux/libs/security/libcap/cap"
)

func main() {
	if len(os.Args) <= 1 {
		log.Print("success")
		return
	}
	if syscall.Getuid() != 1 {
		if err := cap.SetUID(1); err != nil {
			log.Fatalf("failed to setuid(1): %v", err)
		}
	}
	caps, iab := cap.GetProc(), cap.IABGetProc()
	log.Printf("current: %q [%q]", caps, iab)
	iab, err := cap.IABFromText(os.Args[1])
	if err != nil {
		log.Fatalf("failed to parse %q: %v", os.Args[1], err)
	}
	if err := iab.SetProc(); err != nil {
		log.Fatalf("unable to set IAB=%q: %v", iab, err)
	}
	caps, iab = cap.GetProc(), cap.IABGetProc()
	log.Printf("pre-exec: %q [%q]", caps, iab)
	err = syscall.Exec(os.Args[0], append([]string{os.Args[0]}, os.Args[2:]...), nil)
	log.Fatalf("exec %q failed: %v", os.Args[2:], err)
}
