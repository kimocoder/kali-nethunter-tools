// Testable examples.

package cap_test

import (
	"fmt"
	"log"
	"syscall"

	"kernel.org/pub/linux/libs/security/libcap/cap"
)

func ExampleSet_Fill() {
	c, err := cap.FromText("cap_setfcap=p")
	if err != nil {
		log.Fatalf("failed to parse: %v", err)
	}
	c.Fill(cap.Effective, cap.Permitted)
	c.ClearFlag(cap.Permitted)
	c.Fill(cap.Inheritable, cap.Effective)
	c.ClearFlag(cap.Effective)
	fmt.Println(c)
	// Output: cap_setfcap=i
}

func ExampleGetProc() {
	c := cap.GetProc()
	fmt.Printf("current process has these capabilities: %q\n", c)
}

func ExampleNewSet() {
	c := cap.NewSet()
	fmt.Printf("empty capability Set is: %q\n", c)
	// Output: empty capability Set is: "="
}

func ExampleMaxBits() {
	bits := cap.MaxBits()
	fmt.Printf("current kernel supports %d capabilities\n", bits)
	fmt.Printf("the most recently added is %d (%q)\n", bits-1, bits-1)
	fmt.Println("read documentation for it with commands like these:")
	fmt.Printf("\n    capsh --explain=%d\n", bits-1)
	fmt.Printf("    capsh --explain=%q\n", bits-1)
}

func ExampleIABGetProc() {
	iab := cap.IABGetProc()
	fmt.Printf("process inheritable IAB tuple is: [%s]\n", iab)
}

func ExampleNewIAB() {
	iab := cap.NewIAB()
	fmt.Printf("empty IAB tuple is: [%v]\n", iab)
	// Output: empty IAB tuple is: []
}

func ExampleSet_Export() {
	c, err := cap.FromText("cap_setuid=ep")
	if err != nil {
		log.Fatalf("failed to parse: %v", err)
	}
	b1, err := c.Export()
	if err != nil {
		log.Fatalf("export failed: %v", err)
	}
	fmt.Printf("default %q export: %02x\n", c, b1)
	cap.MinExtFlagSize = 0
	b2, err := c.Export()
	if err != nil {
		log.Fatalf("export failed: %v", err)
	}
	fmt.Printf("minimal %q export: %02x\n", c, b2)
	// Output:
	// default "cap_setuid=ep" export: 90c2015108808000000000000000000000000000000000000000000000
	// minimal "cap_setuid=ep" export: 90c2015101808000
}

func ExampleImport() {
	d := []byte{0x90, 0xc2, 0x01, 0x51, 0x01, 0x80, 0x80, 0x00}
	c, err := cap.Import(d)
	if err != nil {
		log.Fatalf("failed to parse: %v", err)
	}
	fmt.Printf("import of %02x is %q\n", d, c)
	// Output: import of 90c2015101808000 is "cap_setuid=ep"
}

func ExampleSetUID() {
	c := cap.GetProc()
	if on, err := c.GetFlag(cap.Permitted, cap.SETUID); err != nil {
		fmt.Printf("unable to determine cap_setuid permitted flag value: %v\n", err)
		return
	} else if !on {
		fmt.Println("no permitted capability, try: sudo setcap cap_setuid=p program")
		return
	}
	pre := syscall.Getuid()
	const nobodyUID = 65534
	if err := cap.SetUID(nobodyUID); err != nil {
		fmt.Printf("failed to set uid (%d): %v\n", nobodyUID, err)
		return
	}
	post := syscall.Getuid()
	fmt.Printf("UID was:%d, is now:%d (nobody=%v)\n", pre, post, post == nobodyUID)
	c = cap.GetProc()
	fmt.Printf("all effective capabilities should be lowered: %q\n", c)
}

func ExampleFromText() {
	ts := []string{"=p all+ei", "all=pie", "=pi all+e", "=eip"}
	expect, err := cap.FromText("=ie all+p")
	good := true
	if err != nil {
		fmt.Printf("failed to parse expected set: %v\n", err)
		good = false
	}
	for _, t := range ts {
		got, err := cap.FromText(t)
		if err != nil {
			fmt.Printf("failed to parse %q: %v\n", t, err)
			good = false
		}
		if cf, err := got.Cf(expect); err != nil || cf != 0 {
			fmt.Printf("comparison failed for %q got %q (want: %q): %v\n", t, got, expect, err)
			good = false
		}
	}
	fmt.Printf("all examples passed=%v\n", good)
	// Output: all examples passed=true
}

func ExampleFromName() {
	v := cap.SYS_CHROOT
	t, err := cap.FromName(v.String())
	if err != nil {
		fmt.Printf("failed to parse %q: %v", v, err)
		return
	}
	fmt.Printf("capability value %q of numerical value=%d correctly named\n", v, t)
	// Output: capability value "cap_sys_chroot" of numerical value=18 correctly named
}
